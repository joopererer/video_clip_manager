import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class AppSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback onOpenAiSettings;
  final VoidCallback onOpenScraperSettings;
  final VoidCallback onOpenAbout;
  final VoidCallback? onOpenTheme;
  final VoidCallback onSwitchDb;
  final String currentDbName;

  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.onOpenAiSettings,
    required this.onOpenScraperSettings,
    required this.onOpenAbout,
    this.onOpenTheme,
    required this.onSwitchDb,
    required this.currentDbName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final width = isCollapsed
        ? AppSpacing.sidebarCollapsedWidth
        : AppSpacing.sidebarExpandedWidth;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(
          right: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部应用标识区
          _buildBrandHeader(context, colors),

          const SizedBox(height: AppSpacing.xs),

          // 主导航选项
          _buildNavItem(
            context,
            index: 0,
            icon: Icons.cut_outlined,
            activeIcon: Icons.cut,
            label: '片段库',
          ),
          _buildNavItem(
            context,
            index: 1,
            icon: Icons.movie_outlined,
            activeIcon: Icons.movie,
            label: '原始视频',
          ),
          _buildNavItem(
            context,
            index: 2,
            icon: Icons.playlist_play_outlined,
            activeIcon: Icons.playlist_play_rounded,
            label: '播放列表',
          ),

          const Spacer(),

          // 数据库简要状态
          _buildDatabaseIndicator(context, colors),

          Divider(color: colors.borderSubtle, height: 1.0),

          // 底部工具与设置区
          _buildActionItem(
            context,
            icon: Icons.auto_awesome_outlined,
            label: 'AI 设置',
            tooltip: 'AI 视觉与跨模态语义设置',
            onTap: onOpenAiSettings,
          ),
          _buildActionItem(
            context,
            icon: Icons.tune_outlined,
            label: '爬虫设置',
            tooltip: '外部视频嗅探与抓取配置',
            onTap: onOpenScraperSettings,
          ),
          if (onOpenTheme != null)
            _buildActionItem(
              context,
              icon: Icons.palette_outlined,
              label: '外观配色',
              tooltip: '选择预设配色或自定义强调色',
              onTap: onOpenTheme!,
            ),
          _buildActionItem(
            context,
            icon: Icons.info_outline,
            label: '关于软件',
            tooltip: '关于 Video Clip Manager',
            onTap: onOpenAbout,
          ),

          // 折叠/展开控制按钮
          _buildCollapseToggle(context, colors),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildBrandHeader(BuildContext context, AppColorExtension colors) {
    return Container(
      height: AppSpacing.topToolbarHeight,
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? AppSpacing.sm : AppSpacing.md,
      ),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: isCollapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.movie_filter_outlined,
              color: colors.primary,
              size: 20,
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'VIDEO CLIPS',
                overflow: TextOverflow.ellipsis,
                style: AppTypography.subtitle.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final colors = context.appColors;
    final isActive = currentIndex == index;

    final content = InkWell(
      onTap: () => onIndexChanged(index),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      hoverColor: colors.surfaceElevated.withValues(alpha: 0.5),
      child: Container(
        height: 42,
        padding: EdgeInsets.symmetric(
          horizontal: isCollapsed ? 0 : AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? colors.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: isActive
              ? Border.all(
                  color: colors.primary.withValues(alpha: 0.35),
                  width: 1.0,
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: isCollapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 20,
              color: isActive ? colors.primaryHover : colors.textSecondary,
            ),
            if (!isCollapsed) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2.0,
      ),
      child: isCollapsed
          ? Tooltip(
              message: label,
              waitDuration: const Duration(milliseconds: 300),
              child: content,
            )
          : content,
    );
  }

  Widget _buildDatabaseIndicator(
    BuildContext context,
    AppColorExtension colors,
  ) {
    final chip = InkWell(
      onTap: onSwitchDb,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceElevated.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          mainAxisAlignment: isCollapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(Icons.storage_outlined, size: 16, color: colors.textMuted),
            if (!isCollapsed) ...[
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  currentDbName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Tooltip(
      message: '当前数据库: $currentDbName\n点击切换或打开新库',
      waitDuration: const Duration(milliseconds: 300),
      child: chip,
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final colors = context.appColors;

    final item = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      hoverColor: colors.surfaceElevated.withValues(alpha: 0.4),
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(
          horizontal: isCollapsed ? 0 : AppSpacing.md,
        ),
        child: Row(
          mainAxisAlignment: isCollapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: colors.textMuted),
            if (!isCollapsed) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySecondary.copyWith(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1.0,
      ),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 300),
        child: item,
      ),
    );
  }

  Widget _buildCollapseToggle(BuildContext context, AppColorExtension colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2.0,
      ),
      child: Tooltip(
        message: onToggleCollapse == null
            ? '窄窗口自动折叠侧边栏'
            : (isCollapsed ? '展开侧边栏' : '折叠侧边栏'),
        child: InkWell(
          onTap: onToggleCollapse,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            height: 34,
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 0 : AppSpacing.md,
            ),
            child: Row(
              mainAxisAlignment: isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  isCollapsed ? Icons.chevron_right : Icons.chevron_left,
                  size: 18,
                  color: colors.textMuted,
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '折叠侧边栏',
                    style: AppTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
