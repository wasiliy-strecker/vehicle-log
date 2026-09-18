import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahrzeugakte/features/backup/application/backup_file_picker.dart';

void main() {
  test('Android uses a MIME-compatible filter for existing backups', () {
    expect(
      PlatformBackupFilePicker.allowedExtensionsFor(
        platform: TargetPlatform.android,
        isWeb: false,
      ),
      const ['bin'],
    );
  });

  test('other platforms filter by the actual backup extension', () {
    expect(
      PlatformBackupFilePicker.allowedExtensionsFor(
        platform: TargetPlatform.iOS,
        isWeb: false,
      ),
      const ['fzbackup'],
    );
    expect(
      PlatformBackupFilePicker.allowedExtensionsFor(
        platform: TargetPlatform.android,
        isWeb: true,
      ),
      const ['fzbackup'],
    );
  });

  test('only Fahrzeugakte backup names are accepted', () {
    expect(
      PlatformBackupFilePicker.hasBackupExtension('backup.fzbackup'),
      isTrue,
    );
    expect(
      PlatformBackupFilePicker.hasBackupExtension('BACKUP.FZBACKUP'),
      isTrue,
    );
    expect(
      PlatformBackupFilePicker.hasBackupExtension('backup.aicmbackup'),
      isFalse,
    );
    expect(
      PlatformBackupFilePicker.hasBackupExtension('backup.fzbackup.pdf'),
      isFalse,
    );
  });
}
