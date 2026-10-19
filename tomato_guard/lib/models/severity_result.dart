import 'dart:typed_data';

enum SeverityLevel {
  veryMild,
  mild,
  moderate,
  severe,
  healthy,
  verySevere,
}

extension SeverityLevelExtension on SeverityLevel {
  String get displayName {
    switch (this) {
      case SeverityLevel.veryMild:
        return 'Very Mild';
      case SeverityLevel.mild:
        return 'Mild';
      case SeverityLevel.moderate:
        return 'Moderate';
      case SeverityLevel.severe:
        return 'Severe';
      case SeverityLevel.verySevere:
        return 'Very Severe';
      case SeverityLevel.healthy:
        return 'Healthy / Negligible';
    }
  }

  String get description {
    switch (this) {
      case SeverityLevel.veryMild:
        return 'Very mild changes detected. Monitor the leaf and follow the recommended care.';
      case SeverityLevel.mild:
        return 'Mild disease signs detected. Monitor the plant and follow the recommended care.';
      case SeverityLevel.moderate:
        return 'Moderate disease signs detected. Review the treatment recommendations.';
      case SeverityLevel.severe:
        return 'Severe disease signs detected. Prompt treatment and monitoring are recommended.';
      case SeverityLevel.verySevere:
        return 'Very severe disease signs detected. Prompt treatment and monitoring are recommended.';
      case SeverityLevel.healthy:
        return 'The severity model found negligible disease signs.';
    }
  }
}

class SeverityResult {
  final SeverityLevel level;
  final double affectedAreaPercentage; // e.g. 24.5%
  final int? totalLesionCount;
  final String primarySymptom;
  final String? leafTissueHealthScore;
  final Uint8List? maskImageBytes;

  const SeverityResult({
    required this.level,
    required this.affectedAreaPercentage,
    required this.totalLesionCount,
    required this.primarySymptom,
    required this.leafTissueHealthScore,
    this.maskImageBytes,
  });
}
