# Tomato Guard: LADA & Motion Capture Architecture

This document details the architecture, models, and files responsible for the **Motion Capture (Live Leaf Detection)** and **LADA (Linear Augmentation & Dynamic Attention)** enhancement pipelines in the Tomato Guard application.

---

## 1. Motion Capture Pipeline (Live Detection & Quality Analysis)

The motion capture system ensures that the user takes a high-quality, perfectly framed picture of a tomato leaf before the main classification pipeline runs. It operates in real-time on the live camera feed.

### Core Files & Models:

#### 1. `assets/models/tomato_leaf.tflite`
- **What it is:** A lightweight, high-speed TensorFlow Lite object detection model.
- **What it does:** Runs continuously on the live camera feed (at 320x320 resolution) to detect the presence of a tomato leaf. It outputs bounding box coordinates to track the leaf's motion on the screen.

#### 2. `lib/services/leaf_detector.dart`
- **What it is:** The Dart service wrapper for the `tomato_leaf.tflite` model.
- **What it does:** 
  - Directly processes live YUV420 camera frames using a highly optimized Dart `Isolate` (background thread) to prevent UI stuttering.
  - Applies a strict **80% confidence threshold** (recently increased for higher accuracy) to filter out background noise.
  - Returns the bounding box (`Rect`) of the detected leaf.

#### 3. `lib/services/quality_analyzer.dart`
- **What it is:** A real-time image quality assessment engine.
- **What it does:** 
  - Analyzes the pixels inside the leaf's bounding box.
  - Computes the **Laplacian Variance** to check for blurriness (motion blur or out-of-focus).
  - Computes **Luminance** to check if the image is too dark or washed out by harsh glare.
  - Provides instant feedback (e.g., "Hold Steady", "Move Closer", "Good Lighting") before allowing a capture.

#### 4. `lib/screens/guided_capture_screen.dart` (The UI)
- **What it is:** The `LADA-Capture` camera interface.
- **What it does:** 
  - Ties `LeafDetector` and `QualityAnalyzer` together.
  - Draws the dynamic targeting box (Green for good quality, Red for poor quality/no leaf).
  - Handles the auto-capture countdown when quality metrics are perfect.

---

## 2. LADA Pipeline (Linear Augmentation & Dynamic Attention)

Once a photo is captured, the LADA module enhances the image to dramatically improve the accuracy of disease classification and lesion segmentation. It operates without needing an intermediate AI model, using pure mathematical channel transformations.

### Core Files:

#### 1. `lib/services/lada_module.dart`
- **What it is:** The core image processing engine implementing the LADA algorithm.
- **What it does:**
  - **CIE-L*a*b* Color Space Processing:** Amplifies the a* channel (Green vs. Red/Brown) to make necrotic lesions pop out, and separates the b* channel (Blue vs. Yellow) to highlight chlorotic halos.
  - **Adaptive Luminance Equalization (CLAHE):** Equalizes the L* channel to remove harsh sun glares and deep shadows.
  - **Excess Green Index (ExG):** Mathematically isolates healthy plant tissue from non-plant backgrounds (`2G - R - B`).
  - Merges these enhanced channels back into a standard RGB image that the classification and segmentation models can read much more clearly.

#### 2. `lib/screens/image_choice_screen.dart`
- **What it is:** The photo preview and processing screen.
- **What it does:** 
  - Allows the user to choose between **"Standard Diagnosis"** (raw image) or **"Enhance with LADA"** (processed image).
  - Displays the corresponding loading states (`Classifying` vs `LADA Enhancement`).

#### 3. `lib/screens/segmentation_screen.dart` & `lib/screens/classification_screen.dart`
- **What they do:** 
  - Consume the LADA-enhanced image. 
  - Display the `LADA SLA Enhanced Pipeline Active` badge in the UI if the image was processed by the LADA module.

---

### Summary Workflow
1. User taps **LADA-Capture**.
2. **`leaf_detector.dart`** runs `tomato_leaf.tflite` to find the leaf bounding box.
3. **`quality_analyzer.dart`** checks if the bounding box is in focus and well-lit.
4. User captures the photo and chooses **Enhance with LADA**.
5. **`lada_module.dart`** mathematically transforms the colors to highlight lesions and suppress shadows.
6. The enhanced image is passed to `classification.tflite` (YOLOv8) and `alas_net_NO_SLA.tflite` (Lesion Segmentation) for ultra-accurate diagnosis.
