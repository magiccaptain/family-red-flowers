import 'dart:convert';

class PgConfig {
  const PgConfig({
    required this.host,
    this.port = 5432,
    required this.database,
    required this.username,
    required this.password,
    this.sslMode = 'verifyFull',
    this.familyId,
  });

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final String sslMode;
  final String? familyId;

  PgConfig withFamily(String id) => PgConfig(
    host: host,
    port: port,
    database: database,
    username: username,
    password: password,
    sslMode: sslMode,
    familyId: id,
  );

  void validate() {
    if (host.trim().isEmpty ||
        host.contains(RegExp(r'[\s/]')) ||
        port < 1 ||
        port > 65535 ||
        database.trim().isEmpty ||
        username.trim().isEmpty ||
        password.isEmpty ||
        !['disable', 'require', 'verifyFull'].contains(sslMode)) {
      throw const FormatException('请检查连接地址、端口和家庭账号');
    }
  }

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'password': password,
    'sslMode': sslMode,
    'familyId': familyId,
  };

  factory PgConfig.fromJson(Map<String, dynamic> json) {
    final config = PgConfig(
      host: json['host'] as String,
      port: (json['port'] as int?) ?? 5432,
      database: json['database'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      sslMode: (json['sslMode'] as String?) ?? 'verifyFull',
      familyId: json['familyId'] as String?,
    );
    config.validate();
    return config;
  }

  static PgConfig parse(String input) {
    try {
      return PgConfig.fromJson(
        jsonDecode(input.trim()) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const FormatException('连接配置格式不正确，请复制完整的连接配置文件内容');
    }
  }

  // Never include a password in logs, errors, or debugging descriptions.
  @override
  String toString() => 'PgConfig(<private connection>)';
}

class PgFailure implements Exception {
  const PgFailure(
    this.message, {
    this.uncertain = false,
    this.transport = false,
  });
  final String message;
  final bool uncertain;
  final bool transport;
  @override
  String toString() => message;
}

class PgConfigurationMissing implements Exception {
  const PgConfigurationMissing();
}
