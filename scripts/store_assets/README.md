# Play-Store-Bilder für Fahrzeugakte

Die Werkzeuge übernehmen das Layout der bestehenden Log-Apps, arbeiten aber
vollständig app-lokal. Sie verändern weder die App noch den Release oder das
angeschlossene Smartphone. Aufnahmen sind ausschließlich in einem eigenen
AVD mit dem Namenspräfix `fz_store_assets` erlaubt.

## Quelle und Ergebnis

Vorhandene Store-AAB `fahrzeugakte-1.0.0-build-3-internal-test.aab`, Paket
`com.appfactory.vehicle_log`, Version `1.0.0+3`. `prepare_emulator.sh` prüft
ihren fest hinterlegten SHA-256 und extrahiert eine universelle Release-APK.
bundletool signiert diese lokale Emulator-APK mit seinem Debug-Schlüssel.
Die App ist trotzdem ein nicht debuggbarer Store-Release. Es wird kein
Flutter-Build ausgelöst und keine Installation außerhalb des neuen AVD ausgeführt.

`package.py` prüft Paket, Version, Debug-Flag und die unveränderten App-Assets
und nativen Bibliotheken gegen die AAB. Die von bundletool ergänzten
ART-Optimierungsprofile sind von diesem Dateivergleich ausgenommen.

Zielordner: `build/store-assets/de-DE/build-3/`, von Git ausgeschlossen.
Die 18 Upload-Dateien bestehen aus einem Icon, einer Feature-Grafik, acht
Smartphone-Bildern und jeweils vier Bildern für 7- und 10-Zoll-Tablets.
Das ZIP enthält zusätzlich `VORSCHAU.png`, `README.md` und `manifest.json`.
Die Anleitung ordnet die Dateien den Play-Console-Feldern zu und enthält
deutsche Alt-Texte. Das Manifest dokumentiert Maße, Größen und SHA-256.

## Ablauf

Voraussetzungen: Flutter, JDK 21, Android SDK mit API-35-Google-APIs-x86_64,
bundletool 1.18.3, Python 3, Node 22, Chrome und ImageMagick. Alle Befehle
aus dem App-Verzeichnis ausführen. Die vorhandene Release-AAB erhalten.

```bash
flutter test --no-pub test/tooling/store_demo_backup_test.dart \
  --dart-define=STORE_DEMO_DIR=build/store-assets/de-DE/build-3/raw/demo
bash scripts/store_assets/prepare_emulator.sh \
  build/releases/internal-test/fahrzeugakte-1.0.0-build-3-internal-test.aab \
  /home/unknown/.local/share/app-factory/tools/bundletool-all-1.18.3.jar
```

Der zweite Befehl läuft bis zum Beenden des eigenen Emulators und gibt dessen
Serial sowie Arbeitsverzeichnis aus. Standardport ist 5584. Belegte Ports
werden abgelehnt. `FZ_EMULATOR_PORT`, `FZ_ANDROID_SDK` und `FZ_ADB` sind optional.
Die übrigen Befehle in einem zweiten Terminal ausführen.

Das erzeugte `raw/demo/Demo.fzbackup` auf den eigenen Emulator nach
`/sdcard/Download/` kopieren. Die App starten und in Einstellungen → Backup
wiederherstellen über den Android-Dateidialog importieren. Passwort `Demo2026`.
Das Backup enthält vier erfundene Fahrzeuge, 32 Einträge, fünf generierte Fotos
und zwei als MUSTER gekennzeichnete PDFs. Der Host-Test prüft den verschlüsselten
Roundtrip inklusive Reihenfolge und Dateiintegrität. Die Foto-Prompts liegen
unter `assets/store_demo/prompts.json`. Die Beispielbilder werden nicht mit
der App ausgeliefert.

```bash
python3 scripts/store_assets/capture_storyboard.py emulator-5584 phone build/store-assets/de-DE/build-3
python3 scripts/store_assets/capture_storyboard.py emulator-5584 tablet7 build/store-assets/de-DE/build-3
python3 scripts/store_assets/capture_storyboard.py emulator-5584 tablet10 build/store-assets/de-DE/build-3
node scripts/store_assets/render.mjs assets build/store-assets/de-DE/build-3
node scripts/store_assets/render.mjs contact build/store-assets/de-DE/build-3
python3 scripts/store_assets/package.py build/store-assets/de-DE/build-3 \
  --aab build/releases/internal-test/fahrzeugakte-1.0.0-build-3-internal-test.aab \
  --apk /dev/shm/DEIN-AUSGEGEBENES-ARBEITSVERZEICHNIS/universal.apk
```

Die Serial und den APK-Pfad durch die tatsächlich ausgegebenen Werte ersetzen.
Die Aufnahmehelfer bedienen die echte Oberfläche und erzeugen die PDF-Vorschau
in der App. Telefonaufnahmen werden vollständig und proportional unter einer
Überschrift dargestellt. Tablet-Aufnahmen entstehen separat bei 1920×1080 und
2560×1440 Pixeln. App-Inhalte werden nicht übermalt oder nachgebaut.
Bei geänderten Releases müssen Storyboard, Quellprüfung und UI-Texte geprüft
werden. Die Capture-Skripte sind absichtlich an diesen Release gebunden.

## Prüfung

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --no-pub --concurrency=2
python3 scripts/store_assets/test_tools.py
node --check scripts/store_assets/render.mjs
bash -n scripts/store_assets/prepare_emulator.sh
git diff --check
```

Der Paketierer prüft zusätzlich PNG-Dekodierung, Maße, Farben, Alpha,
Dateigrößen, Alt-Text-Längen und den ZIP-Inhalt. Die Gesamtvorschau und alle
Ansichten vor der Übergabe kontrollieren. Nach Abschluss ausschließlich den
ausgegebenen eigenen Emulator beenden. Upload und Veröffentlichung erfolgen
separat durch den Nutzer.

Die Tablet-PDF-Bilder zeigen den kompakten Export. Ein während der Aufnahmen
beobachteter Speicherabsturz mit Anhängen bei hoher Auflösung ist in
[STORE_CAPTURE_FINDINGS.md](../../docs/STORE_CAPTURE_FINDINGS.md) dokumentiert.
