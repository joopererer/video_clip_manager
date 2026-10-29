import 'package:flutter/material.dart';

/// Dark Media Workspace 间距与尺寸 Token
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // 典型界面骨架尺寸
  static const double topToolbarHeight = 60.0;
  static const double sidebarExpandedWidth = 208.0;
  static const double sidebarCollapsedWidth = 64.0;
  static const double minWindowWidth = 900.0;
}

/// 统一圆角 Token
class AppRadius {
  AppRadius._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 10.0;
  static const double card = 12.0;
  static const double modal = 16.0;
  static const double round = 999.0;

  static const Radius radiusXs = Radius.circular(xs);
  static const Radius radiusSm = Radius.circular(sm);
  static const Radius radiusMd = Radius.circular(md);
  static const Radius radiusCard = Radius.circular(card);
  static const Radius radiusModal = Radius.circular(modal);
  static const Radius radiusRound = Radius.circular(round);

  static const BorderRadius borderXs = BorderRadius.all(radiusXs);
  static const BorderRadius borderSm = BorderRadius.all(radiusSm);
  static const BorderRadius borderMd = BorderRadius.all(radiusMd);
  static const BorderRadius borderCard = BorderRadius.all(radiusCard);
  static const BorderRadius borderModal = BorderRadius.all(radiusModal);
  static const BorderRadius borderRound = BorderRadius.all(radiusRound);
}
