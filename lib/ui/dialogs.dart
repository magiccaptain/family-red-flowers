import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/garden.dart';
import '../data/garden_store.dart';
import 'illustrations.dart';

String? validateAmount(String? text, {bool allowZero = false}) {
  final value = int.tryParse(text?.trim() ?? '');
  if (value == null || value < (allowZero ? 0 : 1) || value > 999999) {
    return allowZero ? '请输入 0～999999 之间的整数' : '请输入 1～999999 之间的整数';
  }
  return null;
}

class ChildEditor extends StatefulWidget {
  const ChildEditor({super.key, required this.store, this.child});
  final GardenStore store;
  final ChildProfile? child;
  @override
  State<ChildEditor> createState() => _ChildEditorState();
}

class _ChildEditorState extends State<ChildEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.child?.name ?? '');
  late final _balance = TextEditingController(
    text: '${widget.child?.balance ?? 0}',
  );
  late int _avatar = widget.child?.avatar ?? 0;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final child = widget.child;
      if (child == null) {
        await widget.store.addChild(
          name: _name.text,
          avatar: _avatar,
          balance: int.parse(_balance.text),
        );
      } else {
        await widget.store.updateChild(
          id: child.id,
          name: _name.text,
          avatar: _avatar,
          balance: int.parse(_balance.text),
          previousBalance: child.balance,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: DialogShell(
      title: widget.child == null ? '认识一位新朋友' : '管理小朋友',
      subtitle: widget.child == null ? '从今天起，一起收集成长的小美好。' : '给小朋友的花园做一点小调整。',
      busy: _busy,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FieldLabel('小朋友的昵称'),
            TextFormField(
              key: const Key('child_name'),
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              maxLength: 12,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: '例如：朵朵、小宇'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写小朋友的昵称' : null,
            ),
            const SizedBox(height: 16),
            const FieldLabel('选一个喜欢的头像'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(
                6,
                (index) => Semantics(
                  label: avatarNames[index],
                  selected: _avatar == index,
                  child: InkWell(
                    key: Key('avatar_$index'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: _busy ? null : () => setState(() => _avatar = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _avatar == index
                              ? flowerRed
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: AnimalAvatar(index: index, size: 46),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FieldLabel(widget.child == null ? '初始小红花数量' : '当前小红花数量'),
            TextFormField(
              key: const Key('child_balance'),
              controller: _balance,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                suffixText: '朵',
                counterText: '',
              ),
              validator: (value) => validateAmount(value, allowZero: true),
            ),
            const SizedBox(height: 10),
            Text(
              widget.child == null
                  ? '已经积攒的小红花，也可以带进新花园。'
                  : '调整数量会保存一条记录，已有奖励和兑换记录会保留。',
              style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
            ),
            if (_error != null) ErrorNote(_error!),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('save_child'),
                onPressed: _busy ? null : _save,
                child: Text(
                  _busy
                      ? '正在保存…'
                      : widget.child == null
                      ? '开启小花园'
                      : '保存设置',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ExchangeDialog extends StatefulWidget {
  const ExchangeDialog({
    super.key,
    required this.store,
    required this.child,
    this.amount = 5,
    this.reason = '',
  });
  final GardenStore store;
  final ChildProfile child;
  final int amount;
  final String reason;
  @override
  State<ExchangeDialog> createState() => _ExchangeDialogState();
}

class _ExchangeDialogState extends State<ExchangeDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: '${widget.amount}');
  late final _reason = TextEditingController(text: widget.reason);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.exchange(
        childId: widget.child.id,
        amount: int.parse(_amount.text),
        reason: _reason.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(_amount.text) ?? 0;
    final remaining = widget.child.balance - amount;
    return PopScope(
      canPop: !_busy,
      child: DialogShell(
        title: '兑换一份小快乐',
        subtitle: '${widget.child.name} 的努力，值得一个期待已久的奖励。',
        busy: _busy,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cream,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final name = Row(
                      children: [
                        AnimalAvatar(index: widget.child.avatar),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.child.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 360) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name,
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const FlowerMark(size: 20),
                              Text(
                                '${widget.child.balance} 朵',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        AnimalAvatar(index: widget.child.avatar),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.child.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const FlowerMark(size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.child.balance} 朵',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              const FieldLabel('这次需要多少朵？'),
              TextFormField(
                key: const Key('exchange_amount'),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _amount,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  suffixText: '朵小红花',
                  counterText: '',
                ),
                validator: (value) {
                  final error = validateAmount(value);
                  if (error != null) return error;
                  return int.parse(value!) > widget.child.balance
                      ? '小红花不够啦，目前有 ${widget.child.balance} 朵'
                      : null;
                },
              ),
              const SizedBox(height: 20),
              const FieldLabel('想兑换什么？'),
              TextFormField(
                key: const Key('exchange_reason'),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _reason,
                enabled: !_busy,
                minLines: 2,
                maxLines: 3,
                maxLength: 80,
                decoration: const InputDecoration(hintText: '例如：周末去公园野餐'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请记录这次兑换的事由' : null,
              ),
              const SizedBox(height: 8),
              Text(
                remaining >= 0
                    ? '兑换后还剩 $remaining 朵小红花'
                    : '还差 ${-remaining} 朵，继续加油吧',
                style: TextStyle(
                  fontSize: 13,
                  color: remaining >= 0 ? leafGreen : flowerRed,
                ),
              ),
              if (_error != null) ErrorNote(_error!),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('confirm_exchange'),
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.redeem_outlined, size: 20),
                  label: Text(_busy ? '正在保存…' : '确认兑换'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SuggestionsEditor extends StatefulWidget {
  const SuggestionsEditor({
    super.key,
    required this.store,
    this.wishes = false,
  });

  final GardenStore store;
  final bool wishes;

  @override
  State<SuggestionsEditor> createState() => _SuggestionsEditorState();
}

class _SuggestionDraft {
  _SuggestionDraft(this.id, String title, int amount)
    : title = TextEditingController(text: title),
      amount = TextEditingController(text: '$amount');

  final int id;
  final TextEditingController title;
  final TextEditingController amount;

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}

class _SuggestionsEditorState extends State<SuggestionsEditor> {
  final _form = GlobalKey<FormState>();
  final _drafts = <_SuggestionDraft>[];
  final _allDrafts = <_SuggestionDraft>[];
  late final _previousReasons = widget.store.rewardReasons;
  late final _previousWishes = widget.store.wishSuggestions;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.wishes) {
      for (final wish in _previousWishes) {
        _addDraft(wish.title, wish.amount);
      }
    } else {
      for (final reason in _previousReasons) {
        _addDraft(reason, 5);
      }
    }
  }

  void _addDraft(String title, int amount) {
    final draft = _SuggestionDraft(_allDrafts.length, title, amount);
    _allDrafts.add(draft);
    _drafts.add(draft);
  }

  @override
  void dispose() {
    for (final draft in _allDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.wishes) {
        await widget.store.updateWishSuggestions(
          _drafts
              .map(
                (draft) => WishSuggestion(
                  title: draft.title.text,
                  amount: int.parse(draft.amount.text),
                ),
              )
              .toList(),
          previousWishes: _previousWishes,
        );
      } else {
        await widget.store.updateRewardReasons(
          _drafts.map((draft) => draft.title.text).toList(),
          previousReasons: _previousReasons,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: DialogShell(
      title: widget.wishes ? '心愿灵感设置' : '努力候选项设置',
      subtitle: widget.store.cloud
          ? '按家庭的约定新增、修改或删除，保存后其他设备也能同步使用。'
          : '按家庭的约定新增、修改或删除，设置会保存在当前设备。',
      busy: _busy,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_drafts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  '还没有候选项，点击下方按钮添加。',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ),
            for (var i = 0; i < _drafts.length; i++)
              _draftEditor(_drafts[i], i),
            OutlinedButton.icon(
              key: const Key('add_suggestion'),
              onPressed: _busy || _drafts.length >= maxGardenSuggestions
                  ? null
                  : () => setState(() => _addDraft('', 5)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(widget.wishes ? '添加心愿灵感' : '添加努力候选项'),
            ),
            if (_error != null) ErrorNote(_error!),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('save_suggestions'),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '正在保存…' : '保存设置'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _draftEditor(_SuggestionDraft draft, int index) => Container(
    key: ValueKey(draft.id),
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
    decoration: BoxDecoration(
      color: cream,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.wishes ? '心愿 ${index + 1}' : '努力 ${index + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: Key('remove_suggestion_${draft.id}'),
              tooltip: '删除这一项',
              onPressed: _busy
                  ? null
                  : () => setState(() => _drafts.remove(draft)),
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: muted,
              ),
            ),
          ],
        ),
        TextFormField(
          key: Key('suggestion_title_${draft.id}'),
          controller: draft.title,
          enabled: !_busy,
          maxLength: 80,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: widget.wishes ? '心愿名称' : '努力名称',
            hintText: widget.wishes ? '例如：看10分钟喜欢的动画' : '例如：英语打卡',
            counterText: '',
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '请填写名称，或删除这一项' : null,
        ),
        if (widget.wishes) ...[
          const SizedBox(height: 12),
          TextFormField(
            key: Key('suggestion_amount_${draft.id}'),
            controller: draft.amount,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: '兑换花数',
              suffixText: '朵',
              counterText: '',
            ),
            validator: validateAmount,
          ),
        ],
      ],
    ),
  );
}

class DialogShell extends StatelessWidget {
  const DialogShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.busy = false,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final bool busy;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
      vertical: 16,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 20 : 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: muted, size: 21),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: muted, height: 1.7),
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    ),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(text, style: const TextStyle(color: flowerRed, fontSize: 13)),
  );
}
