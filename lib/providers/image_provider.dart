import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class SelectedImageState {
  const SelectedImageState({this.file, this.source});

  final File? file;
  final ImageSource? source;

  bool get hasImage => file != null;
}

class ImageNotifier extends Notifier<SelectedImageState> {
  @override
  SelectedImageState build() {
    return const SelectedImageState();
  }

  void setImage(File image, ImageSource source) {
    state = SelectedImageState(file: image, source: source);
  }

  void clearImage() {
    state = const SelectedImageState();
  }
}

final imageProvider = NotifierProvider<ImageNotifier, SelectedImageState>(
  ImageNotifier.new,
);
