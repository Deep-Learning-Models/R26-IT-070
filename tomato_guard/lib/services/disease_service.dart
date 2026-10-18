
import 'dart:io';
import 'dart:typed_data';
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

class DetectionResult {
  final Rect boundingBox;
  final int classIndex;
  final double confidence;

  DetectionResult(this.boundingBox, this.classIndex, this.confidence);
}

class DiseaseService {
  /// Disease Detection with YOLOv8, Segmentation with ALAS-Net, and DOA Treatment Lookup
  static Future<DiseaseResult> classifyImage(
    ProcessedImageData imageData, {
    bool enhanceWithLada = true,
  }) async {
    ProcessedImageData finalImageData = imageData;

    if (enhanceWithLada) {
      final enhancedBytes = await LadaModule.getEnhancedImageBytes(imageData);
      if (enhancedBytes != null) {
        finalImageData = ProcessedImageData(
          originalFile: imageData.originalFile,
          imageBytes: enhancedBytes,
        );
      }
    }

    final result = await _runYoloV8Inference(finalImageData);
    final int classIdx = result.classIndex;
    final matchedDisease = _diseaseDatabase[classIdx];

    // Step 2: If healthy or no leaf, zero severity; otherwise run ALAS-Net pixel segmentation!
    SeverityResult finalSeverity;
    if (classIdx == 2) {
      finalSeverity = const SeverityResult(
        level: SeverityLevel.healthy,
        affectedAreaPercentage: 0.0,
        totalLesionCount: 0,
        primarySymptom: 'No pathological symptoms detected',
        leafTissueHealthScore: '100 / 100',
      );
    } else if (classIdx == 10) {
      finalSeverity = const SeverityResult(
        level: SeverityLevel.healthy,
        affectedAreaPercentage: 0.0,
        totalLesionCount: 0,
        primarySymptom: 'No tomato leaf identified in image',
        leafTissueHealthScore: 'N/A',
      );
    } else {
      finalSeverity = await SegmentationService.analyzeSeverity(
        finalImageData,
        matchedDisease.diseaseName,
      );
    }

    // Step 3: Lookup exact treatment guidelines from DOA dataset based on disease & severity
    final treatment = await TreatmentLookupService.getTreatment(
      diseaseName: matchedDisease.diseaseName,
      severityLevel: finalSeverity.level,
    );

    return DiseaseResult(
      diseaseName: matchedDisease.diseaseName,
      scientificName: matchedDisease.scientificName,
      confidencePercentage: double.parse((result.confidence * 100).toStringAsFixed(1)),
      overview: matchedDisease.overview,
      imageData: finalImageData,
      severity: finalSeverity,
      treatment: treatment,
      isLadaEnhanced: enhanceWithLada,
    );
  }

  static Future<_YoloOutput> _runYoloV8Inference(ProcessedImageData imageData) async {
    const String modelAsset = 'assets/models/classification.tflite';
    try {
      final ByteData modelData = await rootBundle.load(modelAsset);
      final Uint8List modelBytes = modelData.buffer.asUint8List();

      final output = await compute(_runYolov8Isolate, {
        'imagePath': imageData.originalFile?.path,
        'imageBytes': imageData.imageBytes,
        'modelBytes': modelBytes,
      });

      if (output != null) {
        return output;
      }
    } catch (e) {
      debugPrint("YOLOv8 error: $e");
    }

    // Fallback when no leaf / inference fails -> No Tomato Leaf (index 10)
    return _YoloOutput(10, 0.0, const SeverityResult(
      level: SeverityLevel.healthy,
      affectedAreaPercentage: 0.0,
      totalLesionCount: 0,
      primarySymptom: 'No tomato leaf identified in image',
      leafTissueHealthScore: 'N/A',
    ));
  }

