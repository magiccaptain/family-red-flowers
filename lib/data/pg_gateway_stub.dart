import 'garden_command.dart';
import 'pg_config.dart';
import 'pg_gateway_contract.dart';

class NativePgGateway implements PgGateway {
  @override
  Future<Map<String, dynamic>> read(PgConfig config) async =>
      throw const PgFailure('请使用 Android 平板或 Linux 桌面版连接家庭云端');
  @override
  Future<Map<String, dynamic>> apply(PgConfig config, GardenCommand command) =>
      read(config);
  @override
  Future<PgConfig?> developerConfig() async => null;
}
