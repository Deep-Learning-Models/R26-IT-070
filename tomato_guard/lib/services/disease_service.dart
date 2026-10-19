import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/disease_result.dart';
import '../models/severity_result.dart';
import '../models/treatment_info.dart';
import 'lada_module.dart';
import 'segmentation_service.dart';
import 'treatment_lookup_service.dart';

class DiseaseService {
  static const String _modelAsset = 'assets/models/classification.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';

  /// Classify a leaf with the ALAS-Net model, then analyze disease severity.
  static Future<DiseaseResult> classifyImage(
    ProcessedImageData imageData, {
    bool enhanceWithLada = true,
  }) async {
    ProcessedImageData finalImageData = imageData;
    bool didEnhance = false;

    if (enhanceWithLada) {
      final enhancedBytes = await LadaModule.getEnhancedImageBytes(imageData);
      if (enhancedBytes != null) {
        finalImageData = ProcessedImageData(
          originalFile: imageData.originalFile,
          imageBytes: enhancedBytes,
        );
        didEnhance = true;
      }
    }

    final prediction = await _runClassifierInference(finalImageData);
    final labels = (await rootBundle.loadString(_labelsAsset))
        .split(RegExp(r'\r?\n'))
        .where((label) => label.isNotEmpty)
        .toList();
    if (labels.length != 10) {
      throw StateError('Expected 10 disease labels, found ${labels.length}');
    }
    final diseaseName = labels[prediction.classIndex];
    final matchedDisease = _diseaseDatabase.firstWhere(
      (disease) => disease.diseaseName == diseaseName,
      orElse: () => throw StateError('No disease details for $diseaseName'),
    );

    final severity = await SegmentationService.analyzeSeverity(imageData);

    final treatment = await TreatmentLookupService.getTreatment(
      diseaseName: diseaseName,
      severityLevel: severity.level,
    );

    return DiseaseResult(
      diseaseName: diseaseName,
      scientificName: matchedDisease.scientificName,
      confidencePercentage:
          double.parse((prediction.confidence * 100).toStringAsFixed(1)),
      overview: matchedDisease.overview,
      imageData: imageData,
      severity: severity,
      treatment: treatment,
      isLadaEnhanced: didEnhance,
    );
  }

  static Future<_ClassifierOutput> _runClassifierInference(
    ProcessedImageData imageData,
  ) async {
    final modelData = await rootBundle.load(_modelAsset);
    return compute(_runClassifierIsolate, {
      'imagePath': imageData.originalFile?.path,
      'imageBytes': imageData.imageBytes,
      'modelBytes': modelData.buffer.asUint8List(),
    });
  }

