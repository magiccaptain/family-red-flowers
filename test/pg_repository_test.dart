import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:red_flowers/data/garden.dart';
import 'package:red_flowers/data/garden_command.dart';
import 'package:red_flowers/data/garden_store.dart';
import 'package:red_flowers/data/pg_config.dart';
import 'package:red_flowers/data/pg_gateway.dart';
import 'package:red_flowers/data/pg_repository.dart';

import 'garden_store_test.dart' show MemoryRepository;

const testConfig = PgConfig(
  host: 'test.invalid',
  database: 'postgres',
  username: 'test-family',
  password: 'test-password',
  familyId: 'test-family-id',
);

class MemorySettings implements PgSettingsStore {
  MemorySettings([this.config = testConfig]);
  PgConfig? config;
  @override
  Future<PgConfig?> read() async => config;
  @override
  Future<void> write(PgConfig value) async => config = value;
}

class ControlledGateway implements PgGateway {
  GardenData data = GardenData();
  PgFailure? readError;
  PgFailure? applyError;
  bool loseNextResponse = false;
  final commands = <GardenCommand>[];
  Map<String, dynamic> get snapshot => {
    'familyId': 'test-family-id',
    'revision': commands.length,
    'garden': jsonDecode(data.encode()),
  };
  @override
  Future<Map<String, dynamic>> read(PgConfig config) async {
    if (readError != null) throw readError!;
    return snapshot;
  }

  @override
  Future<Map<String, dynamic>> apply(
    PgConfig config,
    GardenCommand command,
  ) async {
    commands.add(command);
    if (applyError != null) throw applyError!;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const PgFailure('响应丢失', uncertain: true, transport: true);
    }
    return snapshot;
  }

  @override
  Future<PgConfig?> developerConfig() async => null;
}

Future<GardenData> sampleGarden() async {
  final local = MemoryRepository();
  final store = GardenStore(local);
  await store.addChild(name: '测试小朋友', avatar: 1, balance: 10);
  await store.reward(childId: store.selectedChild!.id, amount: 2, reason: '学习');
  store.dispose();
  return GardenData.decode(local.raw!);
}

