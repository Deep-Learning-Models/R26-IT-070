import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/severity_result.dart';

class LadaBadgeChip extends StatelessWidget {
  final bool isEnhanced;

  const LadaBadgeChip({super.key, required this.isEnhanced});

  @override
  Widget build(BuildContext context) {
    if (isEnhanced) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withOpacity(0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              'Enhanced by LADA',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_outlined, color: Colors.white, size: 16),
          SizedBox(width: 6),
          Text(
            'Original Input',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class SeverityBadgeChip extends StatelessWidget {
  final SeverityLevel level;

  const SeverityBadgeChip({super.key, required this.level});

  Color get _color {
    switch (level) {
      case SeverityLevel.veryMild:
        return AppTheme.severityMild;
      case SeverityLevel.mild:
        return AppTheme.severityMild;
      case SeverityLevel.moderate:
        return AppTheme.severityModerate;
      case SeverityLevel.severe:
        return AppTheme.severitySevere;
      case SeverityLevel.verySevere:
        return AppTheme.severitySevere;
      case SeverityLevel.healthy:
        return AppTheme.primaryDark;
    }
  }

  IconData get _icon {
    switch (level) {
      case SeverityLevel.veryMild:
        return Icons.info_outline;
      case SeverityLevel.mild:
        return Icons.info_outline;
      case SeverityLevel.moderate:
        return Icons.warning_amber_rounded;
      case SeverityLevel.severe:
        return Icons.error_outline;
      case SeverityLevel.verySevere:
        return Icons.error_outline;
      case SeverityLevel.healthy:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: _color, size: 16),
          const SizedBox(width: 6),
          Text(
            'Severity: ${level.displayName}',
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
