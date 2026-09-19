# Fahrzeugakte

Eigenständige Flutter-App auf Grundlage von Pflanzenbuch, Commit
`0fa2f85d26047f1f22ef6fae17cf93d000ca66e3`. Feature-first Clean MVVM und Riverpod.
Keine gemeinsame Runtime-Abhängigkeit auf Nachbar-Apps.

Interne Meter-/Reading-Namen für den Quellabgleich beibehalten. Fahrzeugfelder,
PDF-Dokumente und der Android-Scanner sind autorisierte fachliche Erweiterungen.
Den Dokumentscanner aus AI Contract Manager app-lokal übernehmen. Keine Cloud,
Konten, Analytics oder automatische Rechnungsanalyse ergänzen.

Auf ausdrücklichen Nutzerwunsch vom 19.09.2026 gibt es keinen sichtbaren
Korrekturverlauf und keine neuen Revisionen oder historischen Anhangsversionen.
Bearbeiten speichert nur den aktuellen Stand. Bereits gespeicherte Altdaten
und Dateien bestehender Revisionen bleiben erhalten und backupfähig. Nicht
mehr referenzierte entfernte Anhänge erst nach erfolgreichem Speichern
bereinigen. Abbruch und Speicherfehler dürfen alte Dateien nicht löschen.
Quellhashes nicht überschreiben. Abweichungen in docs/PROCESSING_PARITY.md und
Paritätsausnahmen dokumentieren und testen.

Vor Code-Commits dart format lib test, flutter analyze und flutter test ausführen.
Codegen nur nach Änderungen an Generator-Eingaben. Pro Aufgabe einen Changelog
unter CODEX/changelog/YYYY/MM/DD anlegen und lokal committen. Nicht pushen.
Keine privaten Dokumente, Schlüssel oder Zugangsdaten einchecken.
Keine Semikolons in Nutzertexten. Store-Texte als Klartext ohne Listenzeichen.

Dev: com.appfactory.vehicle_log.dev, Label Fahrzeugakte Dev.
Store: com.appfactory.vehicle_log, Label Fahrzeugakte. Store-Debug/Profile sind
abgeschaltet. Keine Signierschlüssel anderer Apps übernehmen.
Lokale Runs verwenden --flavor dev. Android-Updates datenbewahrend mit adb
install -r -t -g --no-streaming. Kein flutter install, keine Deinstallation und
keine Datenlöschung. Vor Installation Zielpaket und vorhandene Installation prüfen.
Browser bevorzugt Port 53545. Fremde laufende Sitzungen nicht beenden.
