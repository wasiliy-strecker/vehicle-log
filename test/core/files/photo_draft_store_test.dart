import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fahrzeugakte/core/files/photo_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'picker target and form snapshot survive a new store instance',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final first = PreferencesPhotoDraftStore(preferences);
      const route = '/reading/example/edit';
      final draft = {
        'pendingSource': 'gallery',
        'replacementId': 'photo2',
        'fields': {'value': '18', 'note': 'Ärmel'},
        'photos': <Object>[],
        'ownedPaths': <String>[],
      };
      await first.write(route, draft);
      final second = PreferencesPhotoDraftStore(preferences);
      expect(await second.pendingRoute(), route);
      expect(await second.read(route), draft);
      await second.remove(route);
      expect(await first.pendingRoute(), null);
    },
  );
  test('broken or invalid pending routes cannot prevent app startup', () async {
    SharedPreferences.setMockInitialValues({
      'project_photo_draft:/reading/broken/edit': '{bad json',
      'project_photo_draft:/reading/array/edit': '[]',
      'project_photo_draft:/unexpected': '{"pendingSource":"camera"}',
    });
    final store = PreferencesPhotoDraftStore(
      await SharedPreferences.getInstance(),
    );
    expect(await store.pendingRoute(), null);
  });
}
