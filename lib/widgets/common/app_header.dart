import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class AppHeader extends StatelessWidget {
  final String title;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final bool isSemanticSearching;
  final bool hasSemanticScores;
  final VoidCallback onTriggerSemanticSearch;
  final VoidCallback onRefreshThumbnails;
  final VoidCallback onImportMerge;
  final VoidCallback onSwitchDb;
  final VoidCallback onOpenAiSettings;
  final VoidCallback onOpenScraperSettings;
  final VoidCallback onOpenAbout;
  final VoidCallback? onOpenTheme;
  final String? searchStatus;
  final bool isNarrow;

  const AppHeader({
    super.key,
    required this.title,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.isSemanticSearching,
    required this.hasSemanticScores,
    required this.onTriggerSemanticSearch,
    required this.onRefreshThumbnails,
    required this.onImportMerge,
    required this.onSwitchDb,
    required this.onOpenAiSettings,
    required this.onOpenScraperSettings,
    required this.onOpenAbout,
    this.onOpenTheme,
    this.searchStatus,
    this.isNarrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      height: AppSpacing.topToolbarHeight,
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? AppSpacing.sm : AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // 页面主标题
          Text(
            title,
            style: AppTypography.sectionTitle.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: isNarrow ? 16 : 18,
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // 居中搜索栏（自适应展开）
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  onSubmitted: onSearchSubmitted,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: isNarrow
                        ? '搜索名称、标签或 AI 语义…'
                        : '搜索标题、笔记、标签，按回车启动 AI 跨模态语义检索…',
                    hintStyle: AppTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _buildSearchSuffix(context, colors),
                    filled: true,
                    fillColor: colors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: colors.borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: colors.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: colors.primary, width: 1.2),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // 搜索辅助状态提示（当存在时）
          if (searchStatus != null && !isNarrow) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 180),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                searchStatus!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.primaryHover,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],

          // 右侧操作工具栏
          _buildActionButtons(context, colors),
        ],
      ),
    );
  }

  Widget _buildSearchSuffix(BuildContext context, AppColorExtension colors) {
    final hasText = searchController.text.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isSemanticSearching)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (hasText)
          IconButton(
            icon: Icon(
              Icons.auto_awesome,
              size: 17,
              color: hasSemanticScores ? colors.warning : colors.primary,
            ),
            tooltip: '执行 AI 跨模态语义检索',
            onPressed: onTriggerSemanticSearch,
            visualDensity: VisualDensity.compact,
          ),
        if (hasText)
          IconButton(
            icon: const Icon(Icons.clear, size: 16),
            tooltip: '清空搜索',
            onPressed: onClearSearch,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, AppColorExtension colors) {
    // 窄屏模式下，部分次级按钮归入溢出菜单，避免任何 RenderFlex 溢出
    if (isNarrow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 19),
            tooltip: '重新生成全部缩略图',
            onPressed: onRefreshThumbnails,
            visualDensity: VisualDensity.compact,
          ),
          PopupMenuButton<int>(
            tooltip: '更多操作与设置',
            icon: const Icon(Icons.more_vert, size: 19),
            onSelected: (value) {
              switch (value) {
                case 0:
                  onImportMerge();
                  break;
                case 1:
                  onSwitchDb();
                  break;
                case 2:
                  onOpenAiSettings();
                  break;
                case 3:
                  onOpenScraperSettings();
                  break;
                case 4:
                  onOpenAbout();
                  break;
                case 5:
                  onOpenTheme?.call();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Icon(Icons.file_upload_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('导入并合并 JSON 库'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, size: 18),
                    SizedBox(width: 8),
                    Text('切换/新建数据库'),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18),
                    SizedBox(width: 8),
                    Text('AI 视觉与模型设置'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 3,
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 18),
                    SizedBox(width: 8),
                    Text('爬虫设置'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 4,
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18),
                    SizedBox(width: 8),
                    Text('关于软件'),
                  ],
                ),
              ),
              if (onOpenTheme != null)
                const PopupMenuItem(
                  value: 5,
                  child: Row(
                    children: [
                      Icon(Icons.palette_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('外观与配色'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    }

    // 宽屏模式：全功能独立按钮
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 19),
          tooltip: '重新生成全部缩略图',
          onPressed: onRefreshThumbnails,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: AppSpacing.xxs),
        PopupMenuButton<int>(
          tooltip: '数据库与数据管理',
          icon: const Icon(Icons.inventory_2_outlined, size: 19),
          onSelected: (item) {
            if (item == 0) onImportMerge();
            if (item == 1) onSwitchDb();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 0,
              child: Row(
                children: [
                  Icon(Icons.file_upload_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('导入并合并 JSON 库'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 1,
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, size: 18),
                  SizedBox(width: 8),
                  Text('切换/新建数据库'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.xxs),
        IconButton(
          icon: const Icon(Icons.auto_awesome, size: 19),
          tooltip: 'AI 视觉大模型与多模态设置',
          onPressed: onOpenAiSettings,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: AppSpacing.xxs),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 19),
          tooltip: '外部视频嗅探与抓取设置',
          onPressed: onOpenScraperSettings,
          visualDensity: VisualDensity.compact,
        ),
        if (onOpenTheme != null) ...[
          const SizedBox(width: AppSpacing.xxs),
          IconButton(
            icon: const Icon(Icons.palette_outlined, size: 19),
            tooltip: '外观与配色',
            onPressed: onOpenTheme,
            visualDensity: VisualDensity.compact,
          ),
        ],
        const SizedBox(width: AppSpacing.xxs),
        IconButton(
          icon: const Icon(Icons.info_outline, size: 19),
          tooltip: '关于 Video Clip Manager',
          onPressed: onOpenAbout,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
