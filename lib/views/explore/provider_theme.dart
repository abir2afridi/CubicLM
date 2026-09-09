import 'package:flutter/material.dart';

import '../../core/colors.dart';
import '../../theme/design_tokens.dart';

/// Accent color per cloud-provider id. Single source shared by provider
/// cards, local cards and key dialogs (was triplicated inline before).
Color providerAccent(String provider) {
  switch (provider) {
    case 'openrouter':
      return AppColors.success;
    case 'deepseek':
      return const Color(0xFF00B8A9);
    case 'google':
      return AppColors.warning;
    case 'nvidia':
      return const Color(0xFF76B900);
    case 'custom':
      return AppColors.info;
    default:
      return Dt.accent;
  }
}
