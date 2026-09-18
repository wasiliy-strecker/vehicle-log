import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PhotoDraftStore {
  Future<Map<String, dynamic>?> read(String route);
  Future<void> write(String route, Map<String, dynamic> draft);
  Future<void> remove(String route);
  Future<String?> pendingRoute();
}

class MemoryPhotoDraftStore implements PhotoDraftStore {
  final _drafts = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String route) async => _drafts[route];
  @override
  Future<void> write(String route, Map<String, dynamic> draft) async {
    _drafts[route] = draft;
  }

  @override
  Future<void> remove(String route) async => _drafts.remove(route);
  @override
  Future<String?> pendingRoute() async => _drafts.entries
      .where(
        (entry) =>
            entry.value['pendingSource'] != null ||
            entry.value['pendingDocument'] == true,
      )
      .map((entry) => entry.key)
      .firstOrNull;
}

class PreferencesPhotoDraftStore implements PhotoDraftStore {
  PreferencesPhotoDraftStore(this.preferences);
  final SharedPreferences preferences;
  static const _prefix = 'project_photo_draft:';

  @override
  Future<Map<String, dynamic>?> read(String route) async {
    final raw = preferences.getString('$_prefix$route');
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> write(String route, Map<String, dynamic> draft) async {
    if (!await preferences.setString('$_prefix$route', jsonEncode(draft))) {
      throw StateError('Der Foto-Zwischenstand konnte nicht gesichert werden.');
    }
  }

  @override
  Future<void> remove(String route) async {
    if (!await preferences.remove('$_prefix$route')) {
      throw StateError('Der Foto-Zwischenstand konnte nicht entfernt werden.');
    }
  }

  @override
  Future<String?> pendingRoute() async {
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith(_prefix),
    )) {
      final route = key.substring(_prefix.length);
      if (!RegExp(
        r'^/(meter/[^/]+/capture|reading/[^/]+/edit)$',
      ).hasMatch(route)) {
        continue;
      }
      try {
        final draft = await read(route);
        if (draft?['pendingSource'] == 'camera' ||
            draft?['pendingSource'] == 'gallery' ||
            draft?['pendingDocument'] == true) {
          return route;
        }
      } on Object {
        // A damaged transient draft must not prevent opening the app.
        continue;
      }
    }
    return null;
  }
}
