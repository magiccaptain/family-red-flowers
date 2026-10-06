import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:red_flowers/data/garden.dart';
import 'package:red_flowers/data/garden_store.dart';
import 'package:red_flowers/data/pg_repository.dart';
import 'package:red_flowers/main.dart';
import 'package:red_flowers/ui/illustrations.dart';

import 'garden_store_test.dart' show MemoryRepository;
import 'garden_widget_test.dart' show tapVisible;
import 'pg_repository_test.dart' show ControlledGateway, MemorySettings;

void viewport(WidgetTester tester, Size size, {double scale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> capture(WidgetTester tester, String name) async {
  if (Platform.environment['RF_PHONE_SCREENSHOTS'] != '1') return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('phone_capture')),
    );
    final bitmap = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File('artifacts/screenshots/phone-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    final font = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.otf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDownAll(() {
    WidgetController.hitTestWarningShouldBeFatal = false;
  });
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final (size, scale) in [
    (const Size(320, 640), 1.5),
    (const Size(360, 800), 1.0),
    (const Size(393, 852), 1.3),
    (const Size(412, 915), 1.0),
    (const Size(800, 360), 1.0),
  ]) {
    testWidgets('cloud pages and exchange fit $size at text scale $scale', (
      tester,
    ) async {
      viewport(tester, size, scale: scale);
      final local = MemoryRepository();
      final seed = GardenStore(local, now: () => DateTime(2024, 1, 2));
      await seed.addChild(name: '名字稍微长一点的小朋友', avatar: 3, balance: 999990);
      final childId = seed.selectedChild!.id;
      await seed.reward(
        childId: childId,
        amount: 9,
        reason: '认真学习并且主动帮家里做家务'.padRight(80, '好'),
      );
      await seed.exchange(
        childId: childId,
        amount: 777777,
        reason: '兑换了期待已久的亲子活动'.padRight(80, '好'),
      );
      await seed.addChild(name: '二宝', avatar: 1, balance: 10);
      await seed.selectChild(childId);
      seed.dispose();
      final gateway = ControlledGateway()..data = GardenData.decode(local.raw!);
      final store = GardenStore(
        PgGardenRepository(
          gateway: gateway,
          settings: MemorySettings(),
          preferences: SharedPreferencesAsync(),
          legacy: MemoryRepository(),
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('phone_capture'),
          child: FlowerGardenApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('cloud_sync')), findsOneWidget);
      await capture(tester, '${size.width.toInt()}-garden');
      await tapVisible(tester, find.byKey(const Key('cloud_settings')));
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('返回小花园'));
      for (final page in [1, 2, 0]) {
        await tester.tap(find.byType(NavigationDestination).at(page));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, '${size.width.toInt()}-page-$page');
      }
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('custom_exchange')));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('exchange_reason')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exchange_reason')));
      tester.view.viewInsets = FakeViewPadding(
        bottom: size.height > 500 ? 280 : 150,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('confirm_exchange')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('confirm_exchange')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, '${size.width.toInt()}-keyboard');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets(
    'phone can add, edit, reward with animation, redeem, and switch children',
    (tester) async {
      viewport(tester, const Size(360, 800));
      final store = GardenStore(MemoryRepository());
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('phone_capture'),
          child: FlowerGardenApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('add_child')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('child_name')), '朵朵');
      await tester.enterText(find.byKey(const Key('child_balance')), '20');
      await tapVisible(tester, find.byKey(const Key('save_child')));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(store.selectedChild!.balance, 20);
      await tapVisible(tester, find.byKey(const Key('edit_child')));
      await tester.enterText(find.byKey(const Key('child_name')), '手机上的朵朵');
      await tapVisible(tester, find.byKey(const Key('save_child')));
      expect(store.selectedChild!.name, '手机上的朵朵');
      await capture(tester, '360-family');
      await tester.ensureVisible(find.byKey(const Key('reward_amount')));
      await tester.enterText(find.byKey(const Key('reward_amount')), '3');
      await tester.enterText(find.byKey(const Key('reward_reason')), '主动整理玩具');
      await tester.ensureVisible(find.byKey(const Key('give_reward')));
      await tester.tap(find.byKey(const Key('give_reward')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Celebration), findsOneWidget);
      expect(store.selectedChild!.balance, 23);
      expect(tester.takeException(), isNull);
      await capture(tester, '360-celebration');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('custom_exchange')));
      await tester.enterText(find.byKey(const Key('exchange_amount')), '5');
      await tester.enterText(
        find.byKey(const Key('exchange_reason')),
        '兑换一本绘本',
      );
      await tapVisible(tester, find.byKey(const Key('confirm_exchange')));
      expect(store.selectedChild!.balance, 18);
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('add_child')));
      await tester.enterText(find.byKey(const Key('child_name')), '二宝');
      await tapVisible(tester, find.byKey(const Key('save_child')));
      final first = store.children.first;
      await tapVisible(tester, find.byKey(Key('child_${first.id}')));
      expect(store.selectedChild!.balance, 18);
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('兑换一本绘本'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'long-name celebration fits a small phone while the keyboard is closing',
    (tester) async {
      viewport(tester, const Size(320, 640), scale: 1.5);
      final store = GardenStore(MemoryRepository());
      await store.addChild(name: '名字稍微长一点的小朋友', avatar: 1, balance: 1);
      await tester.pumpWidget(FlowerGardenApp(store: store));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('give_reward')));
      await tester.tap(find.byKey(const Key('give_reward')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Celebration), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
