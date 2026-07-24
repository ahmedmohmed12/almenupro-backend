import 'package:flutter/material.dart';

/// Shared breakpoints for admin dashboard layouts.
class AdminBreakpoints {
  AdminBreakpoints._();

  static const double mobile = 900;
  static const double compact = 600;

  static bool isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < mobile;
  }

  static bool isCompact(BuildContext context) {
    return MediaQuery.sizeOf(context).width < compact;
  }

  static double pagePadding(BuildContext context) {
    return isMobile(context) ? 12 : 24;
  }
}
