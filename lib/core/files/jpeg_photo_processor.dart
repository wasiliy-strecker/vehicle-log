import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:universal_io/io.dart';

typedef NativeJpegCompressor =
    Future<bool> Function({
      required String sourcePath,
      required String targetPath,
      required int maxDimension,
      required int quality,
    });

Future<bool> compressNativeJpeg({
  required String sourcePath,
  required String targetPath,
  required int maxDimension,
  required int quality,
}) async {
  return await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        autoCorrectionAngle: true,
        format: CompressFormat.jpeg,
        keepExif: false,
      ) !=
      null;
}

Future<bool> normalizePhoto({
  required String sourcePath,
  required String targetPath,
  required int maxDimension,
  required int quality,
  bool nativeJpeg = false,
}) async {
  try {
    return await compute(_normalizePhoto, <String, Object>{
      'source': sourcePath,
      'target': targetPath,
      'maxDimension': maxDimension,
      'quality': quality,
      'nativeJpeg': nativeJpeg,
    }, debugLabel: 'bounded-jpeg-photo');
  } on Object {
    return false;
  }
}

Future<bool> _normalizePhoto(Map<String, Object> input) async {
  final source = File(input['source']! as String);
  final target = File(input['target']! as String);
  final bytes = await source.readAsBytes();
  final maximum = input['maxDimension']! as int;
  if (input['nativeJpeg'] == true) {
    final info = img.JpegDecoder().startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return false;
    // The native compressor already removes EXIF and applies orientation.
    // Avoid a second lossy encoding when it meets the actual size limit.
    if (info.width <= maximum && info.height <= maximum) return true;
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return false;
  var normalized = img.bakeOrientation(decoded);
  if (normalized.width > maximum || normalized.height > maximum) {
    normalized = normalized.width >= normalized.height
        ? img.copyResize(
            normalized,
            width: maximum,
            interpolation: img.Interpolation.linear,
          )
        : img.copyResize(
            normalized,
            height: maximum,
            interpolation: img.Interpolation.linear,
          );
  }
  normalized.exif.clear();
  normalized.iccProfile = null;
  await target.writeAsBytes(
    img.encodeJpg(normalized, quality: input['quality']! as int),
    flush: true,
  );
  return true;
}
