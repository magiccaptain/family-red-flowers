import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:red_flowers/data/garden.dart';
import 'package:red_flowers/data/garden_store.dart';

class MemoryRepository implements GardenRepository {
  String? raw;
  bool failSave = false;
  Completer<void>? pendingSave;
  int writes = 0;
  @override
  Future<GardenData> load() async =>
      raw == null ? GardenData() : GardenData.decode(raw!);
  @override
  Future<void> save(GardenData data) async {
    writes++;
    if (pendingSave != null) await pendingSave!.future;
    if (failSave) throw Exception('disk unavailable');
    raw = data.encode();
  }
}

void main() {
  late MemoryRepository repository;
  late GardenStore store;
  final now = DateTime(2026, 10, 6, 12, 30);
  setUp(() {
    repository = MemoryRepository();
    store = GardenStore(repository, now: () => now);
  });
  tearDown(() => store.dispose());

  test('first launch starts with no invented children or entries', () async {
    await store.load();
    expect(store.children, isEmpty);
    expect(store.selectedChild, isNull);
    expect(repository.writes, 0);
  });

  test(
    'old snapshots receive new defaults without changing the ledger',
    () async {
      await store.addChild(name: '朵朵', avatar: 1, balance: 10);
      final json = jsonDecode(repository.raw!) as Map<String, dynamic>;
      json.remove('rewardReasons');
      json.remove('wishSuggestions');
      repository.raw = jsonEncode(json);
      await store.load();
      expect(store.rewardReasons, ['英语打卡', '单词打卡', '体育打卡', '早睡早起']);
      expect(store.wishSuggestions.single.title, '看10分钟喜欢的动画');
      expect(store.wishSuggestions.single.amount, 5);
      expect(store.selectedChild!.balance, 10);
      expect(store.selectedEntries, hasLength(1));
    },
  );

  test(
    'custom suggestions survive transactions, child switches and restart',
    () async {
      await store.updateRewardReasons([
        ' 阅读打卡 ',
        '早睡早起',
      ], previousReasons: store.rewardReasons);
      await store.updateWishSuggestions([
        const WishSuggestion(title: ' 拼图时间 ', amount: 8),
      ], previousWishes: store.wishSuggestions);
      await store.addChild(name: '朵朵', avatar: 1, balance: 10);
      final first = store.selectedChild!.id;
      await store.reward(childId: first, amount: 2, reason: '阅读打卡');
      await store.exchange(childId: first, amount: 8, reason: '拼图时间');
      await store.updateChild(id: first, name: '花花', avatar: 2, balance: 4);
      await store.addChild(name: '小宇', avatar: 0, balance: 1);
      await store.selectChild(first);
      final reloaded = GardenStore(repository);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.rewardReasons, ['阅读打卡', '早睡早起']);
      expect(reloaded.wishSuggestions.single.title, '拼图时间');
      expect(reloaded.wishSuggestions.single.amount, 8);
      expect(reloaded.selectedChild!.balance, 4);
      final ledger = repository.raw!;
      await reloaded.updateWishSuggestions(
        [],
        previousWishes: reloaded.wishSuggestions,
      );
      await reloaded.updateRewardReasons(
        [],
        previousReasons: reloaded.rewardReasons,
      );
      await reloaded.load();
      expect(reloaded.rewardReasons, isEmpty);
      expect(reloaded.wishSuggestions, isEmpty);
      expect(
        reloaded.selectedEntries.length,
        GardenData.decode(ledger).entries
            .where((e) => e.childId == first)
            .length,
      );
    },
  );

  test(
    'invalid, stale and failed suggestion saves preserve stored settings',
    () async {
      await store.load();
      final defaults = store.rewardReasons;
      for (final reasons in [
        [' '],
        ['打卡', ' 打卡 '],
        List.filled(21, '打卡'),
      ]) {
        await expectLater(
          store.updateRewardReasons(reasons, previousReasons: defaults),
          throwsA(isA<GardenException>()),
        );
      }
      for (final amount in [0, -1, 1000000]) {
        await expectLater(
          store.updateWishSuggestions([
            WishSuggestion(title: '动画', amount: amount),
          ], previousWishes: store.wishSuggestions),
          throwsA(isA<GardenException>()),
        );
      }
      expect(repository.writes, 0);
      await store.updateRewardReasons(['阅读'], previousReasons: defaults);
      await expectLater(
        store.updateRewardReasons(['跑步'], previousReasons: defaults),
        throwsA(isA<GardenException>()),
      );
      final before = repository.raw;
      repository.failSave = true;
      await expectLater(
        store.updateWishSuggestions([], previousWishes: store.wishSuggestions),
        throwsA(isA<GardenException>()),
      );
      expect(repository.raw, before);
      expect(store.rewardReasons, ['阅读']);
      expect(store.wishSuggestions.single.title, '看10分钟喜欢的动画');
    },
  );

  test(
    'each child has independent balance and ledger across restart',
    () async {
      await store.addChild(name: '  朵朵  ', avatar: 1, balance: 20);
      final first = store.selectedChild!.id;
      await store.reward(childId: first, amount: 3, reason: '认真学习');
      await store.exchange(childId: first, amount: 10, reason: '一本绘本');
      await store.addChild(name: '小宇', avatar: 0, balance: 7);
      final second = store.selectedChild!.id;
      expect(first, isNot(second));
      expect(store.selectedChild!.balance, 7);
      expect(store.selectedEntries, hasLength(1));
      await store.selectChild(first);
      expect(store.selectedChild!.name, '朵朵');
      expect(store.selectedChild!.balance, 13);
      expect(store.totalRewarded, 3);
      expect(store.totalExchanged, 10);
      expect(store.todayRewarded, 3);
      final reloaded = GardenStore(repository);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.selectedChild!.id, first);
      expect(reloaded.selectedChild!.balance, 13);
      final redemption = reloaded.selectedEntries.first;
      expect(redemption.amount, -10);
      expect(redemption.reason, '一本绘本');
      expect(redemption.createdAt, now);
      expect(redemption.balanceAfter, 13);
      await reloaded.selectChild(second);
      expect(reloaded.selectedChild!.balance, 7);
    },
  );

  test(
    'setting balance preserves history and records the exact adjustment',
    () async {
      await store.addChild(name: '朵朵', avatar: 1, balance: 10);
      final id = store.selectedChild!.id;
      await store.reward(childId: id, amount: 2, reason: '帮忙');
      await store.updateChild(id: id, name: '花花', avatar: 2, balance: 3);
      expect(store.selectedEntries, hasLength(3));
      expect(store.selectedEntries.first.amount, -9);
      expect(store.selectedEntries.first.kind, EntryKind.adjustment);
      expect(store.totalRewarded, 2);
      expect(store.totalExchanged, 0);
      expect(GardenData.decode(repository.raw!).children.first.balance, 3);
      await store.updateChild(id: id, name: '花花', avatar: 3, balance: 3);
      expect(store.selectedEntries, hasLength(3));
    },
  );

  test('insufficient balance cannot spend or append a record', () async {
    await store.addChild(name: '朵朵', avatar: 1, balance: 2);
    final before = repository.raw;
    await expectLater(
      store.exchange(childId: store.selectedChild!.id, amount: 3, reason: '绘本'),
      throwsA(isA<GardenException>()),
    );
    expect(store.selectedChild!.balance, 2);
    expect(repository.raw, before);
  });

  test('spending the entire balance results in zero and persists', () async {
    await store.addChild(name: '小宇', avatar: 0, balance: 5);
    await store.exchange(
      childId: store.selectedChild!.id,
      amount: 5,
      reason: '动画',
    );
    expect(store.selectedChild!.balance, 0);
    expect(GardenData.decode(repository.raw!).children.first.balance, 0);
  });

  test('invalid amounts and empty reasons cannot change a balance', () async {
    await store.addChild(name: '朵朵', avatar: 1, balance: 10);
    final id = store.selectedChild!.id;
    for (final amount in [-1, 0, 1000000]) {
      await expectLater(
        store.reward(childId: id, amount: amount, reason: '学习'),
        throwsA(isA<GardenException>()),
      );
      await expectLater(
        store.exchange(childId: id, amount: amount, reason: '绘本'),
        throwsA(isA<GardenException>()),
      );
    }
    await expectLater(
      store.exchange(childId: id, amount: 1, reason: '  '),
      throwsA(isA<GardenException>()),
    );
    expect(store.selectedChild!.balance, 10);
    expect(store.selectedEntries, hasLength(1));
  });

  test('upper bound rejects overflow but supports six-digit balance', () async {
    await store.addChild(name: '朵朵', avatar: 1, balance: 999999);
    await expectLater(
      store.reward(childId: store.selectedChild!.id, amount: 1, reason: '学习'),
      throwsA(isA<GardenException>()),
    );
    expect(store.selectedChild!.balance, 999999);
  });

  test(
    'a failed save leaves both the visible state and persisted data untouched',
    () async {
      await store.addChild(name: '朵朵', avatar: 1, balance: 10);
      final before = repository.raw;
      repository.failSave = true;
      await expectLater(
        store.reward(childId: store.selectedChild!.id, amount: 2, reason: '学习'),
        throwsA(isA<GardenException>()),
      );
      expect(store.selectedChild!.balance, 10);
      expect(repository.raw, before);
      expect(store.saving, isFalse);
    },
  );

  test(
    'concurrent submissions cannot duplicate or lose a transaction',
    () async {
      await store.addChild(name: '朵朵', avatar: 1, balance: 10);
      repository.pendingSave = Completer<void>();
      final pending = store.reward(
        childId: store.selectedChild!.id,
        amount: 2,
        reason: '学习',
      );
      expect(store.saving, isTrue);
      expect(store.selectedChild!.balance, 10);
      await expectLater(
        store.reward(childId: store.selectedChild!.id, amount: 2, reason: '学习'),
        throwsA(isA<GardenException>()),
      );
      repository.pendingSave!.complete();
      await pending;
      expect(store.selectedChild!.balance, 12);
      expect(store.selectedEntries, hasLength(2));
    },
  );

  test(
    'corrupt and mismatched ledgers are rejected without overwriting data',
    () async {
      await store.addChild(name: '朵朵', avatar: 1, balance: 10);
      final json = jsonDecode(repository.raw!) as Map<String, dynamic>;
      json['children'][0]['balance'] = 999;
      repository.raw = jsonEncode(json);
      final raw = repository.raw;
      await expectLater(store.load(), throwsA(isA<FormatException>()));
      expect(repository.raw, raw);
      expect(
        () => GardenData.decode('{invalid'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('zero initial balance still has an initialization record', () async {
    await store.addChild(name: '朵朵', avatar: 1, balance: 0);
    expect(store.selectedEntries.single.kind, EntryKind.initial);
    expect(store.selectedEntries.single.amount, 0);
    expect(GardenData.decode(repository.raw!).children.single.balance, 0);
  });

  test('unknown child and invalid profiles are rejected', () async {
    await expectLater(
      store.addChild(name: '  ', avatar: 0, balance: 0),
      throwsA(isA<GardenException>()),
    );
    await expectLater(
      store.addChild(name: '朵朵', avatar: 6, balance: 0),
      throwsA(isA<GardenException>()),
    );
    await expectLater(
      store.selectChild('missing'),
      throwsA(isA<GardenException>()),
    );
    await expectLater(
      store.exchange(childId: 'missing', amount: 1, reason: '绘本'),
      throwsA(isA<GardenException>()),
    );
    expect(repository.writes, 0);
  });
}
