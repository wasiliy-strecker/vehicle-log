import 'package:universal_io/io.dart';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../integrity/integrity_service.dart';
import '../utils/id_generator.dart';
import '../../features/meters/domain/meter_reading.dart';
import 'meter_photo_optimizer.dart';
import 'meter_photo_repository.dart';

typedef MeterPhotoDocumentsDirectoryProvider = Future<Directory> Function();
typedef MeterPhotoPicker = Future<XFile?> Function(ReadingSource source);

class DeviceMeterPhotoCaptureRepository implements MultiPhotoCaptureRepository {
  DeviceMeterPhotoCaptureRepository({
    ImagePicker? picker,
    IntegrityService integrity = const IntegrityService(),
    MeterPhotoOptimizer optimizer = const MeterPhotoOptimizer(),
    MeterPhotoDocumentsDirectoryProvider? documentsDirectoryProvider,
    MeterPhotoPicker? photoPicker,
    Future<List<XFile>> Function()? multiPhotoPicker,
    Future<LostDataResponse> Function()? lostDataPicker,
  }) : _picker = picker ?? ImagePicker(),
       _integrity = integrity,
       _optimizer = optimizer,
       _photoPicker = photoPicker,
       _multiPhotoPicker = multiPhotoPicker,
       _lostDataPicker = lostDataPicker,
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final ImagePicker _picker;
  final IntegrityService _integrity;
  final MeterPhotoOptimizer _optimizer;
  final MeterPhotoDocumentsDirectoryProvider _documentsDirectoryProvider;
  final MeterPhotoPicker? _photoPicker;
  final Future<List<XFile>> Function()? _multiPhotoPicker;
  final Future<LostDataResponse> Function()? _lostDataPicker;

  @override
  Future<StoredMeterPhoto?> capture(ReadingSource source) async {
    if (source == ReadingSource.manual) {
      throw ArgumentError(
        'Eine manuelle Erfassung verwendet keinen Fotozugriff.',
      );
    }
    final picked = await (_photoPicker != null
        ? _photoPicker(source)
        : _picker.pickImage(
            source: source == ReadingSource.camera
                ? ImageSource.camera
                : ImageSource.gallery,
            requestFullMetadata: false,
          ));
    if (picked == null) {
      return null;
    }
    return _persist(picked, source: source, capturedAt: DateTime.now());
  }

  @override
  Future<StoredMeterPhoto?> recoverLostCapture() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty || response.files == null || response.files!.isEmpty) {
      return null;
    }
    return _persist(
      response.files!.first,
      source: ReadingSource.camera,
      capturedAt: DateTime.now(),
    );
  }

  @override
  Future<PhotoImportResult> pickGalleryPhotos({
    PhotoImportProgress? onProgress,
  }) async {
    final files =
        await (_multiPhotoPicker?.call() ??
            _picker.pickMultiImage(requestFullMetadata: false));
    return _persistAll(files, ReadingSource.gallery, onProgress);
  }

  @override
  Future<PhotoImportResult> recoverPhotos({
    required ReadingSource source,
    PhotoImportProgress? onProgress,
  }) async {
    final response =
        await (_lostDataPicker?.call() ?? _picker.retrieveLostData());
    if (response.exception != null) throw response.exception!;
    return _persistAll(response.files ?? [], source, onProgress);
  }

  Future<PhotoImportResult> _persistAll(
    List<XFile> files,
    ReadingSource source,
    PhotoImportProgress? onProgress,
  ) async {
    final photos = <StoredMeterPhoto>[];
    final failures = <String>[];
    onProgress?.call(0, files.length);
    for (final (index, file) in files.indexed) {
      try {
        photos.add(
          await _persist(file, source: source, capturedAt: DateTime.now()),
        );
      } on Object {
        failures.add(file.name);
      }
      onProgress?.call(index + 1, files.length);
    }
    return PhotoImportResult(photos: photos, failures: failures);
  }

  Future<StoredMeterPhoto> _persist(
    XFile picked, {
    required ReadingSource source,
    required DateTime capturedAt,
  }) async {
    final documents = await _documentsDirectoryProvider();
    final directory = Directory(p.join(documents.path, 'meter_photos'));
    await directory.create(recursive: true);
    final id = newLocalId('photo');
    final optimizedFile = File(p.join(directory.path, '$id.jpg'));
    final staging = File(p.join(directory.path, '$id.preparing.jpg'));
    try {
      final optimized = await _optimizer.optimize(
        sourcePath: picked.path,
        targetPath: staging.path,
      );
      late final File file;
      if (optimized) {
        file = await staging.rename(optimizedFile.path);
      } else {
        if (await staging.exists()) await staging.delete();
        throw const MeterPhotoProcessingException();
      }
      final bytes = await file.readAsBytes();
      return StoredMeterPhoto(
        path: file.path,
        sha256: await _integrity.sha256Bytes(bytes),
        source: source,
        capturedAt: capturedAt,
      );
    } on Object {
      for (final file in [staging, optimizedFile]) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class MeterPhotoProcessingException implements Exception {
  const MeterPhotoProcessingException();

  @override
  String toString() =>
      'Das Foto konnte nicht sicher optimiert werden. Bitte wähle es erneut aus.';
}
