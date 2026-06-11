import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectedImageState {
  const SelectedImageState({this.file});

  final File? file;

  bool get hasImage => file != null;
}

class ImageNotifier extends Notifier<SelectedImageState> {
  @override
  SelectedImageState build() {
    return const SelectedImageState();
  }

  void setImage(File image) {
    state = SelectedImageState(file: image);
  }

  void clearImage() {
    state = const SelectedImageState();
  }
}

final imageProvider = NotifierProvider<ImageNotifier, SelectedImageState>(
  ImageNotifier.new,
);
