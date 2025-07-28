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

  // The thumbnail service now manages a global player
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
          )..loadInitialClips(),
        ),
      ],
      child: MyApp(thumbnailService: thumbnailService),
    ),
  );
}

class MyApp extends StatelessWidget {
  final ThumbnailService thumbnailService;
  const MyApp({super.key, required this.thumbnailService});

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
      home: Scaffold(
        body: Stack(
          children: [
            const MainScreen(),
            // This is the global, 1x1 pixel "drawing board" for screenshots
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: Video(
                controller: thumbnailService.videoController,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

String formatDuration(Duration d) {
  final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
  return '${parts[0]}:${parts[1]}:${parts[2]}';
}
