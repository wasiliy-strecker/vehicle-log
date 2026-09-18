import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fahrzeugakte/core/files/evidence_photo_asset_repository.dart';
import 'package:fahrzeugakte/core/files/meter_photo_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final portrait in [false, true]) {
    test('bounds oversized native JPEG output, portrait=$portrait', () async {
      final temp = await Directory.systemTemp.createTemp('native_bounds_');
      addTearDown(() => temp.delete(recursive: true));
      // Represents a source decoded only by the native codec (e.g. HEIC).
      final source = File('${temp.path}/source.heic');
      await source.writeAsBytes([1, 2, 3]);
      final nativeBytes = img.encodeJpg(
        img.Image(
          width: portrait ? 1200 : 2400,
          height: portrait ? 2400 : 1200,
        ),
      );
      Future<bool> compressor({
        required String sourcePath,
        required String targetPath,
        required int maxDimension,
        required int quality,
      }) async {
        await File(targetPath).writeAsBytes(nativeBytes);
        return true;
      }

      final target = File('${temp.path}/stored.jpg');
      expect(
        await MeterPhotoOptimizer(
          nativeCompressor: compressor,
        ).optimize(sourcePath: source.path, targetPath: target.path),
        isTrue,
      );
      final stored = img.decodeJpg(await target.readAsBytes())!;
      expect(stored.width, portrait ? 960 : 1920);
      expect(stored.height, portrait ? 1920 : 960);
      final assets = LocalEvidencePhotoAssetRepository(
        cacheDirectoryProvider: () async => Directory('${temp.path}/cache'),
        nativeCompressor: compressor,
      );
      final pdfPath = await assets.prepare(path: source.path, sha256: 'a' * 64);
      final pdf = img.decodeJpg(await File(pdfPath!).readAsBytes())!;
      expect(pdf.width, portrait ? 800 : 1600);
      expect(pdf.height, portrait ? 1600 : 800);
      expect(await source.readAsBytes(), [1, 2, 3]);
    });
  }

  test('keeps already bounded native JPEG without a second encoding', () async {
    final temp = await Directory.systemTemp.createTemp('native_small_');
    addTearDown(() => temp.delete(recursive: true));
    final bytes = img.encodeJpg(img.Image(width: 100, height: 50));
    final target = File('${temp.path}/stored.jpg');
    final optimizer = MeterPhotoOptimizer(
      nativeCompressor:
          ({
            required sourcePath,
            required targetPath,
            required maxDimension,
            required quality,
          }) async {
            await File(targetPath).writeAsBytes(bytes);
            return true;
          },
    );
    expect(
      await optimizer.optimize(
        sourcePath: '/source.heic',
        targetPath: target.path,
      ),
      isTrue,
    );
    expect(await target.readAsBytes(), bytes);
  });

  test(
    'failed native compression falls back to oriented, bounded JPEG',
    () async {
      final temp = await Directory.systemTemp.createTemp('native_fallback_');
      addTearDown(() => temp.delete(recursive: true));
      final image = img.Image(width: 2400, height: 1200);
      image.exif.imageIfd.orientation = 6;
      final source = File('${temp.path}/source.jpg');
      final original = img.encodeJpg(image);
      await source.writeAsBytes(original);
      final target = File('${temp.path}/stored.jpg');
      final optimizer = MeterPhotoOptimizer(
        nativeCompressor:
            ({
              required sourcePath,
              required targetPath,
              required maxDimension,
              required quality,
            }) async => throw StateError('Synthetic codec failure'),
      );
      expect(
        await optimizer.optimize(
          sourcePath: source.path,
          targetPath: target.path,
        ),
        isTrue,
      );
      final result = img.decodeJpg(await target.readAsBytes())!;
      expect(result.width, 960);
      expect(result.height, 1920);
      expect(result.exif.isEmpty, isTrue);
      expect(await source.readAsBytes(), original);
    },
  );
}
