import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:red_flowers/data/garden_store.dart';
import 'package:red_flowers/data/garden.dart';
import 'package:red_flowers/data/pg_config.dart';
import 'package:red_flowers/data/pg_preset.dart';
import 'package:red_flowers/data/pg_repository.dart';

import 'garden_store_test.dart' show MemoryRepository;
import 'pg_repository_test.dart' show MemorySettings;

void main() {
  final path = Platform.environment['RF_PG_TEST_CONFIG'];
  test(
    'Dart native PG driver saves all features and reloads from a second device',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final config = PgConfig.parse(await File(path!).readAsString());
      final preferences = SharedPreferencesAsync();
      PgGardenRepository repository() => PgGardenRepository(
        settings: MemorySettings(config),
        preferences: preferences,
        legacy: MemoryRepository(),
      );
      final first = GardenStore(repository());
      final second = GardenStore(repository());
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.load();
      await first.addChild(name: '原生连接验证', avatar: 1, balance: 20);
      final child = first.selectedChild!.id;
      await second.load();
      expect(second.selectedChild!.id, child);
      expect(second.selectedChild!.balance, 20);
      await first.updateRewardReasons([
        '英语打卡',
        '阅读打卡',
      ], previousReasons: first.rewardReasons);
      await first.updateWishSuggestions([
        const WishSuggestion(title: '看10分钟喜欢的动画', amount: 8),
        const WishSuggestion(title: '一起拼图', amount: 6),
      ], previousWishes: first.wishSuggestions);
      await second.refresh();
      expect(second.rewardReasons, ['英语打卡', '阅读打卡']);
      expect(second.wishSuggestions.map((wish) => wish.title), [
        '看10分钟喜欢的动画',
        '一起拼图',
      ]);
      expect(second.wishSuggestions.first.amount, 8);
      await Future.wait([
        first.reward(childId: child, amount: 1, reason: '第一台设备奖励'),
        second.reward(childId: child, amount: 2, reason: '第二台设备奖励'),
      ]);
      await first.refresh();
      expect(first.selectedChild!.balance, 23);
      await first.exchange(childId: child, amount: 10, reason: '原生兑换绘本');
      await first.updateChild(id: child, name: '修改昵称', avatar: 3, balance: 8);
      await first.addChild(name: '第二位', avatar: 2, balance: 7);
      await first.selectChild(child);
      await second.refresh();
      expect(second.children, hasLength(2));
      expect(second.selectedChild!.balance, 8);
      expect(second.selectedChild!.name, '修改昵称');
      expect(second.selectedChild!.avatar, 3);
      expect(second.totalRewarded, 3);
      expect(second.totalExchanged, 10);
      expect(second.selectedEntries.first.kind.name, 'adjustment');
      expect(
        second.selectedEntries
            .where((e) => e.kind.name == 'exchange')
            .single
            .reason,
        '原生兑换绘本',
      );
      expect(second.offline, isFalse);
      expect(second.hasPending, isFalse);
      expect(second.rewardReasons, ['英语打卡', '阅读打卡']);
      expect(second.wishSuggestions.first.amount, 8);
    },
    skip: path == null
        ? 'Run scripts/test-pg.sh for the isolated real-PG fixture'
        : false,
  );

  test(
    'compiled family preset connects without saved device settings',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final expected = PgConfig.parse(await File(path!).readAsString());
      final preset = loadPresetPgConfig();
      expect(preset, isNotNull);
      expect(preset!.familyId, expected.familyId);
      final preferences = SharedPreferencesAsync();
      PgGardenRepository repository() => PgGardenRepository(
        settings: MemorySettings(null),
        preferences: preferences,
        legacy: MemoryRepository(),
      );
      final firstRepository = repository();
      final first = GardenStore(firstRepository);
      final second = GardenStore(repository());
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.load();
      expect(firstRepository.config!.familyId, expected.familyId);
      expect(first.offline, isFalse);
      await first.addChild(name: '预置连接验证', avatar: 1, balance: 2);
      final childId = first.selectedChild!.id;
      await second.load();
      expect(second.selectedChild!.id, childId);
      expect(second.selectedChild!.balance, 2);
      expect(second.hasPending, isFalse);
    },
    skip: path == null || loadPresetPgConfig() == null
        ? 'Run scripts/test-pg.sh for the isolated compiled preset fixture'
        : false,
  );
}