  static _ClassifierOutput _runClassifierIsolate(Map<String, dynamic> args) {
    Uint8List? imageBytes = args['imageBytes'];
    final String? imagePath = args['imagePath'];
    if (imageBytes == null && imagePath != null) {
      imageBytes = File(imagePath).readAsBytesSync();
    }
    if (imageBytes == null) {
      throw StateError('No image available for disease classification');
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw StateError('The image could not be decoded');
    }

    final interpreter = Interpreter.fromBuffer(
      args['modelBytes'] as Uint8List,
      options: InterpreterOptions()..threads = 4,
    );
    try {
      if (!listEquals(interpreter.getInputTensor(0).shape, [1, 256, 256, 3]) ||
          !listEquals(interpreter.getOutputTensor(0).shape, [1, 10])) {
        throw StateError('Unexpected disease classifier tensor shapes');
      }

      const int size = 256;
      final resized = img.copyResize(decoded, width: size, height: size);
      final input = List.generate(
        1,
        (_) => List.generate(
          size,
          (y) => List.generate(
            size,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
            },
          ),
        ),
      );
      final output = [List<double>.filled(10, 0.0)];
      interpreter.run(input, output);

      int bestIndex = 0;
      for (int index = 1; index < output[0].length; index++) {
        if (output[0][index] > output[0][bestIndex]) bestIndex = index;
      }
      return _ClassifierOutput(bestIndex, output[0][bestIndex]);
    } finally {
      interpreter.close();
    }
  }

  static TreatmentInfo getDefaultTreatment() {
    return _diseaseDatabase[1].treatment;
  }

  static const List<DiseaseResult> _diseaseDatabase = [
    DiseaseResult(
      diseaseName: 'Tomato Bacterial Spot',
      scientificName: 'Xanthomonas',
      confidencePercentage: 90.0,
      overview: 'Bacterial spot produces small, dark, water-soaked lesions.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Bacterial Spot',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Early Blight',
      scientificName: 'Alternaria solani',
      confidencePercentage: 90.0,
      overview: 'Early blight causes dark concentric rings.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Early Blight',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Healthy Tomato Plant',
      scientificName: 'Lycopersicon esculentum',
      confidencePercentage: 99.0,
      overview: 'Plant is healthy with no pathogens.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.healthy,
          affectedAreaPercentage: 0,
          totalLesionCount: 0,
          primarySymptom: 'None',
          leafTissueHealthScore: '100/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Healthy',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Late Blight',
      scientificName: 'Phytophthora infestans',
      confidencePercentage: 90.0,
      overview: 'Late blight is a fast-spreading disease causing dark lesions.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Late Blight',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Leaf Mold',
      scientificName: 'Passalora fulva',
      confidencePercentage: 90.0,
      overview: 'Leaf mold causes pale spots with mold on underside.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Leaf Mold',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Leaf Miner',
      scientificName: 'Liriomyza',
      confidencePercentage: 90.0,
      overview:
          'Leaf miners create white winding trails or mines in the leaf tissue.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'White winding trails',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Leaf Miner',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Mosaic Virus',
      scientificName: 'ToMV',
      confidencePercentage: 90.0,
      overview: 'Causes mottled mosaic chlorosis.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'ToMV',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Septoria Leaf Spot',
      scientificName: 'Septoria lycopersici',
      confidencePercentage: 90.0,
      overview: 'Causes numerous small, circular spots with dark borders.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Septoria Leaf Spot',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Spider Mites',
      scientificName: 'Tetranychus urticae',
      confidencePercentage: 90.0,
      overview: 'Spider mites cause stippling and webbing.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Spider Mites',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Target Spot',
      scientificName: 'Corynespora cassiicola',
      confidencePercentage: 90.0,
      overview: 'Target spot causes brown leaf lesions with concentric rings.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'Target Spot',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Yellow Leaf Curl Virus',
      scientificName: 'TYLCV',
      confidencePercentage: 90.0,
      overview: 'Causes severe upward curling of leaf margins.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
          level: SeverityLevel.moderate,
          affectedAreaPercentage: 10,
          totalLesionCount: 5,
          primarySymptom: 'Spots',
          leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(
          diseaseName: 'TYLCV',
          culturalPractices: [],
          organicTreatments: [],
          chemicalTreatments: []),
    ),
    // Kept for scans created by the separate leaf-detection flow.
    DiseaseResult(
      diseaseName: 'No Tomato Leaf Detected',
      scientificName: 'Non-Plant / Inconclusive Subject',
      confidencePercentage: 0.0,
      overview:
          'No tomato foliage or recognizable disease symptoms were detected in the provided image. Please capture a clear, well-lit photo centered on a tomato leaf.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(
        level: SeverityLevel.healthy,
        affectedAreaPercentage: 0.0,
        totalLesionCount: 0,
        primarySymptom: 'No tomato leaf identified in image',
        leafTissueHealthScore: 'N/A',
      ),
      treatment: TreatmentInfo(
        diseaseName: 'No Tomato Leaf Detected',
        culturalPractices: [
          TreatmentItem(
            title: 'Point Camera at a Tomato Leaf',
            description:
                'Ensure the subject is an actual tomato leaf and is centered within the frame.',
            dosageOrFrequency: 'During photo capture',
          ),
          TreatmentItem(
            title: 'Ensure Adequate Lighting',
            description:
                'Avoid dark shadows or intense direct glare which can obscure plant texture.',
            dosageOrFrequency: 'During photo capture',
          ),
        ],
        organicTreatments: [],
        chemicalTreatments: [],
      ),
    ),
  ];
}

class _ClassifierOutput {
  final int classIndex;
  final double confidence;

  _ClassifierOutput(this.classIndex, this.confidence);
}
