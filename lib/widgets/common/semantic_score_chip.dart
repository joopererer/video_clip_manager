import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../utils/search_mode.dart';

/// Similarity badge for semantic search results.
///
/// The number is the cosine similarity of the best matching frame as returned by
/// the retrieval pipeline. It is never relabelled as accuracy or confidence, and
/// it is only rendered when a real semantic score exists.
class SemanticScoreChip extends StatelessWidget {
  final double score;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const SemanticScoreChip({
    super.key,
    required this.score,
    this.fontSize = 10.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Tooltip(
      message: '语义相似度（余弦相似度），不是准确率或可信概率',
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.55),
            width: 0.6,
          ),
        ),
        child: Text(
          formatSemanticScore(score),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: colors.primaryHover,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
