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

  /// Clears the selection only if it still holds [path], so a late clear from a
  /// slow save does not wipe a newer capture selected in the meantime.
  void clearIfPath(String path) {
    if (state.file?.path == path) {
      state = const SelectedImageState();
    }
  }
}

final imageProvider = NotifierProvider<ImageNotifier, SelectedImageState>(
  ImageNotifier.new,
);
