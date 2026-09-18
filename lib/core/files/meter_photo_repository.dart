import '../../features/meters/domain/meter_reading.dart';

class StoredMeterPhoto {
  const StoredMeterPhoto({
    required this.path,
    required this.sha256,
    required this.source,
    required this.capturedAt,
  });

  final String path;
  final String sha256;
  final ReadingSource source;
  final DateTime capturedAt;
}

abstract interface class MeterPhotoCaptureRepository {
  Future<StoredMeterPhoto?> capture(ReadingSource source);
  Future<StoredMeterPhoto?> recoverLostCapture();
  Future<void> delete(String path);
}

class UnsupportedMeterPhotoCaptureRepository
    implements MeterPhotoCaptureRepository {
  const UnsupportedMeterPhotoCaptureRepository();

  @override
  Future<StoredMeterPhoto?> capture(ReadingSource source) async => null;

  @override
  Future<void> delete(String path) async {}

  @override
  Future<StoredMeterPhoto?> recoverLostCapture() async => null;
}

class PhotoImportResult {
  const PhotoImportResult({this.photos = const [], this.failures = const []});
  final List<StoredMeterPhoto> photos;
  final List<String> failures;
}

typedef PhotoImportProgress = void Function(int completed, int total);

abstract interface class MultiPhotoCaptureRepository
    implements MeterPhotoCaptureRepository {
  Future<PhotoImportResult> pickGalleryPhotos({
    PhotoImportProgress? onProgress,
  });
  Future<PhotoImportResult> recoverPhotos({
    required ReadingSource source,
    PhotoImportProgress? onProgress,
  });
}

extension MultiplePhotoCapture on MeterPhotoCaptureRepository {
  Future<PhotoImportResult> pickGalleryPhotos({
    PhotoImportProgress? onProgress,
  }) async {
    final repository = this;
    if (repository is MultiPhotoCaptureRepository) {
      return repository.pickGalleryPhotos(onProgress: onProgress);
    }
    final photo = await capture(ReadingSource.gallery);
    return PhotoImportResult(photos: [?photo]);
  }

  Future<PhotoImportResult> recoverPhotos({
    required ReadingSource source,
    PhotoImportProgress? onProgress,
  }) async {
    final repository = this;
    if (repository is MultiPhotoCaptureRepository) {
      return repository.recoverPhotos(source: source, onProgress: onProgress);
    }
    final photo = await recoverLostCapture();
    return PhotoImportResult(photos: [?photo]);
  }
}
