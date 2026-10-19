import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/disease_result.dart';
import 'segmentation_service.dart';

/// On-demand occlusion sensitivity for the CORAL severity output.
/// This explains changes in severity scores; it is not Grad-CAM or a lesion mask.
class SeverityExplanationService {
  static Future<Uint8List?> explain(ProcessedImageData imageData) async {
    final modelData = await rootBundle.load(SegmentationService.modelAsset);
    return compute(_explainInIsolate, {
      'modelBytes': modelData.buffer.asUint8List(),
      'imageBytes': imageData.imageBytes,
      'imagePath': imageData.originalFile?.path,
    });
  }

  static Uint8List? _explainInIsolate(Map<String, dynamic> args) {
    final String? imagePath = args['imagePath'];
    Uint8List? imageBytes = args['imageBytes'];
    if (imageBytes == null && imagePath != null) {
      imageBytes = File(imagePath).readAsBytesSync();
    }
    if (imageBytes == null) {
      throw StateError('No photo is available for the explanation');
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw StateError('The photo could not be decoded');
    }

    const int imageSize = 256;
    const int gridSize = 4;
    const int patchSize = imageSize ~/ gridSize;
    final resized = img.copyResize(
      decoded,
      width: imageSize,
      height: imageSize,
    );
    final originalValues = Float32List(imageSize * imageSize * 3);
    final channelMeans = List<double>.filled(3, 0.0);
    final input = List.generate(
      1,
      (_) => List.generate(
        imageSize,
        (_) => List.generate(imageSize, (_) => List<double>.filled(3, 0.0)),
      ),
    );

    for (int y = 0; y < imageSize; y++) {
      for (int x = 0; x < imageSize; x++) {
        final pixel = resized.getPixel(x, y);
        final values = [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        for (int c = 0; c < 3; c++) {
          input[0][y][x][c] = values[c];
          originalValues[(y * imageSize + x) * 3 + c] = values[c];
          channelMeans[c] += values[c];
        }
      }
    }
    for (int c = 0; c < 3; c++) {
      channelMeans[c] /= imageSize * imageSize;
    }

    final interpreter = Interpreter.fromBuffer(
      args['modelBytes'] as Uint8List,
      options: InterpreterOptions()..threads = 2,
    );
    try {
      interpreter.runInference([input]);
      final outputs = interpreter.getOutputTensors();
      final severityIndex = outputs.indexWhere(
        (tensor) =>
            tensor.shape.length == 2 &&
            tensor.shape[0] == 1 &&
            tensor.shape[1] == 4,
      );
      if (severityIndex < 0) {
        throw StateError('The model has no four-score severity output');
      }

      double severityScore() {
        final scores = [List<double>.filled(4, 0.0)];
        interpreter.getOutputTensor(severityIndex).copyTo(scores);
        return scores[0].reduce((a, b) => a + b);
      }

      final baselineScore = severityScore();
      final drops = List<double>.filled(gridSize * gridSize, 0.0);

      for (int row = 0; row < gridSize; row++) {
        for (int col = 0; col < gridSize; col++) {
          final int x0 = col * patchSize;
          final int y0 = row * patchSize;
          for (int y = y0; y < y0 + patchSize; y++) {
            for (int x = x0; x < x0 + patchSize; x++) {
              for (int c = 0; c < 3; c++) {
                input[0][y][x][c] = channelMeans[c];
              }
            }
          }

          interpreter.runInference([input]);
          drops[row * gridSize + col] =
              max(0.0, baselineScore - severityScore());

          for (int y = y0; y < y0 + patchSize; y++) {
            for (int x = x0; x < x0 + patchSize; x++) {
              for (int c = 0; c < 3; c++) {
                input[0][y][x][c] = originalValues[(y * imageSize + x) * 3 + c];
              }
            }
          }
        }
      }

      final maxDrop = drops.reduce(max);
      if (maxDrop <= 1e-5) return null;

      final overlay = img.Image(
        width: imageSize,
        height: imageSize,
        numChannels: 4,
      );
      for (int y = 0; y < imageSize; y++) {
        for (int x = 0; x < imageSize; x++) {
          final drop = drops[(y ~/ patchSize) * gridSize + (x ~/ patchSize)];
          final alpha = (180 * drop / maxDrop).round().clamp(0, 180);
          overlay.setPixelRgba(x, y, 239, 68, 68, alpha);
        }
      }

      final displayOverlay = img.copyResize(
        overlay,
        width: decoded.width,
        height: decoded.height,
      );
      return Uint8List.fromList(img.encodePng(displayOverlay));
    } finally {
      interpreter.close();
    }
  }
}
