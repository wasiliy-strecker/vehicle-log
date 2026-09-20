# Eigene Datenschutzerklärung und Repository-Verweise

Der Datenschutz-Button öffnet auf Nutzerwunsch die eigene öffentliche
Datenschutzerklärung unter vehicle-log/blob/main/PRIVACY.md. Der Quellcode-Link
führt zum Fahrzeugakte-Repository und trägt die Bezeichnung „Quellcode auf
GitHub“. Beide verwenden den bestehenden externen URL-Launcher und zeigen bei
Fehlern eine passende Meldung. Lokaler Textdialog und ungenutztes Datenschutz-
Asset entfallen. Die Darstellung der Datenschutz-Card bleibt erhalten.

PRIVACY.md übernimmt die Abschnittsfolge und Formulierungen von PflanzenLog.
Fahrzeugfelder, Dokumentmetadaten, lokale PDF-Scans mit Google Play Services,
vorhandene ältere Korrekturdaten und externe GitHub-Aufrufe sind berücksichtigt.
README und Paritätsdokumentation angepasst. Nur den lokalen Ausnahmehash
aktualisiert, keine eingefrorenen Quellhashes verändert.

Prüfung: dart format lib test ohne Änderungen, flutter analyze --no-pub ohne
Befunde. 175 Tests aus settings_screen_test.dart, action_layout_test.dart und
test/parity erfolgreich. Die Linktests prüfen die eigenen Zieladressen sowie
false-Rückgaben und Exceptions. git diff --check erfolgreich.
Keine nativen Änderungen, kein APK-Neubau und keine visuellen Smartphone-Tests.
