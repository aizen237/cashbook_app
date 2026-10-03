import 'dart:io';
import 'package:flutter/material.dart';

class ReceiptViewerDialog extends StatelessWidget {
  final String imagePath;

  const ReceiptViewerDialog({super.key, required this.imagePath});

  static void show(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (_) => ReceiptViewerDialog(imagePath: imagePath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    final exists = file.existsSync();

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Receipt / Screenshot'),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: Center(
          child: exists
              ? InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                  ),
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Receipt image not found on device',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
