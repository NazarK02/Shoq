import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

class UiScaleData {
  UiScaleData._({
    required this.screenSize,
    required this.screenScale,
    required this.userScale,
  }) : layoutScale = (screenScale * userScale).clamp(0.72, 1.5).toDouble();

  final Size screenSize;
  final double screenScale;
  final double userScale;
  final double layoutScale;

  bool get isCompactPhone => screenSize.width < 360 || screenSize.height < 700;
  bool get isTablet => screenSize.shortestSide >= 600;

  double scale(double base, {double min = 0, double max = double.infinity}) {
    return (base * layoutScale).clamp(min, max).toDouble();
  }

  int columns({
    required int compactPhone,
    required int phone,
    required int tablet,
  }) {
    if (isTablet) {
      return tablet;
    }
    return isCompactPhone ? compactPhone : phone;
  }
}

extension UiScaleContext on BuildContext {
  UiScaleData get uiScaleData {
    final size = MediaQuery.sizeOf(this);
    final screenScale = (size.shortestSide / 390).clamp(0.88, 1.18).toDouble();
    final userScale = ThemeService().uiScale;
    return UiScaleData._(
      screenSize: size,
      screenScale: screenScale,
      userScale: userScale,
    );
  }
}
