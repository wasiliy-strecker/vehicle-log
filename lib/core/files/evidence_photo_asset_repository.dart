import 'package:universal_io/io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'jpeg_photo_processor.dart';

typedef EvidencePhotoCacheDirectoryProvider = Future<Directory> Function();

abstract interface class EvidencePhotoAssetRepository {
  Future<String?> prepare({required String path, required String sha256});
  Future<void> delete(String sha256);
}

class NoopEvidencePhotoAssetRepository implements EvidencePhotoAssetRepository {
  const NoopEvidencePhotoAssetRepository();

  @override
  Future<String?> prepare({
    required String path,
    required String sha256,
  }) async {
    return path;
  }

  @override
  Future<void> delete(String sha256) async {}
}

class LocalEvidencePhotoAssetRepository
    implements EvidencePhotoAssetRepository {
  LocalEvidencePhotoAssetRepository({
    EvidencePhotoCacheDirectoryProvider? cacheDirectoryProvider,
    NativeJpegCompressor? nativeCompressor,
  }) : _nativeCompressor = nativeCompressor,
       _cacheDirectoryProvider =
           cacheDirectoryProvider ?? _defaultCacheDirectory;

  static const maxDimension = 1600;
  static const jpegQuality = 82;
  static const _cacheVersion = 'pdf_v2_1600_q82';

  final EvidencePhotoCacheDirectoryProvider _cacheDirectoryProvider;
  final NativeJpegCompressor? _nativeCompressor;
  final Map<String, Future<String?>> _inFlight = {};

  @override
  Future<String?> prepare({required String path, required String sha256}) {
    return _inFlight.putIfAbsent(sha256, () async {
      try {
        return await _prepare(path: path, sha256: sha256);
      } finally {
        _inFlight.remove(sha256);
      }
    });
  }

  Future<String?> _prepare({
    required String path,
    required String sha256,
  }) async {
    final source = File(path);
    if (!await source.exists()) return null;

    final directory = await _cacheDirectoryProvider();
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, _fileName(sha256)));
    if (await _isUsable(target)) return target.path;

    final staging = File('${target.path}.preparing.jpg');
    if (await staging.exists()) await staging.delete();

    var prepared = false;
    if (_nativeCompressor != null ||
        (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
      try {
        final compressed = await (_nativeCompressor ?? compressNativeJpeg)(
          sourcePath: source.path,
          targetPath: staging.path,
          maxDimension: maxDimension,
          quality: jpegQuality,
        );
        prepared =
            compressed &&
            await normalizePhoto(
              sourcePath: staging.path,
              targetPath: staging.path,
              maxDimension: maxDimension,
              quality: jpegQuality,
              nativeJpeg: true,
            );
      } on Object {
        prepared = false;
      }
    }
    if (!prepared) {
      prepared = await normalizePhoto(
        sourcePath: source.path,
        targetPath: staging.path,
        maxDimension: maxDimension,
        quality: jpegQuality,
      );
    }

    if (!prepared || !await _isUsable(staging)) {
      if (await staging.exists()) await staging.delete();
      return null;
    }
    if (await target.exists()) await target.delete();
    await staging.rename(target.path);
    return target.path;
  }

  @override
  Future<void> delete(String sha256) async {
    final directory = await _cacheDirectoryProvider();
    final target = File(p.join(directory.path, _fileName(sha256)));
    final staging = File('${target.path}.preparing.jpg');
    if (await target.exists()) await target.delete();
    if (await staging.exists()) await staging.delete();
  }

  static Future<Directory> _defaultCacheDirectory() async {
    Directory root;
    try {
      root = await getTemporaryDirectory();
    } on MissingPluginException {
      root = Directory.systemTemp;
    }
    return Directory(p.join(root.path, 'evidence_photo_assets'));
  }

  static Future<bool> _isUsable(File file) async {
    return await file.exists() && await file.length() > 0;
  }

  static String _fileName(String sha256) {
    final safeHash = sha256.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    return '${_cacheVersion}_${safeHash.isEmpty ? 'unknown' : safeHash}.jpg';
  }
}
