import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_state.dart';
import 'screens/main_screen.dart';
import 'services/path_service.dart';
import 'services/thumbnail_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: Colors.grey[100],
          dialogTheme: const DialogThemeData(backgroundColor: Colors.white), // Fixed
        ),
        darkTheme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF121212),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1e1e1e)), // Fixed
        ),
        themeMode: ThemeMode.system,
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
