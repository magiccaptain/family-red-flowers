import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:red_flowers/data/garden_store.dart';
import 'package:red_flowers/data/pg_config.dart';
import 'package:red_flowers/data/pg_repository.dart';
import 'package:red_flowers/main.dart';
import 'package:red_flowers/ui/illustrations.dart';

import 'garden_store_test.dart' show MemoryRepository;
import 'garden_widget_test.dart' show tapVisible;
import 'pg_repository_test.dart'
    show ControlledGateway, MemorySettings, sampleGarden, testConfig;

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  for (final size in [
    const Size(320, 640),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets('cloud toolbar and settings fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = ControlledGateway()..data = await sampleGarden();
      final repository = PgGardenRepository(
        gateway: gateway,
        settings: MemorySettings(),
        preferences: SharedPreferencesAsync(),
        legacy: MemoryRepository(),
      );
      final store = GardenStore(repository);
      await tester.pumpWidget(FlowerGardenApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloud_sync')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.byKey(const Key('cloud_settings')));
      expect(find.text('连接家里的小花园'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('pg_password')))
            .obscureText,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets(
    'first launch shows connection form, with no invented local garden',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = PgGardenRepository(
        gateway: ControlledGateway(),
        settings: MemorySettings(null),
        preferences: SharedPreferencesAsync(),
        legacy: MemoryRepository(),
      );
      final store = GardenStore(repository);
      addTearDown(store.dispose);
      await tester.pumpWidget(FlowerGardenApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('连接家里的小花园'), findsOneWidget);
      expect(find.byKey(const Key('pg_host')), findsOneWidget);
      expect(find.text('添加第一位小朋友'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pasting connection config updates the selected TLS mode', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {
              'text': jsonEncode({
                ...testConfig.toJson(),
                'sslMode': 'disable',
              }),
            };
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final store = GardenStore(
      PgGardenRepository(
        gateway: ControlledGateway(),
        settings: MemorySettings(null),
        preferences: SharedPreferencesAsync(),
        legacy: MemoryRepository(),
      ),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(FlowerGardenApp(store: store));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('paste_pg_config')));
    final dropdown = tester.state<FormFieldState<String>>(
      find.byKey(const Key('pg_ssl_mode')),
    );
    expect(dropdown.value, 'disable');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('pg_host')))
          .controller!
          .text,
      testConfig.host,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('family preset opens the garden without a connection form', (
    tester,
  ) async {
    final store = GardenStore(
      PgGardenRepository(
        gateway: ControlledGateway(),
        settings: MemorySettings(null),
        preferences: SharedPreferencesAsync(),
        legacy: MemoryRepository(),
        presetConfigLoader: () => testConfig,
      ),
    );
    await tester.pumpWidget(FlowerGardenApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cloud_sync')), findsOneWidget);
    expect(find.byKey(const Key('connect_pg')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'failed first preset connection can be retried without entering credentials',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = ControlledGateway()
        ..readError = const PgFailure('暂时无法连接家庭云端', transport: true);
      final store = GardenStore(
        PgGardenRepository(
          gateway: gateway,
          settings: MemorySettings(null),
          preferences: SharedPreferencesAsync(),
          legacy: MemoryRepository(),
          presetConfigLoader: () => testConfig,
        ),
      );
      await tester.pumpWidget(FlowerGardenApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('retry_pg')), findsOneWidget);
      expect(find.byKey(const Key('pg_host')), findsNothing);
      expect(tester.takeException(), isNull);
      gateway.readError = null;
      await tapVisible(tester, find.byKey(const Key('retry_pg')));
      expect(find.byKey(const Key('cloud_sync')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'failed cloud write does not change flowers or play celebration',
    (tester) async {
      final gateway = ControlledGateway()..data = await sampleGarden();
      final repository = PgGardenRepository(
        gateway: gateway,
        settings: MemorySettings(),
        preferences: SharedPreferencesAsync(),
        legacy: MemoryRepository(),
      );
      final store = GardenStore(repository);
      await tester.pumpWidget(FlowerGardenApp(store: store));
      await tester.pumpAndSettle();
      gateway.applyError = const PgFailure('暂时无法连接家庭云端', transport: true);
      await tapVisible(tester, find.byKey(const Key('give_reward')));
      expect(store.selectedChild!.balance, 12);
      expect(find.byType(Celebration), findsNothing);
      expect(find.text('暂时无法连接家庭云端'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
