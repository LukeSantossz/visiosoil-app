import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      debugPrint('Imagem selecionada: ${image.path}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Captura de Imagens')),
      body: Center(
        child: ElevatedButton(
          onPressed: _pickImage,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera, size: 50.0),
              const SizedBox(height: 16.0),
              const Text('Capture aqui!'),
            ],
          ),
        ),
      ),
    );
  }
}
