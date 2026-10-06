import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'garden.dart';
import 'garden_command.dart';

abstract interface class GardenRepository {
  Future<GardenData> load();
  Future<void> save(GardenData data);
}

class LocalGardenRepository implements GardenRepository {
  LocalGardenRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const storageKey = 'red_flowers_garden_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<GardenData> load() async {
    final raw = await _preferences.getString(storageKey);
    return raw == null ? GardenData() : GardenData.decode(raw);
  }

  @override
  Future<void> save(GardenData data) =>
      _preferences.setString(storageKey, data.encode());
}

class GardenException implements Exception {
  const GardenException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GardenStore extends ChangeNotifier {
  GardenStore(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final GardenRepository repository;
  final DateTime Function() _now;
  GardenData _data = GardenData();
  bool _saving = false;
  bool _syncing = false;
  String? _syncError;

  List<ChildProfile> get children => _data.children;
  List<String> get rewardReasons => _data.rewardReasons;
  List<WishSuggestion> get wishSuggestions => _data.wishSuggestions;
  bool get saving => _saving;
  bool get syncing => _syncing;
  bool get busy => _saving || _syncing;
  bool get cloud => repository is CommandGardenRepository;
  CommandGardenRepository? get _remote =>
      cloud ? repository as CommandGardenRepository : null;
  bool get offline => _remote?.offline ?? false;
  bool get hasPending => _remote?.hasPending ?? false;
  DateTime? get lastSyncAt => _remote?.lastSyncAt;
  String? get syncMessage => _syncError ?? _remote?.notice;
  ChildProfile? get selectedChild => children.isEmpty
      ? null
      : children.firstWhere((child) => child.id == _data.selectedChildId);

  List<FlowerEntry> entriesFor(String childId) => _data.entries
      .where((entry) => entry.childId == childId)
      .toList()
      .reversed
      .toList();

  List<FlowerEntry> get selectedEntries =>
      selectedChild == null ? [] : entriesFor(selectedChild!.id);

  int get totalRewarded => selectedEntries
      .where((e) => e.kind == EntryKind.reward)
      .fold(0, (sum, e) => sum + e.amount);
  int get totalExchanged => selectedEntries
      .where((e) => e.kind == EntryKind.exchange)
      .fold(0, (sum, e) => sum - e.amount);
  int get todayRewarded {
    final today = _now();
    return selectedEntries
        .where(
          (e) =>
              e.kind == EntryKind.reward &&
              e.createdAt.year == today.year &&
              e.createdAt.month == today.month &&
              e.createdAt.day == today.day,
        )
        .fold(0, (sum, e) => sum + e.amount);
  }

  Future<void> load() async {
    if (busy) throw const GardenException('正在保存或同步，请稍后再试');
    _syncing = true;
    _syncError = null;
    notifyListeners();
    try {
      _data = await repository.load();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (busy || _remote == null) return;
    _syncing = true;
    _syncError = null;
    notifyListeners();
    try {
      _data = await _remote!.refresh();
    } catch (error) {
      _syncError = error.toString();
      rethrow;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  String _id() => const Uuid().v4();

  void _validateProfile(String name, int avatar, int balance) {
    if (name.trim().isEmpty || name.trim().runes.length > 12) {
      throw const GardenException('请填写 1～12 个字的昵称');
    }
    if (avatar < 0 || avatar > 5) throw const GardenException('请选择一个头像');
    if (balance < 0 || balance > 999999) {
      throw const GardenException('小红花数量应在 0～999999 之间');
    }
  }

  Future<void> _commit(GardenData data, GardenCommand command) async {
    if (busy) throw const GardenException('正在保存，请稍后再试');
    _saving = true;
    notifyListeners();
    try {
      if (_remote != null) {
        _data = await _remote!.apply(command);
        _syncError = null;
      } else {
        await repository.save(data);
        _data = data;
      }
    } on GardenException {
      rethrow;
    } catch (error) {
      throw const GardenException('保存失败，请重试。此次操作尚未生效。');
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> addChild({
    required String name,
    required int avatar,
    required int balance,
  }) async {
    _validateProfile(name, avatar, balance);
    final child = ChildProfile(
      id: _id(),
      name: name.trim(),
      avatar: avatar,
      balance: balance,
      createdAt: _now(),
    );
    final entry = FlowerEntry(
      id: _id(),
      childId: child.id,
      kind: EntryKind.initial,
      amount: balance,
      reason: '开启小花园 · 初始小红花',
      balanceAfter: balance,
      createdAt: _now(),
    );
    await _commit(
      _data.copyWith(
        children: [...children, child],
        entries: [..._data.entries, entry],
        selectedChildId: child.id,
      ),
      GardenCommand('add_child', {
        'childId': child.id,
        'name': child.name,
        'avatar': avatar,
        'balance': balance,
      }),
    );
  }

  Future<void> selectChild(String id) async {
    if (!children.any((child) => child.id == id)) {
      throw const GardenException('没有找到这位小朋友');
    }
    if (id == _data.selectedChildId) return;
    await _commit(
      _data.copyWith(
        children: children,
        entries: _data.entries,
        selectedChildId: id,
      ),
      GardenCommand('select_child', {'childId': id}),
    );
  }

  Future<void> updateChild({
    required String id,
    required String name,
    required int avatar,
    required int balance,
    int? previousBalance,
  }) async {
    _validateProfile(name, avatar, balance);
    final index = children.indexWhere((child) => child.id == id);
    if (index == -1) throw const GardenException('没有找到这位小朋友');
    final old = children[index];
    final effectiveBalance =
        previousBalance != null && balance == previousBalance
        ? old.balance
        : balance;
    final updated = [...children];
    updated[index] = old.copyWith(
      name: name.trim(),
      avatar: avatar,
      balance: effectiveBalance,
    );
    final entries = [..._data.entries];
    if (old.balance != effectiveBalance) {
      entries.add(
        FlowerEntry(
          id: _id(),
          childId: id,
          kind: EntryKind.adjustment,
          amount: effectiveBalance - old.balance,
          reason: '家长设置花数：${old.balance} → $effectiveBalance',
          balanceAfter: effectiveBalance,
          createdAt: _now(),
        ),
      );
    }
    await _commit(
      _data.copyWith(
        children: updated,
        entries: entries,
        selectedChildId: _data.selectedChildId,
      ),
      GardenCommand('update_child', {
        'childId': id,
        'name': name.trim(),
        'avatar': avatar,
        'balance': previousBalance != null
            ? (balance == previousBalance ? null : balance)
            : (balance == old.balance ? null : balance),
        'expectedBalance': previousBalance ?? old.balance,
      }),
    );
  }

  Future<void> reward({
    required String childId,
    required int amount,
    required String reason,
  }) => _transact(childId, amount, reason, EntryKind.reward);

  Future<void> updateRewardReasons(
    List<String> reasons, {
    required List<String> previousReasons,
  }) async {
    final normalized = reasons.map((reason) => reason.trim()).toList();
    try {
      validateRewardReasons(normalized);
    } on FormatException catch (error) {
      throw GardenException(error.message);
    }
    if (!listEquals(rewardReasons, previousReasons)) {
      throw const GardenException('努力候选项已更新，请关闭设置后重新打开');
    }
    await _commit(
      _data.copyWith(rewardReasons: normalized),
      GardenCommand('set_reward_reasons', {
        'rewardReasons': normalized,
        'expectedRewardReasons': previousReasons,
      }),
    );
  }

  Future<void> updateWishSuggestions(
    List<WishSuggestion> wishes, {
    required List<WishSuggestion> previousWishes,
  }) async {
    final normalized = wishes
        .map(
          (wish) =>
              WishSuggestion(title: wish.title.trim(), amount: wish.amount),
        )
        .toList();
    try {
      validateWishSuggestions(normalized);
    } on FormatException catch (error) {
      throw GardenException(error.message);
    }
    if (wishSuggestions.length != previousWishes.length ||
        !Iterable<int>.generate(wishSuggestions.length).every(
          (i) =>
              wishSuggestions[i].title == previousWishes[i].title &&
              wishSuggestions[i].amount == previousWishes[i].amount,
        )) {
      throw const GardenException('心愿灵感已更新，请关闭设置后重新打开');
    }
    await _commit(
      _data.copyWith(wishSuggestions: normalized),
      GardenCommand('set_wish_suggestions', {
        'wishSuggestions': normalized.map((wish) => wish.toJson()).toList(),
        'expectedWishSuggestions': previousWishes
            .map((wish) => wish.toJson())
            .toList(),
      }),
    );
  }

  Future<void> exchange({
    required String childId,
    required int amount,
    required String reason,
  }) => _transact(childId, amount, reason, EntryKind.exchange);

  Future<void> _transact(
    String childId,
    int amount,
    String reason,
    EntryKind kind,
  ) async {
    if (amount < 1 || amount > 999999) {
      throw const GardenException('请填写 1～999999 之间的整数');
    }
    if (reason.trim().isEmpty || reason.trim().runes.length > 80) {
      throw const GardenException('请填写 1～80 个字的事由');
    }
    final index = children.indexWhere((child) => child.id == childId);
    if (index == -1) throw const GardenException('请先添加一位小朋友');
    final child = children[index];
    if (kind == EntryKind.exchange && amount > child.balance) {
      throw const GardenException('小红花不够啦，再积攒一些吧');
    }
    final delta = kind == EntryKind.exchange ? -amount : amount;
    final balance = child.balance + delta;
    if (balance > 999999) throw const GardenException('小红花数量不能超过 999999');
    final updated = [...children];
    updated[index] = child.copyWith(balance: balance);
    final entry = FlowerEntry(
      id: _id(),
      childId: child.id,
      kind: kind,
      amount: delta,
      reason: reason.trim(),
      balanceAfter: balance,
      createdAt: _now(),
    );
    await _commit(
      _data.copyWith(
        children: updated,
        entries: [..._data.entries, entry],
        selectedChildId: _data.selectedChildId,
      ),
      GardenCommand(kind.name, {
        'childId': childId,
        'amount': amount,
        'reason': reason.trim(),
      }),
    );
  }
}
