import 'dart:io';
import '../services/disease_service.dart';
import 'disease_result.dart';
import 'severity_result.dart';

class ScanRecord {
  final int? id;
  final String diseaseName;
  final String scientificName;
  final double confidencePercentage;
  final bool isEnhancedByLada;
  final String severityLevel;
  final double affectedAreaPercentage;
  final String overview;
  final String? imagePath;
  final DateTime timestamp;

  const ScanRecord({
    this.id,
    required this.diseaseName,
    required this.scientificName,
    required this.confidencePercentage,
    this.isEnhancedByLada = false,
    required this.severityLevel,
    required this.affectedAreaPercentage,
    required this.overview,
    this.imagePath,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'disease_name': diseaseName,
      'scientific_name': scientificName,
      'confidence': confidencePercentage,
      'is_enhanced': isEnhancedByLada ? 1 : 0,
      'severity_level': severityLevel,
      'affected_percentage': affectedAreaPercentage,
      'overview': overview,
      'image_path': imagePath,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ScanRecord.fromMap(Map<String, dynamic> map) {
    return ScanRecord(
      id: map['id'] as int?,
      diseaseName: map['disease_name'] as String,
      scientificName: map['scientific_name'] as String,
      confidencePercentage: (map['confidence'] as num).toDouble(),
      isEnhancedByLada: (map['is_enhanced'] as int?) == 1,
      severityLevel: map['severity_level'] as String,
      affectedAreaPercentage: (map['affected_percentage'] as num).toDouble(),
      overview: map['overview'] as String,
      imagePath: map['image_path'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  factory ScanRecord.fromDiseaseResult(DiseaseResult result) {
    return ScanRecord(
      diseaseName: result.diseaseName,
      scientificName: result.scientificName,
      confidencePercentage: result.confidencePercentage,
      isEnhancedByLada: result.isLadaEnhanced,
      severityLevel: result.severity.level.displayName,
      affectedAreaPercentage: result.severity.affectedAreaPercentage,
      overview: result.overview,
      imagePath: result.imageData.originalFile?.path,
      timestamp: DateTime.now(),
    );
  }

  /// Convert ScanRecord back into a full DiseaseResult for re-inspection in UI screens
  DiseaseResult toDiseaseResult() {
    SeverityLevel parseSeverity(String levelStr) {
      if (levelStr.toLowerCase().contains('very severe')) {
        return SeverityLevel.verySevere;
      }
      if (levelStr.toLowerCase().contains('very mild')) {
        return SeverityLevel.veryMild;
      }
      if (levelStr.toLowerCase().contains('mild')) return SeverityLevel.mild;
      if (levelStr.toLowerCase().contains('moderate')) {
        return SeverityLevel.moderate;
      }
      if (levelStr.toLowerCase().contains('severe')) {
        return SeverityLevel.severe;
      }
      return SeverityLevel.healthy;
    }

    final severityObj = SeverityResult(
      level: parseSeverity(severityLevel),
      affectedAreaPercentage: affectedAreaPercentage,
      totalLesionCount: null,
      primarySymptom: 'Historical mask is unavailable for this saved scan',
      leafTissueHealthScore: null,
    );

    return DiseaseResult(
      diseaseName: diseaseName,
      scientificName: scientificName,
      confidencePercentage: confidencePercentage,
      overview: overview,
      imageData: ProcessedImageData(
        originalFile: imagePath != null ? File(imagePath!) : null,
      ),
      severity: severityObj,
      treatment: DiseaseService.getDefaultTreatment(),
      isLadaEnhanced: isEnhancedByLada,
    );
  }
}