  static _YoloOutput? _runYolov8Isolate(Map<String, dynamic> args) {
    final String? imagePath = args['imagePath'];
    final Uint8List? imageBytesRaw = args['imageBytes'];
    final Uint8List modelBytes = args['modelBytes'];

    Interpreter? interpreter;
    try {
      final options = InterpreterOptions()..threads = 4;
      interpreter = Interpreter.fromBuffer(modelBytes, options: options);
    } catch (e) {
      print('[YOLOv8] FATAL: Could not load model: $e');
      return null;
    }

    Uint8List? finalBytes = imageBytesRaw;
    if (finalBytes == null && imagePath != null) {
      final file = File(imagePath);
      if (file.existsSync()) finalBytes = file.readAsBytesSync();
    }
    if (finalBytes == null) return null;

    final img.Image? decoded = img.decodeImage(finalBytes);
    if (decoded == null) return null;

    final int width = 640;
    final int height = 640;
    final img.Image resized = img.copyResize(decoded, width: width, height: height);

    // YOLOv8 uses NCHW typically, and values 0-1
    final tensor = List.generate(
      1,
      (_) => List.generate(
        3,
        (_) => List.generate(
          height,
          (_) => List.filled(width, 0.0),
        ),
      ),
    );

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = resized.getPixel(x, y);
        tensor[0][0][y][x] = pixel.r / 255.0;
        tensor[0][1][y][x] = pixel.g / 255.0;
        tensor[0][2][y][x] = pixel.b / 255.0;
      }
    }

    // Run inference
    final outputShape = [1, 14, 8400]; // 4 bbox + 10 classes
    final outputTensor = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List.filled(outputShape[2], 0.0),
      ),
    );

    try {
      interpreter.run(tensor, outputTensor);
    } catch (e) {
      print('[YOLOv8] Inference failed: $e');
      return null;
    } finally {
      interpreter.close();
    }

    final List<DetectionResult> detections = [];
    final double confThreshold = 0.25;

    for (int i = 0; i < 8400; i++) {
      double maxClassConf = 0.0;
      int maxClassIndex = -1;
      
      for (int c = 0; c < 10; c++) {
        final conf = outputTensor[0][c + 4][i];
        if (conf > maxClassConf) {
          maxClassConf = conf;
          maxClassIndex = c;
        }
      }

      if (maxClassConf > confThreshold) {
        final cx = outputTensor[0][0][i];
        final cy = outputTensor[0][1][i];
        final w = outputTensor[0][2][i];
        final h = outputTensor[0][3][i];

        final rect = Rect.fromCenter(
          center: Offset(cx, cy),
          width: w,
          height: h,
        );

        detections.add(DetectionResult(rect, maxClassIndex, maxClassConf));
      }
    }

    final nmsDetections = _applyNMS(detections, 0.45);

    if (nmsDetections.isEmpty) {
      return _YoloOutput(10, 0.0, const SeverityResult(
        level: SeverityLevel.healthy,
        affectedAreaPercentage: 0.0,
        totalLesionCount: 0,
        primarySymptom: 'No tomato leaf identified in image',
        leafTissueHealthScore: 'N/A',
      ));
    }

    nmsDetections.sort((a, b) => b.confidence.compareTo(a.confidence));
    final topDetection = nmsDetections.first;

    // Check if the top detection is Healthy (class 2) but has low confidence (< 0.35)
    if (topDetection.classIndex == 2 && topDetection.confidence < 0.35) {
      return _YoloOutput(10, 0.0, const SeverityResult(
        level: SeverityLevel.healthy,
        affectedAreaPercentage: 0.0,
        totalLesionCount: 0,
        primarySymptom: 'No tomato leaf identified in image',
        leafTissueHealthScore: 'N/A',
      ));
    }

    double totalBBoxArea = 0.0;
    for (var det in nmsDetections) {
      if (det.classIndex != 2) {
        totalBBoxArea += (det.boundingBox.width * det.boundingBox.height);
      }
    }

    final double imageArea = 640.0 * 640.0;
    double severityPercentage = (totalBBoxArea / imageArea) * 100.0;
    severityPercentage = severityPercentage.clamp(0.0, 100.0);

    int lesionCount = nmsDetections.where((d) => d.classIndex != 2).length;
    severityPercentage = (severityPercentage + (lesionCount * 0.5)).clamp(0.0, 100.0);

    SeverityLevel level = SeverityLevel.healthy;
    if (severityPercentage > 30) {
      level = SeverityLevel.severe;
    } else if (severityPercentage > 0) {
      level = SeverityLevel.moderate;
    }

    final severity = SeverityResult(
      level: level,
      affectedAreaPercentage: double.parse(severityPercentage.toStringAsFixed(1)),
      totalLesionCount: lesionCount,
      primarySymptom: lesionCount > 0 ? 'Multiple disease lesions detected' : 'No symptoms',
      leafTissueHealthScore: '${(100.0 - severityPercentage).toStringAsFixed(1)} / 100',
    );

    return _YoloOutput(topDetection.classIndex, topDetection.confidence, severity);
  }

  static List<DetectionResult> _applyNMS(List<DetectionResult> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];

    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    final List<DetectionResult> picked = [];

    for (var box in boxes) {
      bool keep = true;
      for (var pickedBox in picked) {
        if (box.classIndex != pickedBox.classIndex) continue;
        
        final double iou = _calculateIoU(box.boundingBox, pickedBox.boundingBox);
        if (iou > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) {
        picked.add(box);
      }
    }
    return picked;
  }

  static double _calculateIoU(Rect a, Rect b) {
    final double intersectionArea = a.intersect(b).width.clamp(0.0, double.infinity) * 
                                    a.intersect(b).height.clamp(0.0, double.infinity);
    final double unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0.0) return 0.0;
    return intersectionArea / unionArea;
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
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'Bacterial Spot', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Early Blight',
      scientificName: 'Alternaria solani',
      confidencePercentage: 90.0,
      overview: 'Early blight causes dark concentric rings.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'Early Blight', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Healthy Tomato Plant',
      scientificName: 'Lycopersicon esculentum',
      confidencePercentage: 99.0,
      overview: 'Plant is healthy with no pathogens.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.healthy, affectedAreaPercentage: 0, totalLesionCount: 0, primarySymptom: 'None', leafTissueHealthScore: '100/100'),
      treatment: TreatmentInfo(diseaseName: 'Healthy', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Late Blight',
      scientificName: 'Phytophthora infestans',
      confidencePercentage: 90.0,
      overview: 'Late blight is a fast-spreading disease causing dark lesions.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'Late Blight', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Leaf Mold',
      scientificName: 'Passalora fulva',
      confidencePercentage: 90.0,
      overview: 'Leaf mold causes pale spots with mold on underside.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'Leaf Mold', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Leaf Miner',
      scientificName: 'Liriomyza',
      confidencePercentage: 90.0,
      overview: 'Leaf miners create white winding trails or mines in the leaf tissue.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'White winding trails', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'Leaf Miner', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Mosaic Virus',
      scientificName: 'ToMV',
      confidencePercentage: 90.0,
      overview: 'Causes mottled mosaic chlorosis.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'ToMV', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Septoria Leaf Spot',
      scientificName: 'Septoria lycopersici',
      confidencePercentage: 90.0,
      overview: 'Causes numerous small, circular spots with dark borders.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'Septoria Leaf Spot', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Spider Mites',
      scientificName: 'Tetranychus urticae',
      confidencePercentage: 90.0,
      overview: 'Spider mites cause stippling and webbing.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'Spider Mites', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    DiseaseResult(
      diseaseName: 'Tomato Yellow Leaf Curl Virus',
      scientificName: 'TYLCV',
      confidencePercentage: 90.0,
      overview: 'Causes severe upward curling of leaf margins.',
      imageData: ProcessedImageData(),
      severity: SeverityResult(level: SeverityLevel.moderate, affectedAreaPercentage: 10, totalLesionCount: 5, primarySymptom: 'Spots', leafTissueHealthScore: '90/100'),
      treatment: TreatmentInfo(diseaseName: 'TYLCV', culturalPractices: [], organicTreatments: [], chemicalTreatments: []),
    ),
    // 10: No Tomato Leaf Detected
    DiseaseResult(
      diseaseName: 'No Tomato Leaf Detected',
      scientificName: 'Non-Plant / Inconclusive Subject',
      confidencePercentage: 0.0,
      overview: 'No tomato foliage or recognizable disease symptoms were detected in the provided image. Please capture a clear, well-lit photo centered on a tomato leaf.',
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
      ),
    ),
  ];

}

class _YoloOutput {
  final int classIndex;
  final double confidence;
  final SeverityResult severityResult;

  _YoloOutput(this.classIndex, this.confidence, this.severityResult);
}
