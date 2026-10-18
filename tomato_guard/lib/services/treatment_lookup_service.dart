import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/severity_result.dart';
import '../models/treatment_info.dart';

class TreatmentLookupService {
  static List<Map<String, dynamic>>? _cachedData;

  /// Loads the treatment lookup dataset from assets
  static Future<void> init() async {
    if (_cachedData != null) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/treatment_lookup.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      _cachedData = jsonList.cast<Map<String, dynamic>>();
      debugPrint('[TreatmentLookupService] Loaded ${_cachedData!.length} treatment guidelines.');
    } catch (e) {
      debugPrint('[TreatmentLookupService] Failed to load JSON: $e');
    }
  }

  /// Normalizes disease names to match dataset keys
  static String _normalizeDiseaseName(String rawName) {
    final lower = rawName.toLowerCase();
    if (lower.contains('bacterial')) return 'Bacterial Spot';
    if (lower.contains('early blight')) return 'Early Blight';
    if (lower.contains('late blight')) return 'Late Blight';
    if (lower.contains('leaf mold')) return 'Leaf Mold';
    if (lower.contains('septoria')) return 'Septoria Leaf Spot';
    if (lower.contains('spider')) return 'Spider Mites';
    if (lower.contains('yellow leaf curl') || lower.contains('tylcv')) return 'TYLCV';
    if (lower.contains('mosaic')) return 'Mosaic Virus';
    if (lower.contains('target')) return 'Target Spot';
    if (lower.contains('miner')) return 'Leaf Miner';
    if (lower.contains('no tomato leaf')) return 'No Tomato Leaf Detected';
    if (lower.contains('healthy')) return 'Healthy';
    return rawName.replaceAll('Tomato ', '').trim();
  }

  /// Gets tailored treatment recommendations based on Disease and Severity Level
  static Future<TreatmentInfo> getTreatment({
    required String diseaseName,
    required SeverityLevel severityLevel,
  }) async {
    if (_cachedData == null) {
      await init();
    }

    final normalizedDisease = _normalizeDiseaseName(diseaseName);

    if (normalizedDisease == 'No Tomato Leaf Detected') {
      return const TreatmentInfo(
        diseaseName: 'No Tomato Leaf Detected',
        culturalPractices: [
          TreatmentItem(
            title: 'Point Camera at a Tomato Leaf',
            description: 'Ensure the subject is an actual tomato leaf and is centered within the frame.',
            dosageOrFrequency: 'During photo capture',
          ),
          TreatmentItem(
            title: 'Ensure Adequate Lighting',
            description: 'Avoid dark shadows or intense direct glare which can obscure plant texture.',
            dosageOrFrequency: 'During photo capture',
          ),
        ],
        organicTreatments: [],
        chemicalTreatments: [],
      );
    }

    // Convert SeverityLevel to query strings
    final List<String> targetSeverities = [];
    switch (severityLevel) {
      case SeverityLevel.mild:
        targetSeverities.add('Mild');
        break;
      case SeverityLevel.moderate:
        targetSeverities.add('Moderate');
        break;
      case SeverityLevel.severe:
        targetSeverities.addAll(['Severe', 'Extremely Severe']);
        break;
      case SeverityLevel.healthy:
        targetSeverities.add('Healthy');
        break;
    }

    final List<Map<String, dynamic>> matchingRows = [];
    if (_cachedData != null) {
      for (var row in _cachedData!) {
        final rowDisease = (row['disease'] ?? '').toString();
        final rowSeverity = (row['severity'] ?? '').toString();

        if (rowDisease.toLowerCase() == normalizedDisease.toLowerCase()) {
          if (targetSeverities.any((s) => s.toLowerCase() == rowSeverity.toLowerCase())) {
            matchingRows.add(row);
          }
        }
      }
    }

    // If no exact severity match found, fallback to any rows for this disease
    if (matchingRows.isEmpty && _cachedData != null) {
      for (var row in _cachedData!) {
        final rowDisease = (row['disease'] ?? '').toString();
        if (rowDisease.toLowerCase() == normalizedDisease.toLowerCase()) {
          matchingRows.add(row);
        }
      }
    }

    final List<TreatmentItem> cultural = [];
    final List<TreatmentItem> organic = [];
    final List<TreatmentItem> chemical = [];

    for (var row in matchingRows) {
      final String text = row['treatment'] ?? '';
      final String source = row['source'] ?? 'DOA Sri Lanka';
      final item = _parseTreatmentItem(text, source);

      final lowerText = text.toLowerCase();
      if (lowerText.contains('neem') ||
          lowerText.contains('trichoderma') ||
          lowerText.contains('bacillus') ||
          lowerText.contains('organic') ||
          lowerText.contains('bio-') ||
          lowerText.contains('compost') ||
          lowerText.contains('soap')) {
        organic.add(item);
      } else if (lowerText.contains('wp') ||
          lowerText.contains('sc') ||
          lowerText.contains('ec') ||
          lowerText.contains('mancozeb') ||
          lowerText.contains('metalaxyl') ||
          lowerText.contains('chlorothalonil') ||
          lowerText.contains('copper') ||
          lowerText.contains('azoxystrobin') ||
          lowerText.contains('iprodione') ||
          lowerText.contains('propiconazole') ||
          lowerText.contains('tebuconazole') ||
          lowerText.contains('abamectin') ||
          lowerText.contains('imidacloprid') ||
          lowerText.contains('thiamethoxam') ||
          lowerText.contains('spray') ||
          lowerText.contains('apply')) {
        chemical.add(item);
      } else {
        cultural.add(item);
      }
    }

    // Default fallbacks if any list is empty
    if (cultural.isEmpty && normalizedDisease != 'Healthy') {
      cultural.add(const TreatmentItem(
        title: 'Field Sanitation & Airflow',
        description: 'Remove heavily infected foliage from plant canopy. Prune lower suckers to improve sunlight penetration and air circulation.',
        dosageOrFrequency: 'Weekly during growing season',
      ));
    }

    if (organic.isEmpty && normalizedDisease != 'Healthy') {
      organic.add(const TreatmentItem(
        title: 'Bio-Fungicide / Organic Neem Spray',
        description: 'Apply organic cold-pressed neem oil formulation or Bacillus subtilis bio-fungicide to inhibit secondary pathogen spread.',
        dosageOrFrequency: '10-15ml per 10L water every 7 days',
      ));
    }

    if (chemical.isEmpty && normalizedDisease != 'Healthy') {
      chemical.add(const TreatmentItem(
        title: 'DOA Recommended Protective Spray',
        description: 'Consult local agricultural extension officer for certified fungicide/bactericide recommendations.',
        dosageOrFrequency: 'As advised by DOA Sri Lanka',
      ));
    }

    return TreatmentInfo(
      diseaseName: '$diseaseName (${severityLevel.displayName}) - DOA Sri Lanka',
      culturalPractices: cultural,
      organicTreatments: organic,
      chemicalTreatments: chemical,
    );
  }

  static TreatmentItem _parseTreatmentItem(String text, String source) {
    String title = 'DOA Guideline';
    String dosage = 'As directed by DOA';

    // Try to extract title (e.g. "Apply Mancozeb 80% WP")
    if (text.startsWith('Apply ')) {
      final parts = text.split(' at ');
      if (parts.length > 1) {
        title = parts[0].replaceAll('Apply ', '').trim();
        final doseParts = parts[1].split('. ');
        dosage = doseParts[0].trim();
      } else {
        final dotParts = text.split('. ');
        title = dotParts[0].replaceAll('Apply ', '').trim();
      }
    } else if (text.startsWith('Remove ') || text.startsWith('Destroy ') || text.startsWith('Prune ')) {
      final parts = text.split('. ');
      title = parts[0].trim();
      dosage = 'Immediate agronomic action';
    } else {
      final parts = text.split('. ');
      title = parts[0].trim();
      if (parts.length > 1 && parts[1].toLowerCase().contains('every')) {
        dosage = parts[1].trim();
      }
    }

    return TreatmentItem(
      title: title,
      description: text,
      dosageOrFrequency: dosage,
    );
  }
}
