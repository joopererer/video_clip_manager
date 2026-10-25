import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiService Tests', () {
    final ai = AiService();

    test('resolveCliPath finds compiled local-media-ai executable', () async {
      final cliPath = await ai.resolveCliPath();
      expect(cliPath, isNotNull);
      expect(await File(cliPath!).exists(), isTrue,
          reason: 'local-media-ai binary should exist at $cliPath');
    });

    test('checkDoctor reports FFmpeg and CLI presence', () async {
      final doctor = await ai.checkDoctor();
      expect(doctor.cliFound, isTrue);
      expect(doctor.ffmpegFound, isTrue);
      expect(doctor.isReady, isTrue);
    });

    test('generateCaption parses structured output correctly', () async {
      const mockVlmOutput = '''
```json
{
  "scene": "ocean beach",
  "main_subject": "surfer",
  "key_actions": ["paddling", "riding wave"],
  "summary": "A surfer rides an ocean wave skillfully."
}
```
''';
      final caption = await ai.generateCaption(
        framePaths: ['test_frame_1.png', 'test_frame_2.png'],
        mockResponse: mockVlmOutput,
      );

      expect(caption.scene, equals('ocean beach'));
      expect(caption.mainSubject, equals('surfer'));
      expect(caption.keyActions, equals(['paddling', 'riding wave']));
      expect(caption.summary, equals('A surfer rides an ocean wave skillfully.'));
      expect(caption.searchDocument, contains('Scene: ocean beach'));
      expect(caption.searchDocument, contains('Subject: surfer'));
    });
  });
}
