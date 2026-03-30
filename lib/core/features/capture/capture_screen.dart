import "dart:io";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visiosoil_app/providers/image_provider.dart';

class CaptureScreen extends ConsumerWidget {
  const CaptureScreen({super.key});

  Future<void> _pickFromCamera(WidgetRef ref) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      debugPrint('Imagem selecionada: ${image.path}');
      ref.read(imageProvider.notifier).setImage(File(image.path));
    }
  }

Future<void> _pickFromGallery(WidgetRef ref) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery); 
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
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () => _pickFromCamera(ref),
              icon: const Icon(Icons.camera),
              label: const Text('Capturar'),
            ),
            ElevatedButton.icon(
              onPressed: () => _pickFromGallery(ref),
              icon: const Icon(Icons.photo),
              label: const Text('Galeria'),  
            ),
          ],
        );
      } else {
        return Column(
          children: [
            Image.file(image),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickFromCamera(ref),
                  icon: const Icon(Icons.camera),
                  label: const Text('Capturar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickFromGallery(ref),
                  icon: const Icon(Icons.photo),
                  label: const Text('Galeria'),  
                ),
              ],
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
