import 'garden_command.dart';
import 'pg_config.dart';

abstract interface class PgGateway {
  Future<Map<String, dynamic>> read(PgConfig config);
  Future<Map<String, dynamic>> apply(PgConfig config, GardenCommand command);
  Future<PgConfig?> developerConfig();
}
