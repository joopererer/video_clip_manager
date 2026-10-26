import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_state.dart';
import 'screens/main_screen.dart';
import 'services/path_service.dart';
import 'services/thumbnail_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 添加错误处理来避免 media_kit 初始化失败
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    print('MediaKit initialization failed: $e');
    // 继续运行，即使 media_kit 初始化失败
  }

  final pathService = PathService();
  await pathService.init();

  final prefs = await SharedPreferences.getInstance();

  final thumbnailService = ThumbnailService(pathService: pathService);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: pathService),
        Provider.value(value: thumbnailService),
        ChangeNotifierProvider(
          create: (context) => AppState(
            prefs: prefs,
            pathService: pathService,
            thumbnailService: thumbnailService,
          )..loadInitialData(),
        ),
      ],
      child: MaterialApp(
        title: 'Video Clip Manager',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
