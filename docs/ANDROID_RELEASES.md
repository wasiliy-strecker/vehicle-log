# Android-Varianten und Play-Releases

Dev: `com.appfactory.vehicle_log.dev`, sichtbar als Fahrzeugakte Dev.
Store: `com.appfactory.vehicle_log`, sichtbar als Fahrzeugakte.
Store wird nur als Release gebaut. Debug und Profile sind deaktiviert.

## Signierung und erster Release

Die nächste interne Testversion lautet `1.0.0+3`. Der eigene Upload-Schlüssel
ist außerhalb des Checkouts unter `~/.local/share/app-factory/signing/fahrzeugakte/`
eingerichtet. Eine geschützte lokale Sicherung liegt unter
`~/backups/fahrzeugakte-signing/`. Die ignorierte Datei `android/key.properties`
verweist auf diesen Schlüssel. Es wurden keine Signierschlüssel anderer Apps
übernommen. Die lokale Sicherung zusätzlich außerhalb dieses Rechners verwahren.

Die fertigen Store-Texte und Hinweise für den manuellen Upload stehen unter
[PLAY_TEST_RELEASE.md](store/PLAY_TEST_RELEASE.md). Die tatsächlichen Nachweise
für Version 1.0.0+3 stehen im
[Abschlussbericht](INTERNAL_RELEASE_1.0.0_3.md).

Die technische PDF-Prüfung vom 20.09.2026 ist in
[PDF_RELEASE_AUDIT.md](PDF_RELEASE_AUDIT.md) dokumentiert. Sie ersetzt keinen
signierten Store-Build und keine Gerätetests des Google-Scanners.

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
