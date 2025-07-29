import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_clip_manager/utils/tag_utils.dart';

void main() {
  group('Tag Utils Tests', () {
    test('generateTagColor should return consistent colors for same tag', () {
      const tag1 = 'action';
      const tag2 = 'comedy';
      const tag3 = 'drama';
      
      // Generate colors multiple times for the same tags
      final color1a = generateTagColor(tag1);
      final color1b = generateTagColor(tag1);
      final color2a = generateTagColor(tag2);
      final color2b = generateTagColor(tag2);
      final color3a = generateTagColor(tag3);
      final color3b = generateTagColor(tag3);
      
      // Same tag should always generate the same color
      expect(color1a, equals(color1b));
      expect(color2a, equals(color2b));
      expect(color3a, equals(color3b));
      
      // Different tags should generate different colors (most of the time)
      expect(color1a, isNot(equals(color2a)));
      expect(color1a, isNot(equals(color3a)));
      expect(color2a, isNot(equals(color3a)));
    });
    
    test('generateTagColor should return valid colors', () {
      const tag = 'test';
      final color = generateTagColor(tag);
      
      // Color should not be null
      expect(color, isNotNull);
      
      // Color should be a valid Color object
      expect(color, isA<Color>());
      
      // Color should have valid RGB values
      expect(color.red, greaterThanOrEqualTo(0));
      expect(color.red, lessThanOrEqualTo(255));
      expect(color.green, greaterThanOrEqualTo(0));
      expect(color.green, lessThanOrEqualTo(255));
      expect(color.blue, greaterThanOrEqualTo(0));
      expect(color.blue, lessThanOrEqualTo(255));
    });
    
    test('buildTagChip should create a valid widget', () {
      const tag = 'test';
      final widget = buildTagChip(tag);
      
      // Should return a valid widget
      expect(widget, isNotNull);
      expect(widget, isA<Widget>());
    });
    
    test('buildTagChipWithTap should create a valid widget', () {
      const tag = 'test';
      bool tapped = false;
      final widget = buildTagChipWithTap(tag, () => tapped = true);
      
      // Should return a valid widget
      expect(widget, isNotNull);
      expect(widget, isA<Widget>());
    });
  });
} 