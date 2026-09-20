import 'dart:async';
import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Flutter's test worker does not forward PDFium's hook assets to its worker.
  if (Platform.isLinux) {
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/linux/libpdfium.so',
    ).absolute.path;
  }
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  await testMain();
}
