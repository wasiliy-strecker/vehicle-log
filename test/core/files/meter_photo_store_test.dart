import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:fahrzeugakte/core/files/meter_photo_optimizer.dart';
import 'package:fahrzeugakte/core/files/meter_photo_store.dart';
import 'package:fahrzeugakte/core/integrity/integrity_service.dart';
import 'package:fahrzeugakte/features/meters/domain/meter_reading.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'gallery batch and Android recovery persist every valid file in order',
    () async {
      final temp = await Directory.systemTemp.createTemp('photo_batch_');
      addTearDown(() => temp.delete(recursive: true));
      final first = File('${temp.path}/first.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 20, height: 40)));
      final broken = File('${temp.path}/broken.png')
        ..writeAsBytesSync([0, 1, 2]);
      final last = File('${temp.path}/last.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 40, height: 20)));
      final files = [XFile(first.path), XFile(broken.path), XFile(last.path)];
      final repository = DeviceMeterPhotoCaptureRepository(
        documentsDirectoryProvider: () async => temp,
        multiPhotoPicker: () async => files,
        lostDataPicker: () async =>
            LostDataResponse(files: [files.first, files.last]),
      );
      final progress = <(int, int)>[];
      final batch = await repository.pickGalleryPhotos(
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(batch.photos, hasLength(2));
      expect(batch.failures, ['broken.png']);
      expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
      expect(
        batch.photos.map((p) => p.source),
        everyElement(ReadingSource.gallery),
      );
      final restored = await repository.recoverPhotos(
        source: ReadingSource.gallery,
      );
      expect(restored.photos, hasLength(2));
      expect(
        restored.photos.map((p) => p.source),
        everyElement(ReadingSource.gallery),
      );
      for (final photo in [...batch.photos, ...restored.photos]) {
        expect(await File(photo.path).exists(), true);
        expect(
          await const IntegrityService().sha256Bytes(
            await File(photo.path).readAsBytes(),
          ),
          photo.sha256,
        );
      }
      final savedFiles = Directory('${temp.path}/meter_photos').listSync();
      expect(savedFiles, hasLength(4));
      expect(savedFiles.where((f) => f.path.contains('.preparing.')), isEmpty);
    },
  );

  test('manual source never opens the camera or gallery picker', () async {
    var opened = false;
    final repository = DeviceMeterPhotoCaptureRepository(
      photoPicker: (_) async {
        opened = true;
        return null;
      },
    );
    await expectLater(
      repository.capture(ReadingSource.manual),
      throwsArgumentError,
    );
    expect(opened, isFalse);
  });

  test('new meter photos are normalized before hashing and storage', () async {
    final temp = await Directory.systemTemp.createTemp('meter_photo_store_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}/camera-original.png');
    final originalBytes = img.encodePng(img.Image(width: 2400, height: 1200));
    await source.writeAsBytes(originalBytes);
    final documents = Directory('${temp.path}/documents');
    final repository = DeviceMeterPhotoCaptureRepository(
      photoPicker: (_) async => XFile(source.path),
      documentsDirectoryProvider: () async => documents,
    );

    final stored = await repository.capture(ReadingSource.gallery);
    final storedBytes = await File(stored!.path).readAsBytes();
    final decoded = img.decodeImage(storedBytes);

    expect(stored.path, endsWith('.jpg'));
    expect(decoded, isNotNull);
    expect(decoded!.width, MeterPhotoOptimizer.maxDimension);
    expect(decoded.height, 960);
    expect(
      stored.sha256,
      await const IntegrityService().sha256Bytes(storedBytes),
    );
    expect(await source.readAsBytes(), originalBytes);
  });

  test('small photos are never enlarged', () async {
    final temp = await Directory.systemTemp.createTemp('small_meter_photo_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}/small.jpg');
    await source.writeAsBytes(
      img.encodeJpg(img.Image(width: 800, height: 600), quality: 95),
    );
    final target = File('${temp.path}/optimized.jpg');

    final optimized = await const MeterPhotoOptimizer().optimize(
      sourcePath: source.path,
      targetPath: target.path,
    );
    final decoded = img.decodeImage(await target.readAsBytes());

    expect(optimized, isTrue);
    expect(decoded, isNotNull);
    expect(decoded!.width, 800);
    expect(decoded.height, 600);
  });

  test('optimized photos do not retain EXIF metadata', () async {
    final temp = await Directory.systemTemp.createTemp('photo_metadata_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}/with-metadata.jpg');
    final image = img.Image(width: 800, height: 600)
      ..exif.imageIfd.make = 'Private camera'
      ..exif.imageIfd.imageDescription = 'Private location';
    await source.writeAsBytes(img.encodeJpg(image, quality: 95));
    final target = File('${temp.path}/optimized.jpg');

    final optimized = await const MeterPhotoOptimizer().optimize(
      sourcePath: source.path,
      targetPath: target.path,
    );
    final decoded = img.decodeJpg(await target.readAsBytes());

    expect(optimized, isTrue);
    expect(decoded, isNotNull);
    expect(decoded!.exif.isEmpty, isTrue);
  });

  test('an unoptimizable photo is not stored as a raw fallback', () async {
    final temp = await Directory.systemTemp.createTemp('failed_photo_');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}/source.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);
    final documents = Directory('${temp.path}/documents');
    final repository = DeviceMeterPhotoCaptureRepository(
      optimizer: const _FailingMeterPhotoOptimizer(),
      photoPicker: (_) async => XFile(source.path),
      documentsDirectoryProvider: () async => documents,
    );

    await expectLater(
      repository.capture(ReadingSource.gallery),
      throwsA(isA<MeterPhotoProcessingException>()),
    );
    final storedFiles = await Directory(
      '${documents.path}/meter_photos',
    ).list().toList();
    expect(storedFiles, isEmpty);
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
  });
}

class _FailingMeterPhotoOptimizer extends MeterPhotoOptimizer {
  const _FailingMeterPhotoOptimizer();

  @override
  Future<bool> optimize({
    required String sourcePath,
    required String targetPath,
  }) async => false;
}
