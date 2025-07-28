import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_state.dart';
import 'screens/main_screen.dart';
import 'services/thumbnail_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Initialize services
  final prefs = await SharedPreferences.getInstance();
  final thumbnailService = ThumbnailService();
  await thumbnailService.init();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: prefs),
        Provider.value(value: thumbnailService),
        ChangeNotifierProvider(
          create: (context) =>
              AppState(prefs: prefs, thumbnailService: thumbnailService)
                ..loadInitialClips(), // Load initial data
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Clip Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
        dialogTheme: DialogThemeData(backgroundColor: Colors.white),
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
        dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF1e1e1e)),
      ),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

String formatDuration(Duration d) {
  final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
  return '${parts[0]}:${parts[1]}:${parts[2]}';
}
