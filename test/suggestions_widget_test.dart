import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_flowers/data/garden_store.dart';
import 'package:red_flowers/main.dart';

import 'garden_store_test.dart' show MemoryRepository;
import 'garden_widget_test.dart' show tapVisible;
import 'phone_widget_test.dart' show capture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.otf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  for (final size in [const Size(1280, 1000), const Size(320, 640)]) {
    testWidgets('edit suggestions and redeem on ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = size.width < 600
          ? 1.5
          : 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = MemoryRepository();
      final store = GardenStore(repository);
      addTearDown(store.dispose);
      await store.addChild(name: '朵朵', avatar: 1, balance: 999999);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('phone_capture'),
          child: FlowerGardenApp(store: store),
        ),
      );
      await tester.pumpAndSettle();

      for (final reason in ['英语打卡', '单词打卡', '体育打卡', '早睡早起']) {
        expect(find.text(reason), findsOneWidget);
      }
      expect(find.text('认真学习'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('edit_reward_reasons')));
      await capture(tester, '${size.width.toInt()}-reward-settings');
      await tester.enterText(
        find.byKey(const Key('suggestion_title_0')),
        '阅读打卡',
      );
      await tapVisible(tester, find.byKey(const Key('remove_suggestion_1')));
      await tapVisible(tester, find.byKey(const Key('add_suggestion')));
      await tester.ensureVisible(find.byKey(const Key('suggestion_title_4')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('suggestion_title_4')),
        '整理书包',
      );
      await tapVisible(tester, find.byKey(const Key('save_suggestions')));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(store.rewardReasons, ['阅读打卡', '体育打卡', '早睡早起', '整理书包']);
      await tapVisible(tester, find.text('整理书包'));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('reward_reason')))
            .controller!
            .text,
        '整理书包',
      );

      if (size.width >= 1000) {
        await tapVisible(tester, find.byKey(const Key('nav_1')));
      } else {
        await tester.tap(find.byType(NavigationDestination).at(1));
        await tester.pumpAndSettle();
      }
      expect(find.text('看10分钟喜欢的动画'), findsOneWidget);
      await capture(tester, '${size.width.toInt()}-wish-defaults');
      for (final old in ['看一集喜欢的动画', '周末去公园玩', '挑一本喜欢的绘本']) {
        expect(find.text(old), findsNothing);
      }
      await tapVisible(tester, find.byKey(const Key('edit_wish_suggestions')));
      await capture(tester, '${size.width.toInt()}-wish-settings');
      await tester.enterText(
        find.byKey(const Key('suggestion_title_0')),
        '一起拼图',
      );
      await tester.enterText(
        find.byKey(const Key('suggestion_amount_0')),
        '999999',
      );
      await tapVisible(tester, find.byKey(const Key('add_suggestion')));
      await tester.enterText(
        find.byKey(const Key('suggestion_title_1')),
        '选择晚餐',
      );
      await tester.enterText(find.byKey(const Key('suggestion_amount_1')), '6');
      await tapVisible(tester, find.byKey(const Key('save_suggestions')));
      expect(store.wishSuggestions.map((wish) => wish.title), ['一起拼图', '选择晚餐']);
      expect(store.wishSuggestions.first.amount, 999999);
      await capture(tester, '${size.width.toInt()}-custom-wishes');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('去兑换').first);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('exchange_amount')))
            .controller!
            .text,
        '999999',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('exchange_reason')))
            .controller!
            .text,
        '一起拼图',
      );
      await tapVisible(tester, find.byKey(const Key('confirm_exchange')));
      expect(store.selectedChild!.balance, 0);
      expect(store.selectedEntries.first.reason, '一起拼图');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.load();
      expect(store.rewardReasons.last, '整理书包');
      expect(store.wishSuggestions.first.amount, 999999);
    });
  }

  testWidgets(
    'cancelling, invalid values and failed saves retain suggestions',
    (tester) async {
      final repository = MemoryRepository();
      final store = GardenStore(repository);
      addTearDown(store.dispose);
      await tester.pumpWidget(FlowerGardenApp(store: store));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('edit_reward_reasons')));
      await tester.enterText(
        find.byKey(const Key('suggestion_title_0')),
        '未保存',
      );
      await tapVisible(tester, find.byTooltip('关闭'));
      expect(store.rewardReasons.first, '英语打卡');
      await tapVisible(tester, find.byKey(const Key('edit_reward_reasons')));
      await tester.enterText(find.byKey(const Key('suggestion_title_0')), '');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('save_suggestions')));
      expect(find.text('请填写名称，或删除这一项'), findsOneWidget);
      expect(store.rewardReasons.first, '英语打卡');
      await tester.enterText(
        find.byKey(const Key('suggestion_title_0')),
        '阅读打卡',
      );
      repository.failSave = true;
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('save_suggestions')));
      expect(find.text('保存失败，请重试。此次操作尚未生效。'), findsOneWidget);
      expect(store.rewardReasons.first, '英语打卡');
      repository.failSave = false;
      await tapVisible(tester, find.byKey(const Key('save_suggestions')));
      expect(store.rewardReasons.first, '阅读打卡');
      expect(tester.takeException(), isNull);
    },
  );
}
