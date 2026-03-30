import "dart:io";
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ImageNotifier extends Notifier<File?> {
  @override
  File? build() {
    return null;
  }

  void setImage(File image) {
    state = image;
  }

  void clearImage() {
    state = null;
  }
}

final imageProvider = NotifierProvider<ImageNotifier, File?>(
  ImageNotifier.new,
);