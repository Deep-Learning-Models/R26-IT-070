import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/disease_result.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_button.dart';
import 'history_screen.dart';
import 'guided_capture_screen.dart';
import 'image_choice_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      XFile? image;
      if (source == ImageSource.camera) {
        image = await Navigator.push<XFile?>(
          context,
          MaterialPageRoute(builder: (_) => const GuidedCaptureScreen()),
        );
      } else {
        image = await _picker.pickImage(
          source: source,
          imageQuality: 90,
        );
      }

      if (image != null && mounted) {
        final processedData = ProcessedImageData(
          originalFile: File(image.path),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageChoiceScreen(imageData: processedData),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: AppTheme.severitySevere,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softBackground,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.eco, color: Colors.white, size: 26),
            SizedBox(width: 10),
            Text('Tomato Guard'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined, size: 26),
            tooltip: 'Detection History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // Hero Card Banner
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1B5E20),
                        Color(0xFF2E7D32),
                        Color(0xFF43A047),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.eco,
                          color: Colors.white,
                          size: 52,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Tomato Plant Disease Detection',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Powered by EfficientNet-B2 & TFLite Segmentation Engine',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.9),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Features overview pill list
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildFeatureBadge(Icons.pie_chart_outline, 'Segmentation & Severity'),
                    const SizedBox(width: 8),
                    _buildFeatureBadge(Icons.analytics_outlined, 'AI Diagnosis'),
                    const SizedBox(width: 8),
                    _buildFeatureBadge(Icons.medication_outlined, 'Treatments'),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Primary Action Buttons
              Column(
                children: [
                  PrimaryButton(
                    label: 'LADA-Capture',
                    icon: Icons.camera_alt_outlined,
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                  const SizedBox(height: 14),
                  SecondaryButton(
                    label: 'Upload from Gallery',
                    icon: Icons.photo_library_outlined,
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentMint.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryDark, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
