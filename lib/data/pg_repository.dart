import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'garden.dart';
import 'garden_command.dart';
import 'garden_store.dart';
import 'pg_config.dart';
import 'pg_gateway.dart';
import 'pg_preset.dart';

abstract interface class PgSettingsStore {
  Future<PgConfig?> read();
  Future<void> write(PgConfig config);
}

class SecurePgSettingsStore implements PgSettingsStore {
  static const _key = 'red_flowers_pg_connection_v1';
  final _storage = const FlutterSecureStorage();
  @override
  Future<PgConfig?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : PgConfig.parse(raw);
  }

  @override
  Future<void> write(PgConfig config) =>
      _storage.write(key: _key, value: jsonEncode(config.toJson()));
}

class PgGardenRepository implements GardenRepository, CommandGardenRepository {
  PgGardenRepository({
    PgGateway? gateway,
    PgSettingsStore? settings,
    SharedPreferencesAsync? preferences,
    GardenRepository? legacy,
    PgConfig? Function()? presetConfigLoader,
  }) : gateway = gateway ?? NativePgGateway(),
       settings = settings ?? SecurePgSettingsStore(),
       preferences = preferences ?? SharedPreferencesAsync(),
       legacy = legacy ?? LocalGardenRepository(),
       _presetConfigLoader = presetConfigLoader ?? loadPresetPgConfig;

  final PgGateway gateway;
  final PgSettingsStore settings;
  final SharedPreferencesAsync preferences;
  final GardenRepository legacy;
  final PgConfig? Function() _presetConfigLoader;
  PgConfig? config;
  @override
  bool offline = false;
  @override
  bool hasPending = false;
  @override
  DateTime? lastSyncAt;
  @override
  String? notice;

  String get _cacheKey => 'red_flowers_pg_cache_v1_${config!.familyId}';
  String get _pendingKey => 'red_flowers_pg_pending_v1_${config!.familyId}';

  Future<PgConfig?> savedConfig() async =>
      config ??
      await gateway.developerConfig() ??
      await settings.read() ??
      _presetConfigLoader();

  @override
  Future<GardenData> load() async {
    config = await savedConfig();
    if (config == null) throw const PgConfigurationMissing();
    try {
      final result = await refresh();
      // Automatic one-time migration preserves the original local backup.
      final local = await legacy.load();
      if (local.children.isNotEmpty &&
          await preferences.getBool(
                'red_flowers_pg_imported_${config!.familyId}',
              ) !=
              true) {
        final imported = await apply(
          GardenCommand('import_local', {'garden': jsonDecode(local.encode())}),
        );
        await preferences.setBool(
          'red_flowers_pg_imported_${config!.familyId}',
          true,
        );
        return imported;
      }
      return result;
    } on PgFailure catch (error) {
      if (!error.transport || config!.familyId == null) rethrow;
      final cached = await preferences.getString(_cacheKey);
      if (cached == null) rethrow;
      offline = true;
      notice = '当前显示上次同步的数据，联网后点击同步';
      hasPending = await preferences.getString(_pendingKey) != null;
      return GardenData.decode(cached);
    }
  }

  Future<GardenData> configure(
    PgConfig candidate, {
    bool importLocal = true,
  }) async {
    candidate.validate();
    if (hasPending) {
      throw const GardenException('请先同步确认上一次保存，再修改连接设置');
    }
    final snapshot = await gateway.read(candidate);
    final verified = candidate.withFamily(snapshot['familyId'] as String);
    await settings.write(verified);
    config = verified;
    var data = await _remember(snapshot);
    if (importLocal) {
      final local = await legacy.load();
      if (local.children.isNotEmpty) {
        data = await apply(
          GardenCommand('import_local', {'garden': jsonDecode(local.encode())}),
        );
      }
    }
    // Remember an explicit decision to skip migration as well, so the next
    // launch does not import records the user chose to leave on this device.
    await preferences.setBool(
      'red_flowers_pg_imported_${config!.familyId}',
      true,
    );
    return data;
  }

  @override
  Future<GardenData> refresh() async {
    final active = config;
    if (active == null) throw const PgConfigurationMissing();
    notice = null;
    if (active.familyId != null) {
      final raw = await preferences.getString(_pendingKey);
      hasPending = raw != null;
      if (raw != null) {
        final pending = GardenCommand.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        try {
          final result = await gateway.apply(active, pending);
          final data = await _remember(result);
          await _clearPending();
          return data;
        } on PgFailure catch (error) {
          if (error.uncertain || error.transport) rethrow;
          await _clearPending();
          notice = '上次操作没有保存：${error.message}';
        }
      }
    }
    final snapshot = await gateway.read(active);
    if (active.familyId == null) {
      config = active.withFamily(snapshot['familyId'] as String);
    }
    return _remember(snapshot);
  }

  @override
  Future<GardenData> apply(GardenCommand command) async {
    final active = config;
    if (active?.familyId == null) throw const PgConfigurationMissing();
    final raw = await preferences.getString(_pendingKey);
    if (raw != null) {
      final previous = GardenCommand.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (!previous.sameIntent(command)) {
        hasPending = true;
        throw const GardenException('上一次保存结果待确认，请先点同步，再进行新的操作');
      }
      command = previous;
    } else {
      // Save the original operation ID before contacting PostgreSQL. Replays
      // after a lost response or an app restart cannot award/spend twice.
      await preferences.setString(_pendingKey, jsonEncode(command.toJson()));
    }
    hasPending = true;
    try {
      final snapshot = await gateway.apply(active!, command);
      notice = null;
      final data = await _remember(snapshot);
      await _clearPending();
      return data;
    } on PgFailure catch (error) {
      if (!error.uncertain) await _clearPending();
      if (error.transport) offline = true;
      throw GardenException(error.message);
    }
  }

  Future<void> _clearPending() async {
    try {
      await preferences.remove(_pendingKey);
      hasPending = false;
    } catch (_) {
      // Keep the idempotency marker if clearing storage failed.
      hasPending = true;
    }
  }

  Future<GardenData> _remember(Map<String, dynamic> snapshot) async {
    if (snapshot['familyId'] != config!.familyId) {
      throw const GardenException('家庭连接不一致，请检查同步设置');
    }
    final data = GardenData.decode(jsonEncode(snapshot['garden']));
    offline = false;
    lastSyncAt = DateTime.now();
    try {
      await preferences.setString(_cacheKey, data.encode());
    } catch (_) {
      notice = '云端已保存，本机缓存暂时无法更新';
    }
    return data;
  }

  @override
  Future<void> save(GardenData data) async =>
      throw const GardenException('云端保存必须通过记账操作完成');
}
