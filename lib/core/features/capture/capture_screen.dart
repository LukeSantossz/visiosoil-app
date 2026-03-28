import "dart:io";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/providers/image_provider.dart';

class CaptureScreen extends ConsumerWidget {
  const CaptureScreen({super.key});

  Future<void> _pickImage(WidgetRef ref) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      debugPrint('Imagem selecionada: ${image.path}');
      ref.read(imageProvider.notifier).setImage(File(image.path));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(imageProvider);

    Widget buildImage() {
      if (image == null) {
        return ElevatedButton(
          onPressed: () => _pickImage(ref),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera, size: 50.0),
              const SizedBox(height: 16.0),
              const Text('Capture aqui!'),
            ],
          ),
        );
      } else {
        return Column(
          children: [
            Image.file(image),
            ElevatedButton(
              onPressed: () => _pickImage(ref),
              child: const Text('Capturar outra imagem'),
            ),
          ],
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Captura de Imagens')),
      body: Center(child: buildImage()),
    );
  }
}
