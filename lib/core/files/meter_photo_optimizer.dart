import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

import 'jpeg_photo_processor.dart';

class MeterPhotoOptimizer {
  const MeterPhotoOptimizer({NativeJpegCompressor? nativeCompressor})
    : _nativeCompressor = nativeCompressor;

  final NativeJpegCompressor? _nativeCompressor;

  static const maxDimension = 1920;
  static const jpegQuality = 88;

  Future<bool> optimize({
    required String sourcePath,
    required String targetPath,
  }) async {
    final target = File(targetPath);
    if (await target.exists()) await target.delete();

    if (_nativeCompressor != null ||
        (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
      try {
        final compressed = await (_nativeCompressor ?? compressNativeJpeg)(
          sourcePath: sourcePath,
          targetPath: targetPath,
          maxDimension: maxDimension,
          quality: jpegQuality,
        );
        if (compressed &&
            await normalizePhoto(
              sourcePath: targetPath,
              targetPath: targetPath,
              maxDimension: maxDimension,
              quality: jpegQuality,
              nativeJpeg: true,
            )) {
          return true;
        }
      } on Object {
        // The Dart fallback can still handle a failed native codec.
      }
    }
    return normalizePhoto(
      sourcePath: sourcePath,
      targetPath: targetPath,
      maxDimension: maxDimension,
      quality: jpegQuality,
    );
  }
}
