# Bearbeiten ohne Korrekturverlauf

Der Korrekturverlauf mit Vorher-/Nachher-Anhängen, Begründungsfeld und
Protokollierungshinweisen entfällt. Die Oberfläche verwendet jetzt „Bearbeiten“
und „Änderungen speichern“. Die normale Liste der Einträge bleibt erhalten.

Neue Änderungen speichern den aktuellen Stand ohne neue Revisionen und ohne
neue historische Anhangsversionen. Bestehende Revisionen und historische
Dateizuordnungen bleiben mit alten Backups kompatibel. Entfernte Anhänge,
die alte Revisionen weiterhin benötigen, bleiben erhalten. Nur nicht mehr
referenzierte Dateien und Foto-Caches werden nach erfolgreichem Speichern
bereinigt. Speicherfehler und Abbruch löschen keine bisherigen Anhänge.
Ein Bereinigungsfehler meldet keinen bereits gespeicherten Eintrag als fehlgeschlagen.

Fotoauswahl, Ersetzen, Sortieren und Entwurfswiederherstellung bleiben erhalten.
Schema, Backupversion und eingefrorene Referenzhashes sind unverändert.
Dokumentation und app-lokale Paritätsausnahmen beschreiben die neue Vorgabe.

## Prüfung

`dart format lib test` und `flutter analyze --no-pub` erfolgreich.
Die vollständige Testsuite wurde mit `flutter test --no-pub --concurrency=3
--timeout 2m --reporter expanded` ausgeführt. Im parallelen Lauf erreichte
`app_database_migration_test.dart` ein Zeitlimit. Die gesamte betroffene Datei
wurde danach mit `--concurrency=1` einzeln erneut ausgeführt. Alle fünf
Migrationstests bestanden. Alle übrigen Tests der vollständigen Suite bestanden.

Gezielte Tests prüfen insbesondere neue Änderungen ohne Revision, alte ID- und
Hash-Verweise, geteilte Dateipfade, Speicherfehler, Bereinigungsfehler und Abbruch.
Bestehende Backup-, Integritäts-, Foto- und Sortierungsprüfungen sind erhalten.

Die vorhandene Dev-App auf dem verbundenen Android-Gerät wurde per Hot Reload
aktualisiert. Kein APK gebaut, kein Neustart und keine Datenlöschung.
Fahrzeugakte wurde zusätzlich am Gerät über die sichtbaren Bedienelemente
geprüft. „Eintrag bearbeiten“, aktuelle Fotos und aktuelle PDFs sind vorhanden.
Korrekturgrund und Korrekturverlauf sind entfernt. Es wurde nichts gespeichert.
PDF-Dateien werden zusätzlich mit echten temporären Dateien auf Aufbewahrung
alter Referenzen und Bereinigung erst nach erfolgreichem Speichern geprüft.
