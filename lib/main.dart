import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/garden_store.dart';
import 'data/pg_config.dart';
import 'data/pg_repository.dart';
import 'ui/garden_screen.dart';
import 'ui/illustrations.dart';
import 'ui/pg_connection.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlowerGardenApp());
}

class FlowerGardenApp extends StatefulWidget {
  const FlowerGardenApp({super.key, this.store});
  final GardenStore? store;
  @override
  State<FlowerGardenApp> createState() => _FlowerGardenAppState();
}

class _FlowerGardenAppState extends State<FlowerGardenApp> {
  late final _store = widget.store ?? GardenStore(PgGardenRepository());
  late Future<void> _loading = _store.load();

  void _reload() {
    if (_store.busy) return;
    final loading = _store.load();
    setState(() {
      _loading = loading;
    });
  }

  @override
  void dispose() {
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '小花园 · 小红花成长记录',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansSC',
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: flowerRed,
        primary: flowerRed,
        surface: Colors.white,
        onSurface: ink,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'NotoSansSC',
        bodyColor: ink,
        displayColor: ink,
      ),
      splashFactory: InkSparkle.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: flowerRed,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: 'NotoSansSC',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cream,
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: flowerRed, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerColor: line,
    ),
    home: kIsWeb && widget.store == null
        ? const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '家庭云端版本请使用 Android 平板或 Linux 桌面版。\n'
                  '本机调试请运行 scripts/run-linux.sh。',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 2),
                ),
              ),
            ),
          )
        : FutureBuilder<void>(
            future: _loading,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: flowerRed),
                  ),
                );
              }
              if (snapshot.hasError) {
                final repository = _store.repository;
                if (repository is PgGardenRepository) {
                  final connectionForm = PgConnectionForm(
                    repository: repository,
                    initial: repository.config,
                    onConnected: _reload,
                  );
                  return Scaffold(
                    body: SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: repository.config == null
                                ? connectionForm
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const FlowerMark(size: 72),
                                      const SizedBox(height: 24),
                                      const Text(
                                        '小花园暂时没有打开',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        snapshot.error is PgFailure
                                            ? (snapshot.error as PgFailure)
                                                  .message
                                            : snapshot.error is GardenException
                                            ? (snapshot.error
                                                      as GardenException)
                                                  .message
                                            : '连接暂未完成，原有记录已保留，请重试',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: muted,
                                          height: 1.8,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      FilledButton.icon(
                                        key: const Key('retry_pg'),
                                        onPressed: _reload,
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('重试连接'),
                                      ),
                                      const SizedBox(height: 16),
                                      ExpansionTile(
                                        title: const Text('连接设置'),
                                        children: [connectionForm],
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FlowerMark(size: 72),
                          const SizedBox(height: 24),
                          const Text(
                            '小花园暂时没有打开',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '本地数据读取失败，请重试。\n已有数据会保留。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted, height: 1.8),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _reload,
                            child: const Text('重新打开'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return GardenScreen(store: _store);
            },
          ),
  );
}
