import 'dart:convert';

enum EntryKind { initial, reward, exchange, adjustment }

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.balance,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int avatar;
  final int balance;
  final DateTime createdAt;

  ChildProfile copyWith({String? name, int? avatar, int? balance}) =>
      ChildProfile(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        balance: balance ?? this.balance,
        createdAt: createdAt,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'balance': balance,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory ChildProfile.fromJson(Map<String, dynamic> json) => ChildProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    avatar: json['avatar'] as int,
    balance: json['balance'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
  );
}

class FlowerEntry {
  const FlowerEntry({
    required this.id,
    required this.childId,
    required this.kind,
    required this.amount,
    required this.reason,
    required this.balanceAfter,
    required this.createdAt,
  });

  final String id;
  final String childId;
  final EntryKind kind;
  final int amount;
  final String reason;
  final int balanceAfter;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'id': id,
    'childId': childId,
    'kind': kind.name,
    'amount': amount,
    'reason': reason,
    'balanceAfter': balanceAfter,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory FlowerEntry.fromJson(Map<String, dynamic> json) => FlowerEntry(
    id: json['id'] as String,
    childId: json['childId'] as String,
    kind: EntryKind.values.byName(json['kind'] as String),
    amount: json['amount'] as int,
    reason: json['reason'] as String,
    balanceAfter: json['balanceAfter'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
  );
}

class WishSuggestion {
  const WishSuggestion({required this.title, required this.amount});

  final String title;
  final int amount;

  Map<String, Object> toJson() => {'title': title, 'amount': amount};

  factory WishSuggestion.fromJson(Map<String, dynamic> json) => WishSuggestion(
    title: json['title'] as String,
    amount: json['amount'] as int,
  );
}

const defaultRewardReasons = ['英语打卡', '单词打卡', '体育打卡', '早睡早起'];
const defaultWishSuggestions = [WishSuggestion(title: '看10分钟喜欢的动画', amount: 5)];
const maxGardenSuggestions = 20;

void validateRewardReasons(List<String> reasons) {
  if (reasons.length > maxGardenSuggestions ||
      reasons.any(
        (reason) => reason.trim().isEmpty || reason.trim().runes.length > 80,
      ) ||
      reasons.map((reason) => reason.trim()).toSet().length != reasons.length) {
    throw const FormatException('努力候选项最多 20 个，每项填写 1～80 个字，且不能重复');
  }
}

void validateWishSuggestions(List<WishSuggestion> wishes) {
  if (wishes.length > maxGardenSuggestions ||
      wishes.any(
        (wish) =>
            wish.title.trim().isEmpty ||
            wish.title.trim().runes.length > 80 ||
            wish.amount < 1 ||
            wish.amount > 999999,
      ) ||
      wishes.map((wish) => wish.title.trim()).toSet().length != wishes.length) {
    throw const FormatException('心愿灵感最多 20 个，名称填写 1～80 个字且不能重复，花数为 1～999999');
  }
}

class GardenData {
  GardenData({
    List<ChildProfile> children = const [],
    List<FlowerEntry> entries = const [],
    this.selectedChildId,
    List<String> rewardReasons = defaultRewardReasons,
    List<WishSuggestion> wishSuggestions = defaultWishSuggestions,
  }) : children = List.unmodifiable(children),
       entries = List.unmodifiable(entries),
       rewardReasons = List.unmodifiable(rewardReasons),
       wishSuggestions = List.unmodifiable(wishSuggestions);

  final List<ChildProfile> children;
  final List<FlowerEntry> entries;
  final String? selectedChildId;
  final List<String> rewardReasons;
  final List<WishSuggestion> wishSuggestions;

  GardenData copyWith({
    List<ChildProfile>? children,
    List<FlowerEntry>? entries,
    String? selectedChildId,
    List<String>? rewardReasons,
    List<WishSuggestion>? wishSuggestions,
  }) => GardenData(
    children: children ?? this.children,
    entries: entries ?? this.entries,
    selectedChildId: selectedChildId ?? this.selectedChildId,
    rewardReasons: rewardReasons ?? this.rewardReasons,
    wishSuggestions: wishSuggestions ?? this.wishSuggestions,
  );

  String encode() => jsonEncode({
    'version': 1,
    'children': children.map((child) => child.toJson()).toList(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'selectedChildId': selectedChildId,
    'rewardReasons': rewardReasons,
    'wishSuggestions': wishSuggestions.map((wish) => wish.toJson()).toList(),
  });

  factory GardenData.decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1) throw const FormatException('不支持的数据版本');
      final data = GardenData(
        children: (json['children'] as List)
            .map((e) => ChildProfile.fromJson(e as Map<String, dynamic>))
            .toList(),
        entries: (json['entries'] as List)
            .map((e) => FlowerEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        selectedChildId: json['selectedChildId'] as String?,
        rewardReasons: json.containsKey('rewardReasons')
            ? List<String>.from(json['rewardReasons'] as List)
            : defaultRewardReasons,
        wishSuggestions: json.containsKey('wishSuggestions')
            ? (json['wishSuggestions'] as List)
                  .map(
                    (e) => WishSuggestion.fromJson(e as Map<String, dynamic>),
                  )
                  .toList()
            : defaultWishSuggestions,
      );
      data._validate();
      return data;
    } catch (error) {
      throw const FormatException('本地数据无法读取，请保留数据并重试。');
    }
  }

  void _validate() {
    validateRewardReasons(rewardReasons);
    validateWishSuggestions(wishSuggestions);
    final ids = children.map((child) => child.id).toSet();
    if (ids.length != children.length ||
        (children.isNotEmpty && !ids.contains(selectedChildId)) ||
        (children.isEmpty && selectedChildId != null)) {
      throw const FormatException('小朋友数据不完整');
    }
    final balances = {for (final id in ids) id: 0};
    final entryIds = <String>{};
    for (final child in children) {
      if (child.id.isEmpty ||
          child.name.trim().isEmpty ||
          child.name.runes.length > 12 ||
          child.avatar < 0 ||
          child.avatar > 5 ||
          child.balance < 0 ||
          child.balance > 999999) {
        throw const FormatException('小朋友数据不正确');
      }
    }
    for (final entry in entries) {
      if (!ids.contains(entry.childId) ||
          !entryIds.add(entry.id) ||
          entry.id.isEmpty ||
          entry.reason.trim().isEmpty ||
          entry.reason.runes.length > 80 ||
          (entry.kind == EntryKind.reward && entry.amount <= 0) ||
          (entry.kind == EntryKind.exchange && entry.amount >= 0) ||
          (entry.kind == EntryKind.initial && entry.amount < 0)) {
        throw const FormatException('记录数据不正确');
      }
      final balance = balances[entry.childId]! + entry.amount;
      if (balance < 0 || balance > 999999 || balance != entry.balanceAfter) {
        throw const FormatException('小红花余额不一致');
      }
      balances[entry.childId] = balance;
    }
    for (final child in children) {
      if (balances[child.id] != child.balance) {
        throw const FormatException('小红花余额不一致');
      }
    }
  }
}
