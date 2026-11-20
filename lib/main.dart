import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/database.dart';
import 'services/settings.dart';
import 'screens/bookshelf_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化数据库和设置
  await DatabaseService.instance.init();
  await SettingsService.instance.load();

  // 隐藏安卓底部导航栏，沉浸阅读
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const MoyueApp());
}

class MoyueApp extends StatelessWidget {
  const MoyueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: SettingsService.instance,
      child: Consumer<SettingsService>(
        builder: (context, settingsService, _) {
          final isDark = settingsService.settings.isDarkMode ||
              settingsService.settings.theme.index >= 5;

          return MaterialApp(
            title: '墨阅',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF5B7A6B),
                brightness: isDark ? Brightness.dark : Brightness.light,
              ),
              scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
              appBarTheme: AppBarTheme(
                centerTitle: true,
                backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                foregroundColor: isDark ? Colors.white70 : Colors.black87,
                elevation: 0,
              ),
              cardTheme: CardThemeData(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            home: const BookshelfScreen(),
          );
        },
      ),
    );
  }
}