void main() {
  late ControlledGateway gateway;
  late MemorySettings settings;
  late SharedPreferencesAsync preferences;
  late MemoryRepository legacy;
  PgGardenRepository repository() => PgGardenRepository(
    gateway: gateway,
    settings: settings,
    preferences: preferences,
    legacy: legacy,
  );
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    gateway = ControlledGateway();
    settings = MemorySettings();
    preferences = SharedPreferencesAsync();
    legacy = MemoryRepository();
  });

  test('missing connection asks for configuration rather than silently saving locally', () async {
    settings.config = null;
    await expectLater(
      repository().load(),
      throwsA(isA<PgConfigurationMissing>()),
    );
    expect(legacy.writes, 0);
  });

  test(
    'existing local data is imported once and the local backup is preserved',
    () async {
      final original = await sampleGarden();
      legacy.raw = original.encode();
      gateway.data = original;
      final repo = repository();
      await repo.load();
      expect(gateway.commands.single.kind, 'import_local');
      expect(legacy.raw, original.encode());
      await repository().load();
      expect(gateway.commands, hasLength(1));
      expect(legacy.writes, 0);
    },
  );

  test(
    'fresh install connects using the preset without saved credentials',
    () async {
      settings.config = null;
      final repo = PgGardenRepository(
        gateway: gateway,
        settings: settings,
        preferences: preferences,
        legacy: legacy,
        presetConfigLoader: () => testConfig,
      );
      await repo.load();
      expect(repo.config, same(testConfig));
      expect(repo.offline, isFalse);
      expect(repo.lastSyncAt, isNotNull);
      expect(settings.config, isNull);
    },
  );

  test('saved device settings take precedence over the APK preset', () async {
    final repo = PgGardenRepository(
      gateway: gateway,
      settings: settings,
      presetConfigLoader: () => throw StateError('Preset should not be used'),
    );
    expect(await repo.savedConfig(), same(testConfig));
  });

  test(
    'a lost reply survives restart and retries the original operation ID',
    () async {
      final repo = repository();
      await repo.load();
      gateway.data = await sampleGarden();
      gateway.loseNextResponse = true;
      final call = GardenCommand('reward', {
        'childId': 'child',
        'amount': 2,
        'reason': '学习',
      });
      await expectLater(repo.apply(call), throwsA(isA<GardenException>()));
      expect(repo.hasPending, isTrue);
      final restarted = repository();
      final data = await restarted.load();
      expect(data.children.single.balance, 12);
      expect(gateway.commands.map((c) => c.id), [call.id, call.id]);
      expect(restarted.hasPending, isFalse);
    },
  );

  test('skipping local migration remains skipped after restarting', () async {
    final original = await sampleGarden();
    legacy.raw = original.encode();
    final repo = repository();
    await repo.configure(testConfig, importLocal: false);
    await repository().load();
    expect(gateway.commands, isEmpty);
    expect(legacy.raw, original.encode());
    await repo.configure(testConfig, importLocal: true);
    expect(gateway.commands.single.kind, 'import_local');
  });

  test(
    'a different write is blocked while an earlier response is uncertain',
    () async {
      final repo = repository();
      await repo.load();
      gateway.loseNextResponse = true;
      final call = GardenCommand('reward', {
        'childId': 'child',
        'amount': 2,
        'reason': '学习',
      });
      await expectLater(repo.apply(call), throwsA(isA<GardenException>()));
      await expectLater(
        repo.apply(
          GardenCommand('exchange', {
            'childId': 'child',
            'amount': 1,
            'reason': '兑换',
          }),
        ),
        throwsA(isA<GardenException>()),
      );
      expect(gateway.commands, hasLength(1));
      expect(repo.hasPending, isTrue);
    },
  );

  test(
    'retrying the same create intent preserves both operation and child IDs',
    () async {
      final repo = repository();
      await repo.load();
      final first = GardenCommand('add_child', {
        'childId': 'original',
        'name': '测试',
        'avatar': 1,
        'balance': 0,
      });
      gateway.loseNextResponse = true;
      await expectLater(repo.apply(first), throwsA(isA<GardenException>()));
      await repo.apply(
        GardenCommand('add_child', {
          'childId': 'new-tentative',
          'name': '测试',
          'avatar': 1,
          'balance': 0,
        }),
      );
      expect(gateway.commands.last.id, first.id);
      expect(gateway.commands.last.payload['childId'], 'original');
    },
  );

  test(
    'offline startup displays the last confirmed cache without local writes',
    () async {
      gateway.data = await sampleGarden();
      await repository().load();
      gateway.readError = const PgFailure('断网', transport: true);
      final offline = repository();
      final data = await offline.load();
      expect(data.children.single.balance, 12);
      expect(offline.offline, isTrue);
      expect(legacy.writes, 0);
    },
  );

  test('a definitive database rejection clears the pending marker and preserves cache', () async {
    gateway.data = await sampleGarden();
    final repo = repository();
    await repo.load();
    gateway.applyError = const PgFailure('小红花不够');
    await expectLater(
      repo.apply(
        GardenCommand('exchange', {
          'childId': 'child',
          'amount': 100,
          'reason': '兑换',
        }),
      ),
      throwsA(isA<GardenException>()),
    );
    expect(repo.hasPending, isFalse);
    gateway.readError = const PgFailure('断网', transport: true);
    final cached = await repository().load();
    expect(cached.children.single.balance, 12);
  });

  test('credentials stay out of garden cache, pending operations, and debug descriptions', () async {
    final repo = repository();
    await repo.load();
    gateway.loseNextResponse = true;
    await expectLater(
      repo.apply(
        GardenCommand('reward', {
          'childId': 'child',
          'amount': 1,
          'reason': '学习',
        }),
      ),
      throwsA(isA<GardenException>()),
    );
    final all = await preferences.getAll();
    expect(jsonEncode(all), isNot(contains('test-password')));
    expect(testConfig.toString(), isNot(contains('test-password')));
  });
}
