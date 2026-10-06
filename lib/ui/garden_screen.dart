import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/garden.dart';
import '../data/garden_store.dart';
import '../data/pg_repository.dart';
import 'dialogs.dart';
import 'illustrations.dart';
import 'pg_connection.dart';

class GardenScreen extends StatefulWidget {
  const GardenScreen({super.key, required this.store});
  final GardenStore store;
  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen>
    with WidgetsBindingObserver {
  int _page = 0;
  EntryKind? _filter;
  final _rewardAmount = TextEditingController(text: '1');
  final _rewardReason = TextEditingController();
  final _scroll = ScrollController();
  String? _rewardError;
  (String, int)? _celebration;
  GardenStore get store => widget.store;
  bool get _phone => MediaQuery.sizeOf(context).width < 600;
  Timer? _refreshTimer;
  bool _configuring = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (store.cloud) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_foreground) unawaited(_sync());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && store.cloud) unawaited(_sync());
  }

  Future<void> _sync({bool manual = false}) async {
    if (store.busy || _configuring) return;
    try {
      await store.refresh();
      if (manual) _message(store.syncMessage ?? '已同步最新的小花园');
    } catch (error) {
      if (manual) _message(error.toString());
    }
  }

  Future<void> _cloudSettings() async {
    if (store.busy || _configuring) return;
    final repository = store.repository;
    if (repository is! PgGardenRepository) return;
    _configuring = true;
    try {
      final initial = await repository.savedConfig();
      if (!mounted) return;
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PgConnectionForm(
                    repository: repository,
                    initial: initial,
                    onConnected: () => Navigator.pop(dialogContext, true),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('返回小花园'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (changed == true) await store.load();
    } catch (error) {
      _message(error.toString());
    } finally {
      _configuring = false;
    }
  }

  String get _storageLabel {
    if (!store.cloud) return '陪伴每一次成长  ·  数据保存在当前设备';
    if (store.syncing) return '正在同步家庭云端…';
    if (store.hasPending) return '保存结果待确认，请点击右上角同步';
    if (store.syncMessage != null) return store.syncMessage!;
    if (store.offline) return '当前显示上次同步的数据，联网后点击同步';
    final time = store.lastSyncAt;
    final label = time == null
        ? ''
        : ' · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return '陪伴每一次成长 · 已同步家庭云端$label';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _rewardAmount.dispose();
    _rewardReason.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _navigate(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _editChild([ChildProfile? child]) async {
    if (store.busy) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChildEditor(store: store, child: child),
    );
    if (saved == true) {
      _message(child == null ? '欢迎来到小花园，一起慢慢长大吧' : '小朋友的设置已保存');
    }
  }

  Future<void> _switchChild(String id) async {
    if (store.busy) return;
    try {
      await store.selectChild(id);
      if (mounted) setState(() => _rewardError = null);
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _editSuggestions({bool wishes = false}) async {
    if (store.busy) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SuggestionsEditor(store: store, wishes: wishes),
    );
    if (saved == true) {
      _message(wishes ? '心愿灵感已保存' : '努力候选项已保存');
    }
  }

  Future<void> _reward() async {
    if (store.busy || _celebration != null) return;
    final child = store.selectedChild;
    if (child == null) {
      await _editChild();
      return;
    }
    final error = validateAmount(_rewardAmount.text);
    if (error != null) {
      setState(() => _rewardError = error);
      return;
    }
    final amount = int.parse(_rewardAmount.text);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await store.reward(
        childId: child.id,
        amount: amount,
        reason: _rewardReason.text.trim().isEmpty
            ? '今天表现真棒'
            : _rewardReason.text,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _rewardError = null;
        _celebration = (child.name, amount);
      });
    } catch (error) {
      if (mounted) setState(() => _rewardError = error.toString());
    }
  }

  Future<void> _exchange({int amount = 5, String reason = ''}) async {
    if (store.busy) return;
    final child = store.selectedChild;
    if (child == null) {
      await _editChild();
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExchangeDialog(
        store: store,
        child: child,
        amount: amount,
        reason: reason,
      ),
    );
    if (saved == true) _message('兑换成功！把小红花变成小快乐吧');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return Scaffold(
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _page,
                  onDestinationSelected: _navigate,
                  backgroundColor: Colors.white,
                  indicatorColor: const Color(0xFFFBEAE6),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.local_florist_outlined),
                      label: '小花园',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.redeem_outlined),
                      label: '心愿兑换',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_rounded),
                      label: '成长记录',
                    ),
                  ],
                ),
          body: SafeArea(
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide) _sidebar(),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          wide
                              ? 40
                              : _phone
                              ? 14
                              : 22,
                          _phone ? 16 : 28,
                          wide
                              ? 40
                              : _phone
                              ? 14
                              : 22,
                          32,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1160),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _topBar(wide),
                                SizedBox(height: _phone ? 16 : 28),
                                _childSelector(),
                                SizedBox(height: _phone ? 18 : 26),
                                if (_page == 0)
                                  _gardenPage()
                                else if (_page == 1)
                                  _exchangePage()
                                else
                                  _historyPage(),
                                const SizedBox(height: 28),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.favorite_outline_rounded,
                                      size: 13,
                                      color: muted,
                                    ),
                                    const SizedBox(width: 7),
                                    Flexible(
                                      child: Text(
                                        _storageLabel,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: muted.withValues(alpha: .8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_celebration != null)
                  Positioned.fill(
                    child: Celebration(
                      name: _celebration!.$1,
                      amount: _celebration!.$2,
                      onDone: () {
                        if (mounted) setState(() => _celebration = null);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _sidebar() => Container(
    width: 220,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(22, 34, 22, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(left: 7), child: _Brand()),
        const SizedBox(height: 48),
        _navItem(0, Icons.local_florist_outlined, '我的小花园'),
        const SizedBox(height: 10),
        _navItem(1, Icons.redeem_outlined, '心愿兑换'),
        const SizedBox(height: 10),
        _navItem(2, Icons.history_rounded, '成长记录'),
        const Spacer(),
        if (MediaQuery.sizeOf(context).height >= 700)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4EB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowerMark(size: 40, color: Color(0xFFE4AD76), face: true),
                SizedBox(height: 16),
                Text(
                  '今天的努力，\n明天会开花。',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '慢慢来，每一步都算数',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: store.saving
              ? null
              : () => _editChild(store.selectedChild),
          icon: const Icon(Icons.tune_rounded, size: 18, color: muted),
          label: const Text(
            '小朋友设置',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    ),
  );

  Widget _navItem(int index, IconData icon, String label) => Material(
    color: _page == index ? const Color(0xFFFBECE8) : Colors.transparent,
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      key: Key('nav_$index'),
      onTap: () => _navigate(index),
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        child: Row(
          children: [
            Icon(icon, size: 21, color: _page == index ? flowerRed : muted),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: _page == index ? FontWeight.w600 : FontWeight.w400,
                color: _page == index ? flowerRed : ink,
              ),
            ),
            const Spacer(),
            if (_page == index)
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: flowerRed,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _topBar(bool wide) => Row(
    children: [
      Expanded(
        child: wide
            ? const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '每一份努力，都值得一朵小红花',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '把成长，种成花',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              )
            : const _Brand(compact: true),
      ),
      if (MediaQuery.sizeOf(context).width > 560)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                size: 17,
                color: Color(0xFFC6A568),
              ),
              const SizedBox(width: 8),
              Text(
                _todayLabel(),
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
      if (!wide && !_phone) ...[
        const SizedBox(width: 8),
        IconButton(
          tooltip: '小朋友设置',
          onPressed: store.saving
              ? null
              : () => _editChild(store.selectedChild),
          icon: const Icon(Icons.tune_rounded, color: muted, size: 21),
        ),
      ],
      if (store.cloud) ...[
        const SizedBox(width: 4),
        IconButton(
          key: const Key('cloud_sync'),
          tooltip: '同步家庭云端',
          onPressed: store.busy ? null : () => _sync(manual: true),
          icon: store.syncing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: flowerRed,
                  ),
                )
              : Icon(
                  store.offline || store.hasPending
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_done_outlined,
                  color: muted,
                  size: 21,
                ),
        ),
        IconButton(
          key: const Key('cloud_settings'),
          tooltip: '家庭云端设置',
          onPressed: store.busy ? null : _cloudSettings,
          icon: const Icon(Icons.settings_outlined, color: muted, size: 21),
        ),
      ],
    ],
  );

  Widget _childSelector() => SizedBox(
    height: 68,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: store.children.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        if (index == store.children.length) {
          return Center(
            child: OutlinedButton.icon(
              key: const Key('add_child'),
              onPressed: store.saving ? null : () => _editChild(),
              icon: const Icon(Icons.add_rounded, size: 19, color: muted),
              label: const Text(
                '添加小朋友',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          );
        }
        final child = store.children[index];
        final selected = child.id == store.selectedChild?.id;
        return Center(
          child: Semantics(
            selected: selected,
            child: Material(
              color: selected ? Colors.white : const Color(0xFFF0F0E9),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: Key('child_${child.id}'),
                onTap: store.saving ? null : () => _switchChild(child.id),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFE6A99C)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimalAvatar(index: child.avatar, size: 36),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _phone ? 160 : 240,
                        ),
                        child: Text(
                          child.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 14),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: flowerRed,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _gardenPage() {
    final child = store.selectedChild;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          child == null ? '小小努力，大大值得。' : '${child.name}，今天也很棒！',
          child == null ? '从第一朵小红花开始，记录每一个值得鼓励的瞬间。' : '一点点进步，一朵朵积攒，让每份努力都被看见。',
        ),
        SizedBox(height: _phone ? 16 : 24),
        _balanceCard(),
        SizedBox(height: _phone ? 16 : 24),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 11, child: _rewardCard()),
                  const SizedBox(width: 22),
                  Expanded(flex: 10, child: _recentCard()),
                ],
              );
            }
            return Column(
              children: [
                _rewardCard(),
                const SizedBox(height: 20),
                _recentCard(),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: _phone ? 22 : 26,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: muted, height: 1.7),
      ),
    ],
  );

  Widget _balanceCard() {
    final child = store.selectedChild;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1E5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E9D9)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final art = constraints.maxWidth >= 700;
          return Stack(
            children: [
              if (art)
                const Positioned(
                  right: 16,
                  top: 12,
                  bottom: 10,
                  width: 330,
                  child: GardenIllustration(),
                ),
              Padding(
                padding: EdgeInsets.all(_phone ? 18 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FlowerMark(size: 18, color: Color(0xFF9AAE80)),
                        const SizedBox(width: 8),
                        Text(
                          child == null ? '等待第一朵花开' : '我的小红花',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF758365),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: _phone ? 8 : 14),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 450),
                            child: Text(
                              '${child?.balance ?? 0}',
                              key: ValueKey(
                                'balance_${child?.id}_${child?.balance}',
                              ),
                              style: TextStyle(
                                fontSize: art
                                    ? 68
                                    : _phone
                                    ? 48
                                    : 60,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF475B41),
                                height: 1.2,
                                letterSpacing: -2,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 10, bottom: 10),
                            child: Text(
                              '朵',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF758365),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: _phone ? 8 : 17),
                    if (child == null)
                      FilledButton.icon(
                        key: const Key('start_garden'),
                        onPressed: () => _editChild(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加第一位小朋友'),
                      )
                    else
                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .65),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              '今天收获 +${store.todayRewarded} 朵',
                              style: const TextStyle(
                                fontSize: 11,
                                color: leafGreen,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const Key('edit_child'),
                            onPressed: store.saving
                                ? null
                                : () => _editChild(child),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF758365),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 40),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('设置花数', style: TextStyle(fontSize: 11)),
                                SizedBox(width: 5),
                                Icon(Icons.edit_outlined, size: 13),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rewardCard() => _PaperCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardHeading(
          icon: Icons.auto_awesome_outlined,
          title: '送一朵小红花',
          subtitle: '让今天的好表现，被好好看见',
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in [1, 3, 5])
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: store.saving
                          ? null
                          : () => setState(() => _rewardAmount.text = '$value'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        side: BorderSide(
                          color: _rewardAmount.text == '$value'
                              ? const Color(0xFFEAC1B7)
                              : line,
                        ),
                        backgroundColor: _rewardAmount.text == '$value'
                            ? const Color(0xFFFFF3EE)
                            : Colors.white,
                      ),
                      child: Text(
                        '+$value',
                        style: const TextStyle(fontSize: 12, color: flowerRed),
                      ),
                    ),
                  ),
              ],
            );
            const label = Text(
              '奖励数量',
              style: TextStyle(fontSize: 12, color: muted),
            );
            return constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(12) > 16
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [label, const SizedBox(height: 8), buttons],
                  )
                : Row(children: [label, const Spacer(), buttons]);
          },
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: cream,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              IconButton(
                key: const Key('reward_minus'),
                tooltip: '减少一朵',
                onPressed: store.saving
                    ? null
                    : () {
                        setState(
                          () => _rewardAmount.text =
                              '${math.max(1, (int.tryParse(_rewardAmount.text) ?? 1) - 1)}',
                        );
                      },
                icon: const Icon(Icons.remove_rounded, size: 20, color: muted),
              ),
              Expanded(
                child: TextField(
                  key: const Key('reward_amount'),
                  controller: _rewardAmount,
                  enabled: !store.saving,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: _phone ? 22 : 26,
                    fontWeight: FontWeight.w700,
                    color: flowerRed,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    semanticCounterText: '奖励小红花数量',
                  ),
                ),
              ),
              IconButton(
                key: const Key('reward_plus'),
                tooltip: '增加一朵',
                onPressed: store.saving
                    ? null
                    : () {
                        setState(
                          () => _rewardAmount.text =
                              '${math.min(999999, (int.tryParse(_rewardAmount.text) ?? 0) + 1)}',
                        );
                      },
                icon: const Icon(Icons.add_rounded, size: 20, color: flowerRed),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                '这朵花，送给哪一份努力？',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
            TextButton(
              key: const Key('edit_reward_reasons'),
              onPressed: store.busy ? null : () => _editSuggestions(),
              child: const Text('设置', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: store.rewardReasons
              .map(
                (reason) => _ReasonChip(
                  label: reason,
                  selected: _rewardReason.text == reason,
                  onTap: store.saving
                      ? null
                      : () => setState(() => _rewardReason.text = reason),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('reward_reason'),
          controller: _rewardReason,
          enabled: !store.saving,
          maxLength: 80,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '也可以写下今天的小进步…',
            counterText: '',
          ),
          style: const TextStyle(fontSize: 13),
        ),
        if (_rewardError != null) ErrorNote(_rewardError!),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('give_reward'),
            onPressed: store.saving || _celebration != null ? null : _reward,
            icon: const Icon(Icons.local_florist_outlined, size: 19),
            label: Text(store.saving ? '正在保存…' : '奖励小红花'),
          ),
        ),
      ],
    ),
  );

  Widget _recentCard() {
    final entries = store.selectedEntries.take(3).toList();
    return _PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _CardHeading(
                  icon: Icons.eco_outlined,
                  title: '成长的足迹',
                  subtitle: '每一个小瞬间，都有被记住',
                ),
              ),
              TextButton(
                onPressed: () => _navigate(2),
                child: const Text(
                  '查看全部',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: '累计获得',
                  value: store.totalRewarded,
                  color: flowerRed,
                ),
              ),
              Container(width: 1, height: 36, color: line),
              Expanded(
                child: _Stat(
                  label: '已兑换快乐',
                  value: store.totalExchanged,
                  color: leafGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 25),
              child: _EmptyNote(
                title: '第一份小美好，等你记录',
                subtitle: '奖励和兑换的故事，都会出现在这里。',
              ),
            )
          else
            ...entries.map((entry) => _EntryRow(entry: entry, compact: true)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.redeem_outlined,
                  color: Color(0xFFB79866),
                  size: 23,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '小红花也能变成小快乐',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '一起挑选一份心愿吧',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '去心愿兑换',
                  onPressed: () => _navigate(1),
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: muted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _exchangePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader('把努力，换成小快乐。', '和小朋友一起约定，让每一份期待都有意义。'),
      const SizedBox(height: 24),
      _PaperCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 430;
            final summary = Row(
              children: [
                const FlowerMark(size: 38, face: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.selectedChild == null
                            ? '先开启一个小花园吧'
                            : '${store.selectedChild!.name} 可以兑换的小红花',
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${store.selectedChild?.balance ?? 0} 朵',
                        style: const TextStyle(
                          fontSize: 28,
                          color: flowerRed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final button = FilledButton.icon(
              key: const Key('custom_exchange'),
              onPressed: store.saving ? null : () => _exchange(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('自定义兑换'),
            );
            return narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 18), button],
                  )
                : Row(
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: 16),
                      button,
                    ],
                  );
          },
        ),
      ),
      const SizedBox(height: 28),
      Row(
        children: [
          const Expanded(
            child: Text(
              '心愿灵感',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            key: const Key('edit_wish_suggestions'),
            onPressed: store.busy ? null : () => _editSuggestions(wishes: true),
            child: const Text('设置', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        '在设置里添加喜欢的心愿和花数，兑换时也可以修改。',
        style: TextStyle(fontSize: 12, color: muted),
      ),
      const SizedBox(height: 20),
      if (store.wishSuggestions.isEmpty)
        const Text(
          '还没有心愿灵感，可以在设置中添加。',
          style: TextStyle(fontSize: 13, color: muted),
        ),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 780
              ? 3
              : constraints.maxWidth >= 480
              ? 2
              : 1;
          final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
          return Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final wish in store.wishSuggestions)
                SizedBox(width: width, child: _wishCard(wish)),
            ],
          );
        },
      ),
      const SizedBox(height: 28),
      _PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardHeading(
              icon: Icons.receipt_long_outlined,
              title: '最近的兑换',
              subtitle: '努力变成快乐的那些时刻',
            ),
            const SizedBox(height: 16),
            if (store.selectedEntries
                .where((e) => e.kind == EntryKind.exchange)
                .isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: _EmptyNote(
                  title: '期待第一份心愿成真',
                  subtitle: '完成兑换后，数量、事由和时间都会保存在这里。',
                ),
              )
            else
              ...store.selectedEntries
                  .where((e) => e.kind == EntryKind.exchange)
                  .take(4)
                  .map((e) => _EntryRow(entry: e)),
          ],
        ),
      ),
    ],
  );
  Widget _wishCard(WishSuggestion wish) {
    return _PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF6EAE4),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.redeem_outlined,
              color: Color(0xFFD09A81),
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            wish.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          const Text(
            '和小朋友一起约定的小快乐',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 25),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FlowerMark(size: 18),
                  const SizedBox(width: 7),
                  Text(
                    '${wish.amount} 朵',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: flowerRed,
                    ),
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: store.saving
                    ? null
                    : () => _exchange(amount: wish.amount, reason: wish.title),
                child: const Text('去兑换', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyStats() {
    final balance = _PaperCard(
      child: _Stat(
        label: '当前小红花',
        value: store.selectedChild?.balance ?? 0,
        color: leafGreen,
      ),
    );
    final reward = _PaperCard(
      child: _Stat(label: '累计奖励', value: store.totalRewarded, color: flowerRed),
    );
    final exchange = _PaperCard(
      child: _Stat(
        label: '累计兑换',
        value: store.totalExchanged,
        color: const Color(0xFFB49761),
      ),
    );
    return _phone
        ? Column(
            children: [
              balance,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: reward),
                  const SizedBox(width: 12),
                  Expanded(child: exchange),
                ],
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: balance),
              const SizedBox(width: 12),
              Expanded(child: reward),
              const SizedBox(width: 12),
              Expanded(child: exchange),
            ],
          );
  }

  Widget _historyPage() {
    final entries = store.selectedEntries
        .where(
          (e) =>
              _filter == null ||
              e.kind == _filter ||
              (_filter == EntryKind.adjustment && e.kind == EntryKind.initial),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('每一步成长，都有迹可循。', '奖励、兑换和花数调整，都是这座小花园的故事。'),
        const SizedBox(height: 24),
        _historyStats(),
        const SizedBox(height: 24),
        _PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ReasonChip(
                    label: '全部记录',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  _ReasonChip(
                    label: '奖励',
                    selected: _filter == EntryKind.reward,
                    onTap: () => setState(() => _filter = EntryKind.reward),
                  ),
                  _ReasonChip(
                    label: '兑换',
                    selected: _filter == EntryKind.exchange,
                    onTap: () => setState(() => _filter = EntryKind.exchange),
                  ),
                  _ReasonChip(
                    label: '花数设置',
                    selected: _filter == EntryKind.adjustment,
                    onTap: () => setState(() => _filter = EntryKind.adjustment),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Divider(height: 1),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 42),
                  child: _EmptyNote(
                    title: '这一页，等待一个美好瞬间',
                    subtitle: '给小朋友的第一份鼓励，从一朵小红花开始。',
                  ),
                )
              else
                ...entries.map((e) => _EntryRow(entry: e)),
            ],
          ),
        ),
      ],
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month} 月 ${now.day} 日  ·  星期${weekdays[now.weekday - 1]}';
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlowerMark(size: compact ? 36 : 41, face: true),
        const SizedBox(width: 11),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '小花园',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'LITTLE BLOOMS',
              style: TextStyle(fontSize: 8, color: muted, letterSpacing: 1.9),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 18 : 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, color: flowerRed, size: 21),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      const SizedBox(height: 9),
      Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FittedBox(
        child: Text(
          '$value',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: muted),
      ),
    ],
  );
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFFBECE8) : cream,
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected ? flowerRed : muted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      children: [
        const FlowerMark(size: 35, color: Color(0xFFE5C7B5), face: true),
        const SizedBox(height: 15),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: muted, height: 1.8),
        ),
      ],
    ),
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, this.compact = false});
  final FlowerEntry entry;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final reward = entry.kind == EntryKind.reward;
    final exchange = entry.kind == EntryKind.exchange;
    final color = reward
        ? flowerRed
        : exchange
        ? leafGreen
        : const Color(0xFFB39B72);
    final title = reward
        ? '奖励'
        : exchange
        ? '兑换'
        : entry.kind == EntryKind.initial
        ? '初始'
        : '调整';
    final icon = Container(
      width: 37,
      height: 37,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: reward
          ? const Padding(
              padding: EdgeInsets.all(9),
              child: FlowerMark(size: 19),
            )
          : Icon(
              exchange ? Icons.redeem_outlined : Icons.tune_rounded,
              size: 19,
              color: color,
            ),
    );
    final amount = Text(
      '${entry.amount > 0 ? '+' : ''}${entry.amount}',
      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color),
    );
    final balance = Text(
      '剩余 ${entry.balanceAfter} 朵',
      style: const TextStyle(fontSize: 9, color: muted),
    );
    final date = Text(
      '$title  ·  ${_date(entry.createdAt)}',
      style: const TextStyle(fontSize: 10, color: muted),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 400;
        final reason = Text(
          entry.reason,
          maxLines: compact ? (narrow ? 2 : 1) : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.7,
          ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    reason,
                    const SizedBox(height: 6),
                    if (narrow)
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [amount, balance, date],
                      )
                    else
                      date,
                  ],
                ),
              ),
              if (!narrow) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [amount, const SizedBox(height: 4), balance],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _date(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final date = today
        ? '今天'
        : '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    return '$date ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
