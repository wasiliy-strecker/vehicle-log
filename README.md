# Fahrzeugakte

Einträge werden über „Bearbeiten“ und „Änderungen speichern“ geändert.
Es gibt keinen Korrekturverlauf und keine neuen historischen Versionen.
Vorhandene Altdaten bleiben für kompatible Backups erhalten.

Eigenständige Flutter-App für Wartungen, Reparaturen, HU/AU und die Geschichte
eines Fahrzeugs. Grundlage ist Mein Pflanzenbuch / PflanzenLog, Commit
`0fa2f85d26047f1f22ef6fae17cf93d000ca66e3`. Navigation, Fotoverwaltung,
Bearbeitung, lokale Erinnerungen, PDF-Protokolle und verschlüsselte Backups
folgen dieser Vorlage. Stahlblau und Anthrazit geben der App eine eigene Optik.

## Fahrzeuge und Einträge

Fahrzeuge haben einen Namen, eine Fahrzeugart und eine Einheit, standardmäßig
km. Kennzeichen, Marke/Modell, FIN und Erstzulassung sind optional. Die
Erstzulassung wird im Datumspicker mit Jahresauswahl zuerst gewählt und als
TT.MM.JJJJ angezeigt. Vorhandene Monat-/Jahr-Angaben bleiben unverändert,
bis ein neues Datum gewählt wird. Die Angabe lässt sich im Feld entfernen.
Einträge verlangen eine Aktivität. Wartung, Reparatur, HU/AU und Kilometerstand
werden vorgeschlagen. Eigene Begriffe werden wie in der Vorlage gespeichert
und erneut vorgeschlagen. Kilometerstand, Werkstatt, Kosten in Euro, Notiz,
Fotos und Dokumente sind optional. Kosten werden als ganze Cent gespeichert.
Kilometerstände mit gleicher Einheit lassen sich unabhängig von der Aktivität
vergleichen. Einträge ohne Kilometerstand erhalten keine erfundene Anzeige.

## Fotos und PDFs

Die vorhandenen Kamera-, Galerie- und manuellen Abläufe bleiben erhalten.
„PDF auswählen/scannen“ bietet PDF-Mehrfachauswahl und auf Android den
Dokumentscanner aus AI Contract Manager. Derselbe Google-ML-Kit-Scanner verwendet
Full-Modus, maximal 20 Seiten, JPEG/PDF-Ausgabe und keinen Galerieimport.
Seiten lassen sich im Scanner zuschneiden, drehen und bereinigen. Die fertige
PDF wird zum Eintrag kopiert. Eine automatische Rechnungsanalyse findet nicht
statt. Es gibt keinen AI-Gateway-Aufruf.

Fotos und PDFs können gemeinsam zu einem Eintrag gehören. Original-PDFs werden
unverändert im privaten App-Speicher abgelegt. Passwortgeschützte, beschädigte
und leere PDFs werden abgewiesen. Die Dokumentliste bietet Öffnen, Teilen,
Ersetzen, Entfernen und Sortieren. Neue Änderungen archivieren keine früheren Anhänge.
Ab zwei aktuellen PDFs lassen sich die Zeilen im Erfassungs- und
Bearbeitungsformular wie Fotos länger gedrückt halten und verschieben.
Der Sortierhinweis steht direkt unter der Überschrift. Am Bildschirmrand
scrollt das Formular beim Ziehen automatisch. Die Menüaktionen „Nach vorne“
und „Nach hinten“ bleiben ebenfalls verfügbar.
Beim Verwerfen werden nur neue Entwurfsdateien entfernt.

Vor externen Foto- und Dokumentauswahlen wird das Formular gesichert. Nach
einem Prozessabbruch bleiben bereits importierte Anhänge und Eingaben erhalten.
Ein währenddessen noch nicht abgeschlossener PDF-Scan muss erneut gestartet
werden. Foto-Picker-Wiederherstellung folgt unverändert der Vorlage.

„Kompakt ohne Anhänge“ nennt die Dokumente. „Mit Fotos und PDFs“ enthält
die aktuellen Fotos und direkt nach jedem Eintrag dessen PDFs in gespeicherter
Reihenfolge. Trennseiten ordnen die Originalseiten zu. Text und Seitenformat
bleiben erhalten. Fehlende oder veränderte Anhänge verhindern einen
unvollständigen Export. Bereits erstellte Protokolle bleiben unverändert.

## Daten und Entwicklung

Schema 8 ergänzt Fahrzeugdaten, Werkstatt, Kosten und aktuelle/historische
Dokumente. Backup-Version 6 enthält alle Anhänge. Die eigene Formatkennung
`fahrzeugakte_backup` und Endung `.fzbackup` verhindern das Einlesen fremder
App-Backups. Die App benötigt keine Nachbar-App und kein gemeinsames Paket.
Herkunft und dokumentierte Abweichungen stehen in
[PROCESSING_PARITY.md](docs/PROCESSING_PARITY.md).

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test --concurrency=1
```

Nach Änderungen am Drift-Schema zusätzlich `dart run build_runner build`.
Mit installiertem Poppler lassen sich PDF-Inhalt und Fotoanordnung prüfen:

```bash
TZ=Europe/Berlin flutter test --dart-define=PDF_TEXT_AUDIT=true --concurrency=1 test/features/evidence
```

## Browser und Android

```bash
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=53545
flutter run --flavor dev -d <device-id>
flutter build apk --debug --flavor dev
adb -s <device-id> install -r -t -g --no-streaming build/app/outputs/flutter-apk/app-dev-debug.apk
```

Der Browser ist eine Vorschau mit Daten im Arbeitsspeicher. Neuladen verwirft
diese Daten. Dauerhafte Speicherung, Scannen, PDF-Dateiabläufe und Erinnerungen
werden auf Android geprüft. Der Scanner benötigt Google Play Services und
gegebenenfalls beim ersten Start einen Download seiner Komponenten.

Dev heißt Fahrzeugakte Dev (`com.appfactory.vehicle_log.dev`). Store verwendet
`com.appfactory.vehicle_log`. Store-Debug und Store-Profile sind deaktiviert.
Vor Installationen Zielpaket, Version, Debug-Flag und Installer prüfen.
`flutter install` darf wegen möglicher Datenlöschung nicht verwendet werden.
Normale UI-Änderungen werden per Hot Reload übernommen.

Native Erinnerungstests: im Verzeichnis `android/` mit vollständigem JDK
`./gradlew :app:testDevDebugUnitTest --max-workers=2` ausführen.
Store-Signierung und Veröffentlichung sind noch nicht eingerichtet.
Der spätere Ablauf steht in [ANDROID_RELEASES.md](docs/ANDROID_RELEASES.md).

Quellcode: [Mozilla Public License 2.0](LICENSE).
Herkunft: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Die [Datenschutzerklärung](PRIVACY.md) ist offline in der App verfügbar.
