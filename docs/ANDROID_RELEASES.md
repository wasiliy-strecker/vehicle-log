# Android-Varianten und Play-Releases

Dev: `com.appfactory.vehicle_log.dev`, sichtbar als Fahrzeugakte Dev.
Store: `com.appfactory.vehicle_log`, sichtbar als Fahrzeugakte.
Store wird nur als Release gebaut. Debug und Profile sind deaktiviert.

## Signierung und erster Release

Es ist noch kein Store-Release erstellt oder veröffentlicht. Die Startversion
lautet `1.0.0+1`. Es wurden keine privaten Signierschlüssel aus anderen Apps
übernommen. Ein eigener Upload-Schlüssel muss vor dem ersten Store-Build
außerhalb des Checkouts eingerichtet und gesichert werden.
`android/key.properties.example` beschreibt die ignorierte lokale
Konfiguration. Release-Builds ohne Signierkonfiguration werden abgewiesen.

Bei einem ausdrücklich beauftragten neuen Release den bekannten Play-Stand
prüfen und den Versionscode erhöhen. Normale Dev-Arbeit erhöht ihn nicht.

```bash
dart format lib test
flutter analyze
TZ=Europe/Berlin flutter test --dart-define=PDF_TEXT_AUDIT=true --concurrency=1
./scripts/build_internal_test_aab.sh
```

Der Helfer prüft Store-Paketkennung, Variante und Version. Die benannte Datei
liegt unter `build/releases/internal-test/`. Vorhandene Lieferungen werden
nicht überschrieben. Die AAB mit `bundletool validate` und `jarsigner -verify`
prüfen. Manifest, Paket, Version, Label, Debug-Flag, deaktivierte Systembackups
und tatsächliche Berechtigungen der eingebundenen Plugins kontrollieren.

Interne Play-Tests und Produktion verwenden dieselbe signierte Store-Variante.
Datei, kurzen deutschen Release-Titel und kopierbare Klartext-Notizen übergeben.
Upload und Veröffentlichung erfordern einen eigenen Auftrag. Die Dev-App und
ihre Daten bleiben bei einem Store-Release bestehen.

## Installationen

Dev-Updates mit `adb install -r -t -g --no-streaming` durchführen. Vorher das
konkrete Zielpaket, installierte Version, Debug-Flag, Installer und bei Bedarf
das Zertifikat prüfen. Kein `flutter install`, keine Deinstallation und keine
Datenlöschung. Eine neue Paketkennung besitzt getrennte Daten und kopiert keine
Daten anderer Apps.
