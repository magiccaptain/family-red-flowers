import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_flowers/data/garden_store.dart';
import 'package:red_flowers/main.dart';
import 'package:red_flowers/ui/illustrations.dart';

import 'garden_store_test.dart' show MemoryRepository;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'add two children, reward with animation, redeem and switch independently',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = GardenStore(MemoryRepository());
      addTearDown(store.dispose);
      await tester.pumpWidget(FlowerGardenApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('添加第一位小朋友'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('add_child')));
      await tester.enterText(find.byKey(const Key('child_name')), '朵朵');
      await tester.enterText(find.byKey(const Key('child_balance')), '20');
      await tapVisible(tester, find.byKey(const Key('save_child')));
      final firstId = store.selectedChild!.id;
      expect(store.selectedChild!.balance, 20);

      await tester.enterText(find.byKey(const Key('reward_amount')), '3');
      await tester.enterText(find.byKey(const Key('reward_reason')), '认真读书');
      await tester.ensureVisible(find.byKey(const Key('give_reward')));
      await tester.tap(find.byKey(const Key('give_reward')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Celebration), findsOneWidget);
      expect(find.text('太棒啦，朵朵！'), findsOneWidget);
      expect(store.selectedChild!.balance, 23);
      await tester.pumpAndSettle();
      expect(find.byType(Celebration), findsNothing);

      await tapVisible(tester, find.byKey(const Key('nav_1')));
      await tapVisible(tester, find.byKey(const Key('custom_exchange')));
      await tester.enterText(find.byKey(const Key('exchange_amount')), '24');
      await tester.enterText(find.byKey(const Key('exchange_reason')), '买绘本');
      await tapVisible(tester, find.byKey(const Key('confirm_exchange')));
      expect(find.text('小红花不够啦，目前有 23 朵'), findsOneWidget);
      expect(store.selectedChild!.balance, 23);
      await tester.enterText(find.byKey(const Key('exchange_amount')), '10');
      await tester.pump();
      expect(find.text('小红花不够啦，目前有 23 朵'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('confirm_exchange')));
      expect(store.selectedChild!.balance, 13);
      expect(find.text('买绘本'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('add_child')));
      await tester.enterText(find.byKey(const Key('child_name')), '小宇');
      await tester.enterText(find.byKey(const Key('child_balance')), '5');
      await tapVisible(tester, find.byKey(const Key('save_child')));
      expect(store.selectedChild!.balance, 5);
      expect(find.text('买绘本'), findsNothing);
      await tapVisible(tester, find.byKey(Key('child_$firstId')));
      expect(store.selectedChild!.balance, 13);
      await tapVisible(tester, find.byKey(const Key('nav_2')));
      expect(find.text('认真读书'), findsOneWidget);
      expect(find.text('买绘本'), findsOneWidget);
      await tapVisible(tester, find.text('兑换'));
      expect(find.text('认真读书'), findsNothing);
      expect(find.text('买绘本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1280, 800),
    const Size(800, 1280),
    const Size(390, 844),
    const Size(320, 640),
    const Size(1024, 600),
  ]) {
    testWidgets(
      'all screens fit ${size.width.toInt()}×${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = GardenStore(MemoryRepository());
        addTearDown(store.dispose);
        await store.addChild(name: '名字稍微长一点的小朋友', avatar: 3, balance: 999999);
        await tester.pumpWidget(FlowerGardenApp(store: store));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final page in [1, 2, 0]) {
          if (size.width >= 1000) {
            await tapVisible(tester, find.byKey(Key('nav_$page')));
          } else {
            await tester.tap(find.byType(NavigationDestination).at(page));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        }
        await tapVisible(tester, find.byKey(const Key('edit_child')));
        expect(find.text('管理小朋友'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed local save shows an error without celebrating', (
    tester,
  ) async {
    final repository = MemoryRepository();
    final store = GardenStore(repository);
    addTearDown(store.dispose);
    await store.addChild(name: '朵朵', avatar: 1, balance: 5);
    await tester.pumpWidget(FlowerGardenApp(store: store));
    await tester.pumpAndSettle();
    repository.failSave = true;
    await tapVisible(tester, find.byKey(const Key('give_reward')));
    expect(find.byType(Celebration), findsNothing);
    expect(store.selectedChild!.balance, 5);
    expect(find.text('保存失败，请重试。此次操作尚未生效。'), findsOneWidget);
  });
}
