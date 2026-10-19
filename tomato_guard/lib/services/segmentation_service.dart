import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/disease_result.dart';
import '../models/severity_result.dart';

class SegmentationService {
  // ALAS-Net severity and lesion segmentation model with SLA.
  static const String modelAsset =
      'assets/models/alas_net_Severity_Segmentation_SLA_.tflite';

  /// Runs the SLA segmentation model to produce a lesion overlay and severity metrics.
  static Future<SeverityResult> analyzeSeverity(
    ProcessedImageData imageData,
  ) async {
    try {
      final ByteData modelData = await rootBundle.load(modelAsset);
      final Uint8List modelBytes = modelData.buffer.asUint8List();

      return await compute(_runSegmentationIsolate, {
        'imagePath': imageData.originalFile?.path,
        'imageBytes': imageData.imageBytes,
        'modelBytes': modelBytes,
      });
    } catch (e) {
      debugPrint('[SegmentationService] Error: $e');
      rethrow;
    }
  }

  static SeverityResult _runSegmentationIsolate(Map<String, dynamic> args) {
    final String? imagePath = args['imagePath'];
    final Uint8List? imageBytesRaw = args['imageBytes'];
    final Uint8List modelBytes = args['modelBytes'];

    Interpreter? interpreter;
    try {
      final options = InterpreterOptions()..threads = 2;
      interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      if (!listEquals(interpreter.getInputTensor(0).shape, [1, 256, 256, 3]) ||
          !listEquals(interpreter.getOutputTensor(0).shape, [1, 256, 256, 1]) ||
          !listEquals(interpreter.getOutputTensor(1).shape, [1, 4]) ||
          interpreter.getInputTensor(0).type != TensorType.float32 ||
          interpreter.getOutputTensor(0).type != TensorType.float32 ||
          interpreter.getOutputTensor(1).type != TensorType.float32) {
        throw StateError('Unexpected segmentation model tensor format');
      }
    } catch (e) {
      interpreter?.close();
      rethrow;
    }

    Uint8List? finalBytes = imageBytesRaw;
    if (finalBytes == null && imagePath != null) {
      final file = File(imagePath);
      if (file.existsSync()) finalBytes = file.readAsBytesSync();
    }
    if (finalBytes == null) {
      interpreter.close();
      throw StateError('No image available for segmentation');
    }

    final img.Image? decoded = img.decodeImage(finalBytes);
    if (decoded == null) {
      interpreter.close();
      throw StateError('The image could not be decoded');
    }

    const int targetSize = 256;
    final img.Image resized =
        img.copyResize(decoded, width: targetSize, height: targetSize);

    // Prepare input tensor: [1, 256, 256, 3] normalized [0, 1]
    final inputTensor = List.generate(
      1,
      (_) => List.generate(
        targetSize,
        (_) => List.generate(
          targetSize,
          (_) => List.filled(3, 0.0),
        ),
      ),
    );

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final pixel = resized.getPixel(x, y);
        inputTensor[0][y][x][0] = pixel.r / 255.0;
        inputTensor[0][y][x][1] = pixel.g / 255.0;
        inputTensor[0][y][x][2] = pixel.b / 255.0;
      }
    }

    // Output 0: Mask [1, 256, 256, 1]
    final maskOutput = List.generate(
      1,
      (_) => List.generate(
        targetSize,
        (_) => List.generate(
          targetSize,
          (_) => List.filled(1, 0.0),
        ),
      ),
    );

    // Output 1: CORAL rank probabilities for five ordered severity grades.
    final severityOutput = List.generate(
      1,
      (_) => List.filled(4, 0.0),
    );

    try {
      interpreter.runForMultipleInputs(
        [inputTensor],
        {0: maskOutput, 1: severityOutput},
      );
    } finally {
      interpreter.close();
    }

    // The exported model already applies its own leaf gate to this mask.
    // Display its output directly, without an additional colour filter.
    final img.Image maskImage = img.Image(
      width: targetSize,
      height: targetSize,
      numChannels: 4,
    );
    final int totalLeafPixels = _nativeLeafArea(resized);
    if (totalLeafPixels < targetSize * targetSize * 0.01) {
      throw StateError(
          'The model could not identify enough leaf area in this photo');
    }
    final acceptedLesions = List<bool>.filled(targetSize * targetSize, false);
    int diseasePixels = 0;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final double prob = maskOutput[0][y][x][0];
        if (!prob.isFinite || prob < 0.0 || prob > 1.0) {
          throw StateError(
              'Invalid lesion probability from segmentation model');
        }
        if (prob >= 0.5) {
          acceptedLesions[y * targetSize + x] = true;
          diseasePixels++;
          maskImage.setPixelRgba(x, y, 220, 45, 35, 160);
        } else {
          maskImage.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }

    // A thin outline makes the segmented regions readable like the notebook's
    // final visualization without changing the measured lesion area.
    for (int y = 1; y < targetSize - 1; y++) {
      for (int x = 1; x < targetSize - 1; x++) {
        final index = y * targetSize + x;
        if (acceptedLesions[index]) continue;
        if (acceptedLesions[index - targetSize] ||
            acceptedLesions[index + targetSize] ||
            acceptedLesions[index - 1] ||
            acceptedLesions[index + 1]) {
          maskImage.setPixelRgba(x, y, 255, 205, 20, 220);
        }
      }
    }

    final double affectedArea =
        (diseasePixels / totalLeafPixels * 100.0).clamp(0.0, 100.0);
    // The image is stretched to 256×256 for inference. Restore its original
    // aspect ratio so the mask follows the same BoxFit.cover as the photo.
    final img.Image displayMask = img.copyResize(
      maskImage,
      width: decoded.width,
      height: decoded.height,
      interpolation: img.Interpolation.nearest,
    );
    final Uint8List maskPngBytes =
        Uint8List.fromList(img.encodePng(displayMask));

    // Training decodes the CORAL head by counting thresholds above 0.5:
    // Healthy, Mild, Moderate, Severe, Very Severe.
    if (severityOutput[0]
        .any((score) => !score.isFinite || score < 0.0 || score > 1.0)) {
      throw StateError(
          'Invalid severity probabilities from segmentation model');
    }
    final int grade = severityOutput[0].where((score) => score > 0.5).length;
    final SeverityLevel level = switch (grade) {
      0 => SeverityLevel.healthy,
      1 => SeverityLevel.mild,
      2 => SeverityLevel.moderate,
      3 => SeverityLevel.severe,
      _ => SeverityLevel.verySevere,
    };

    final double displayPercent =
        double.parse(affectedArea.toStringAsFixed(1));
    return SeverityResult(
      level: level,
      affectedAreaPercentage: displayPercent,
      totalLesionCount: null,
      primarySymptom: diseasePixels > 0
          ? 'The model marked possible affected regions'
          : 'No affected regions passed the mask threshold',
      leafTissueHealthScore: null,
      maskImageBytes: maskPngBytes,
    );
  }

  static int _nativeLeafArea(img.Image image) {
    final int width = image.width;
    final int height = image.height;
    List<double> gate = List<double>.filled(width * height, 0.0);
    double sigmoid(double value) => 1.0 / (1.0 + exp(-value));

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final double r = pixel.r / 255.0;
        final double g = pixel.g / 255.0;
        final double b = pixel.b / 255.0;
        final double value = max(r, max(g, b));
        final double minimum = min(r, min(g, b));
        final double saturation = value > 0 ? (value - minimum) / value : 0.0;
        gate[y * width + x] = sigmoid((saturation - 0.12) * 40.0) *
            sigmoid((value - 0.05) * 40.0) *
            sigmoid((0.98 - value) * 40.0);
      }
    }

    // Reproduce the two SAME-padded 5×5 pooling steps in the exported gate.
    for (int pass = 0; pass < 2; pass++) {
      final smoothed = List<double>.filled(width * height, 0.0);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          double sum = 0.0;
          for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
              final int ny = y + dy;
              final int nx = x + dx;
              if (ny >= 0 && ny < height && nx >= 0 && nx < width) {
                sum += gate[ny * width + nx];
              }
            }
          }
          smoothed[y * width + x] = sum / 25.0;
        }
      }
      gate = smoothed;
    }

    return gate.where((value) => value >= 0.5).length;
  }
}
