import 'dart:math';
import 'package:flutter/material.dart';

// 根据tag文本生成一致的颜色
Color generateTagColor(String tag) {
  // 使用tag的hashCode来生成一致的种子
  final random = Random(tag.hashCode);
  
  // 预定义一组鲜艳的颜色
  final colors = [
    Colors.red.shade400,
    Colors.pink.shade400,
    Colors.purple.shade400,
    Colors.deepPurple.shade400,
    Colors.indigo.shade400,
    Colors.blue.shade400,
    Colors.lightBlue.shade400,
    Colors.cyan.shade400,
    Colors.teal.shade400,
    Colors.green.shade400,
    Colors.lightGreen.shade400,
    Colors.lime.shade400,
    Colors.yellow.shade600,
    Colors.orange.shade400,
    Colors.deepOrange.shade400,
    Colors.brown.shade400,
    Colors.blueGrey.shade400,
  ];
  
  return colors[random.nextInt(colors.length)];
}

// 构建带颜色的tag chip (用于clips_tab列表模式)
Widget buildTagChip(String tag) {
  final color = generateTagColor(tag);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: color.withValues(alpha: 0.6),
        width: 1,
      ),
    ),
    child: Text(
      tag,
      style: TextStyle(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

// 构建带颜色的tag chip (用于clip_playback_screen)
Widget buildTagChipWithTap(String tag, VoidCallback onTap) {
  final color = generateTagColor(tag);
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

// 构建带颜色的tag文本 (用于过滤对话框等需要更大字体的地方)
Widget buildTagText(String tag) {
  final color = generateTagColor(tag);
  return Text(
    tag,
    style: TextStyle(
      fontSize: 14,
      color: color,
      fontWeight: FontWeight.w500,
    ),
  );
} 