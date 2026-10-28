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
      expect(
        await File(cliPath!).exists(),
        isTrue,
        reason: 'local-media-ai binary should exist at $cliPath',
      );
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
      expect(caption.keyActions, contains('surfer'));
      expect(caption.keyActions, contains('paddling'));
      expect(
        caption.summary,
        equals('A surfer rides an ocean wave skillfully.'),
      );
      expect(caption.searchDocument, contains('Scene: ocean beach'));
      expect(caption.searchDocument, contains('Subject: surfer'));
    });

    test(
      'sanitizeTags strips punctuation, splits clauses and extracts atomic keywords',
      () {
        final tags = AiService.sanitizeTags(
          ['行走，手持木棍'],
          scene: '一个女人在雪山上行走，手持一根木棍，背景是雪山和雾气。',
          mainSubject: '女人',
        );

        // 绝不能包含逗号或整句短语
        for (final t in tags) {
          expect(t.contains(','), isFalse);
          expect(t.contains('，'), isFalse);
          expect(t.length, lessThanOrEqualTo(8));
          expect(t.length, greaterThanOrEqualTo(2));
        }

        // 应提炼出原子名词/动名词
        expect(tags, contains('行走'));
        expect(tags, contains('木棍'));
        expect(tags, contains('女人'));
        expect(tags, contains('雪山'));
        expect(tags, contains('雾气'));
      },
    );
  });
}
