import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/pg_config.dart';
import '../data/pg_repository.dart';
import 'illustrations.dart';

class PgConnectionForm extends StatefulWidget {
  const PgConnectionForm({
    super.key,
    required this.repository,
    required this.onConnected,
    this.initial,
  });
  final PgGardenRepository repository;
  final PgConfig? initial;
  final VoidCallback onConnected;
  @override
  State<PgConnectionForm> createState() => _PgConnectionFormState();
}

class _PgConnectionFormState extends State<PgConnectionForm> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '5432');
  final _database = TextEditingController(text: 'postgres');
  final _username = TextEditingController(text: 'red_flowers_app');
  final _password = TextEditingController();
  String _sslMode = 'verifyFull';
  bool _importLocal = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) _fill(initial);
  }

  void _fill(PgConfig config) {
    _host.text = config.host;
    _port.text = '${config.port}';
    _database.text = config.database;
    _username.text = config.username;
    _password.text = config.password;
    _sslMode = config.sslMode;
  }

  @override
  void dispose() {
    for (final controller in [_host, _port, _database, _username, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final config = PgConfig.parse(clip?.text ?? '');
      if (mounted) {
        setState(() {
          _fill(config);
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '请先复制完整的家庭连接配置');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final config = PgConfig(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        database: _database.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        sslMode: _sslMode,
      );
      await widget.repository.configure(config, importLocal: _importLocal);
      if (mounted) widget.onConnected();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : error is PgFailure
              ? error.message
              : '连接或迁移暂未完成，原有记录已保留，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    bool password = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: Key(key),
      controller: controller,
      enabled: !_saving,
      obscureText: password,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const FlowerMark(size: 56),
      const SizedBox(height: 18),
      const Text(
        '连接家里的小花园',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      const Text(
        '小朋友、花数和成长记录会同步到家里的其他设备。',
        style: TextStyle(color: muted, height: 1.7),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        key: const Key('paste_pg_config'),
        onPressed: _saving ? null : _paste,
        icon: const Icon(Icons.content_paste_rounded, size: 18),
        label: const Text('粘贴家庭连接配置'),
      ),
      const SizedBox(height: 20),
      _field('pg_host', '连接地址', _host),
      Row(
        children: [
          Expanded(
            child: _field(
              'pg_port',
              '端口',
              _port,
              keyboard: TextInputType.number,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: _field('pg_database', '数据库', _database)),
        ],
      ),
      _field('pg_username', '家庭账号', _username),
      _field('pg_password', '连接密码', _password, password: true),
      DropdownButtonFormField<String>(
        key: const Key('pg_ssl_mode'),
        initialValue: _sslMode,
        isExpanded: true,
        decoration: const InputDecoration(labelText: '连接加密'),
        items: const [
          DropdownMenuItem(value: 'verifyFull', child: Text('TLS，验证证书')),
          DropdownMenuItem(value: 'require', child: Text('TLS，暂不验证证书')),
          DropdownMenuItem(value: 'disable', child: Text('服务器尚未启用 TLS')),
        ],
        onChanged: _saving
            ? null
            : (value) => setState(() => _sslMode = value!),
      ),
      if (_sslMode == 'disable') ...[
        const SizedBox(height: 8),
        const Text(
          '当前连接未加密。服务器开启 TLS 后，请在这里切换。',
          style: TextStyle(fontSize: 11, color: muted, height: 1.6),
        ),
      ],
      const SizedBox(height: 8),
      CheckboxListTile(
        value: _importLocal,
        onChanged: _saving
            ? null
            : (value) => setState(() => _importLocal = value!),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('同步此设备原有记录', style: TextStyle(fontSize: 13)),
        subtitle: const Text(
          '原有本地数据会保留',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ),
      if (_error != null) ...[
        Text(
          _error!,
          key: const Key('pg_connection_error'),
          style: const TextStyle(color: flowerRed, height: 1.6),
        ),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        key: const Key('connect_pg'),
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.cloud_done_outlined, size: 20),
        label: Text(_saving ? '正在连接并同步…' : '连接并打开小花园'),
      ),
      if (widget.initial != null) ...[
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _saving
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(text: jsonEncode(widget.initial!.toJson())),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('连接配置已复制，可粘贴到另一台设备')),
                    );
                  }
                },
          icon: const Icon(Icons.copy_rounded, size: 17),
          label: const Text('复制配置到另一台设备'),
        ),
      ],
    ],
  );
}
