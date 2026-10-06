import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

import 'garden_command.dart';
import 'pg_config.dart';
import 'pg_gateway_contract.dart';

class NativePgGateway implements PgGateway {
  @override
  Future<Map<String, dynamic>> read(PgConfig config) => _execute(config, null);
  @override
  Future<Map<String, dynamic>> apply(PgConfig config, GardenCommand command) =>
      _execute(config, command);

  Future<Map<String, dynamic>> _execute(
    PgConfig config,
    GardenCommand? command,
  ) async {
    config.validate();
    Connection connection;
    try {
      connection = await Connection.open(
        Endpoint(
          host: config.host,
          port: config.port,
          database: config.database,
          username: config.username,
          password: config.password,
        ),
        settings: ConnectionSettings(
          applicationName: 'red-flowers-app',
          timeZone: 'UTC',
          connectTimeout: const Duration(seconds: 8),
          queryTimeout: const Duration(seconds: 12),
          sslMode: switch (config.sslMode) {
            'disable' => SslMode.disable,
            'require' => SslMode.require,
            _ => SslMode.verifyFull,
          },
        ),
      );
    } on ServerException catch (error) {
      if (error.code == '28P01' || error.code == '28000') {
        throw const PgFailure('家庭账号或密码不正确，请检查同步设置');
      }
      throw const PgFailure('暂时无法连接家庭云端，请检查网络和连接设置', transport: true);
    } catch (_) {
      throw const PgFailure('暂时无法连接家庭云端，请检查网络和连接设置', transport: true);
    }
    try {
      final result = command == null
          ? await connection.execute('SELECT red_flowers.get_garden()')
          : await connection.execute(
              Sql.named('SELECT red_flowers.apply_command(@command::jsonb)'),
              parameters: {
                'command': TypedValue(Type.text, jsonEncode(command.toJson())),
              },
            );
      final value = result.single.single;
      return Map<String, dynamic>.from(value as Map);
    } on ServerException catch (error) {
      final message = error.message;
      if (message.startsWith('RF:')) {
        throw PgFailure(message.substring(3));
      }
      if (error.code == '42501' || error.code == '42883') {
        throw const PgFailure('家庭云端尚未准备好，请检查账号权限和数据库初始化');
      }
      if (error.code?.startsWith('23') == true ||
          error.code?.startsWith('22') == true) {
        throw const PgFailure('保存的数据不正确，此次操作没有生效');
      }
      if (error.code == '55P03' || error.code == '57014') {
        throw const PgFailure('云端正在处理其他操作，请稍后重试');
      }
      throw PgFailure(
        command == null ? '云端暂时无法读取，请稍后同步' : '保存结果暂未确认，请点击同步确认，避免重复记账',
        uncertain: command != null,
        transport: true,
      );
    } catch (_) {
      throw PgFailure(
        command == null ? '云端暂时无法读取，请检查网络' : '保存结果暂未确认，请点击同步确认，避免重复记账',
        uncertain: command != null,
        transport: true,
      );
    } finally {
      try {
        await connection.close().timeout(const Duration(seconds: 2));
      } catch (_) {
        // A confirmed database response is authoritative even if closing fails.
      }
    }
  }

  @override
  Future<PgConfig?> developerConfig() async {
    final path = Platform.environment['RF_PG_CONFIG_FILE'];
    if (path == null || path.isEmpty) return null;
    try {
      return PgConfig.parse(await File(path).readAsString());
    } catch (_) {
      throw const PgFailure('本机连接配置无法读取，请重新初始化数据库配置');
    }
  }
}
