import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/disease_result.dart';
import '../services/severity_explanation_service.dart';
import 'image_card.dart';

class SeverityExplanationView extends StatefulWidget {
  final ProcessedImageData imageData;

  const SeverityExplanationView({super.key, required this.imageData});

  @override
  State<SeverityExplanationView> createState() =>
      _SeverityExplanationViewState();
}

class _SeverityExplanationViewState extends State<SeverityExplanationView> {
  Uint8List? _overlay;
  String? _message;
  bool _loading = false;

  Future<void> _explain() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final overlay =
          await SeverityExplanationService.explain(widget.imageData);
      if (!mounted) return;
      setState(() {
        _overlay = overlay;
        _message = overlay == null
            ? 'No region increased the model’s severity score in this check.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _overlay = null;
        _message = 'Could not create the explanation: $error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Why this severity score?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Reveal image regions that raised the model’s severity score. '
              'This is an occlusion explanation, separate from the lesion mask.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _explain,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.visibility_outlined),
              label:
                  Text(_loading ? 'Analyzing regions...' : 'Explain severity'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!),
            ],
            if (_overlay != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 260,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageDisplayCard(
                        imageData: widget.imageData,
                        height: 260,
                      ),
                      Image.memory(_overlay!, fit: BoxFit.cover),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Stronger red means hiding that region reduced the severity score more.'),
            ],
          ],
        ),
      ),
    );
  }
}
