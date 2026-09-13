import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_state.dart';
import 'screens/main_screen.dart';
import 'services/path_service.dart';
import 'services/thumbnail_service.dart';

Future<void> _initializeMediaKitSafely() async {
  try {
    MediaKit.ensureInitialized();
  } catch (error, stackTrace) {
    debugPrint('MediaKit initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  await _initializeMediaKitSafely();

  try {
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
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
          ),
          darkTheme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1e1e1e)),
          ),
          themeMode: ThemeMode.system,
          home: const MainScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('App bootstrap failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    // If the app fails very early, let Flutter continue with a minimal shell instead of crashing.
    runApp(
      MaterialApp(
        home: const Scaffold(
          body: Center(
            child: Text('Application failed to initialize. Please restart the app.'),
          ),
        ),
      ),
    );
  }
}
