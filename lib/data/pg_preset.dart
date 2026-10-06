import 'pg_config.dart';

// Supplied by the private family APK build, never by a committed source file.
const _familyPreset = String.fromEnvironment('RF_PG_PRESET');

PgConfig? loadPresetPgConfig() =>
    _familyPreset.isEmpty ? null : PgConfig.parse(_familyPreset);
