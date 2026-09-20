# Interner Play-Test 1.0.0 (3)

Stand: 20.09.2026. Store-Paket `com.appfactory.vehicle_log`.
Die Arbeiten beziehen sich auf Fahrzeugakte. Nachbar-Apps bleiben unverändert.

## Umgesetzte Release-Punkte

Neue PDF-Anhänge dürfen zusammen höchstens 20 Seiten und 50.000.000 Bytes
pro Eintrag belegen. Eine Datei darf höchstens 25.000.000 Bytes haben.
Auswahl, Import, Scanner, Formular und Speicherdienst berücksichtigen das
Restbudget. Ersetzen gibt das Budget des ersetzten Anhangs frei. Die Anzeige
nennt den aktuellen Verbrauch. Importfehler entfernen nur neue Kopien.

Bereits gespeicherte größere Bestände bleiben lesbar und backupfähig.
Bearbeiten, Entfernen und Verkleinern sind möglich. Die Grenzen gelten für
neue Anhänge und verhindern ein weiteres Vergrößern alter Bestände.

Große Fahrzeugprotokolle werden automatisch auf nummerierte Teile verteilt.
Jeder fertige Teil hat höchstens 100 Seiten und 50.000.000 Bytes einschließlich
Deckblatt und Zuordnungsseiten. Es gibt keine Obergrenze für die Anzahl der
Teile. Die Verarbeitung lädt Originaldateien nacheinander und baut begrenzte
Abschnitte. Die Vorschau lädt jeweils einen Teil. Alle erzeugten Teile können
gemeinsam geteilt werden. Gespeicherte Teile lassen sich einzeln erneut öffnen.
Ein nicht exportierbarer Anhang führt zu einer Fehlermeldung und keinem
unvollständig gespeicherten Protokoll.

PDF-Seiten werden übernommen und nicht als Bilder neu gerastert. Automatische
Tests prüfen Reihenfolge und extrahierbaren Text an den Teilgrenzen. Der
Originalanhang bleibt unverändert. Der zusammengesetzte Bericht ist keine
Erhaltung etwaiger kryptografischer Signaturen des Original-PDFs.

Alle Datenbankänderungen einer Android-Backup-Wiederherstellung erfolgen in
einer gemeinsamen Drift-Transaktion. Neue Dateien erhalten eigene Pfade.
Auch Reparaturen überschreiben keine vorhandenen Dateien. Bei Fehlern werden
nur selbst erzeugte, nicht mehr referenzierte Dateien bereinigt. Erinnerungen
werden nach dem Commit abgeglichen und können den Import nicht zurücknehmen.
Das Datenbankschema und das bestehende Backup-Format wurden nicht geändert.

Ein eigener Upload-Schlüssel wurde außerhalb des Repositories erzeugt und
lokal mit restriktiven Dateirechten gesichert. Schlüssel und Zugangsdaten
sind nicht Bestandteil des Commits. Die Datenschutzerklärung erläutert die
technischen ML-Kit-Daten. Die [Store-Texte](store/PLAY_TEST_RELEASE.md) sind
für den manuellen Upload vorbereitet.

## Automatisierte Prüfung

`dart format lib test` und `flutter analyze` sind ohne Befund. Alle 761
Flutter-Tests bestehen im isolierten Gesamtlauf mit `TZ=Europe/Berlin`,
`--dart-define=PDF_TEXT_AUDIT=true` und `--concurrency=1`. Alle 31 nativen
Android-JVM-Tests bestehen, davon 28 Erinnerungstests und drei Scanner-
Lifecycle-Tests. Ein früherer Gesamtlauf mit gleichzeitigem separatem
Flutter-Fixture-Prozess beendete einzelne Testgruppen unvollständig. Der
abschließende isolierte Lauf enthält keine Fehler oder unvollständigen Tests.

Neue Grenzwerttests prüfen 19, 20 und 21 Seiten, die Dateigrenze von 25 MB
und das gemeinsame Budget von 50 MB. Weitere Tests prüfen Restbudget,
Scanner-Seitenlimit, Ersetzen und den Erhalt größerer Altdaten.

Gezielte SQLite-Fehler beim Schreiben von Einträgen und Exporten weisen den
vollständigen Rollback von Import und Reparatur nach. Ein Fehler beim Speichern
des zweiten Exportteils hinterlässt keine Teilgruppe. Mehrteilige Exporte mit
99, 100, 101 und 205 Inhaltsseiten werden auf Seitenzahl, Größe, Reihenfolge
und vollständige Textmarker geprüft. Verschlüsselte Backup-Roundtrips prüfen
unveränderte Teile, Dateinamen und Prüfsummen.

## Artefakt und Android-Laufzeit

Die finale Übergabe ist:
`build/releases/internal-test/fahrzeugakte-1.0.0-build-3-internal-test.aab`.
Größe: 80165868 Bytes.
SHA-256: `6e6d9a61184603a41644ec3cb71f8e847ae164b1051edec730aaea8811a0e830`.

Build 3 wurde mit dem app-lokalen Release-Helfer erstellt. `bundletool validate`,
`jarsigner -verify`, `apksigner verify` und `zipalign -c -P 16 -v 4` bestehen.
Die AAB-Konfiguration enthält `PAGE_ALIGNMENT_16K`. Alle 21 nativen Bibliotheken
sind geprüft. Das Manifest bestätigt `com.appfactory.vehicle_log`, Version
1.0.0 (3), minSdk 24, targetSdk 36, fehlendes Debug-Flag und deaktivierte
Systembackups. Die Berechtigungen entsprechen dem unten beschriebenen Stand.

Auf API 36 wurde das aus dieser finalen AAB erzeugte APK nach Zertifikatsabgleich
datenbewahrend über Build 2 installiert und gestartet. Alle 13 gespeicherten
PDF-Dateien behalten ihre Prüfsummen. Der ungespeicherte Entwurf mit 20 Seiten
wird wiederhergestellt. Eine versuchte Ersetzung durch 40 Seiten wird mit
verständlicher Meldung ohne technische Fehlerklasse abgewiesen. Der bisherige
Anhang bleibt erhalten. Der abschließende App-Log enthält keine unbehandelten
Ausnahmen, nativen Abstürze oder ANRs.

Der vollständig geprüfte Zwischenstand Build 2 bleibt erhalten. Build 3
ändert gegenüber diesem Stand nur die Darstellung von Importfehlern und die
Buildnummer. Die umfangreichen nachfolgenden Laufzeittests wurden mit Build 2
durchgeführt. Der finale Quellstand besteht erneut alle 761 Flutter-Tests.

Der app-lokale Release-Helfer hat für Build 2 diese AAB erzeugt:
`build/releases/internal-test/fahrzeugakte-1.0.0-build-2-internal-test.aab`.
Größe: 80166538 Bytes.
SHA-256: `f0d733f1cc52531553b2622dd384a7ea816253c9feffe830456b45235e87fc9b`.

`bundletool validate` und `jarsigner -verify` bestehen. Ein daraus mit
Bundletool 1.18.3 erzeugtes Universal-APK besteht `apksigner verify` und
`zipalign -c -P 16 -v 4`. Alle 21 nativen Bibliotheken sind erfasst.
Die 64-Bit-Bibliotheken für arm64-v8a und x86_64 haben LOAD-Ausrichtungen von
mindestens 16 KB. armeabi-v7a ist ebenfalls im Paket enthalten.

Das tatsächliche Manifest bestätigt Store-Paket, Label Fahrzeugakte,
Version 1.0.0 (2), minSdk 24, targetSdk 36 und fehlendes Debug-Flag.
Systembackups sind deaktiviert. INTERNET und ACCESS_NETWORK_STATE sind nicht
enthalten. Vorhanden sind Benachrichtigungen, Neustartempfang, exakte Alarme,
Vibration und die app-eigene Receiver-Berechtigung.

Der Zwischenstand Build 2 wurde auf API 24, API 35 mit 16-KB-Seiten und
API 36 installiert und erfolgreich gestartet. Auf API 35 und API 36 wurden
jeweils zwölf Einträge mit 240 angehängten PDF-Seiten und Fotos über die
App-Oberfläche aus einem verschlüsselten Test-Backup wiederhergestellt.

Auf API 24 und im 16-KB-Abbild wurde der vollständige Verlauf exportiert.
Jeweils zwölf Teile mit 22 bis 24 Seiten und maximal 42.966.549 Bytes wurden
erzeugt. `pdfinfo` und `pdftotext` bestätigen sämtliche 240 Originalseiten
in der richtigen Reihenfolge. Vorschau und das erneute Öffnen gespeicherter Teile funktionieren auf API 24
und im 16-KB-Abbild. Im 16-KB-Abbild wurden zusätzlich Teilwechsel und der
Teilen-Dialog mit allen zwölf Dateien geprüft.
Es wurden keine Dateien an einen Empfänger versendet. Die geprüften App-Logs
enthalten keine Flutter-Fehler, unbehandelten Ausnahmen, ANRs oder nativen
Absturzmeldungen.

Die per `dumpsys meminfo` alle zwei Sekunden gemessenen PSS-Spitzen lagen
bei etwa 550,3 MiB im 16-KB-Abbild und 649,2 MiB auf API 24. Das API-24-Gerät
meldet rund 1,5 GB RAM. Das 16-KB-Abbild meldet trotz kleiner angeforderter
AVD-Konfiguration tatsächlich rund 2,4 GiB. Diese Messung ist eine Stichprobe
mit synthetischen Daten und keine allgemeine Speicherobergrenze.

Die Touch-Bedienung des alten API-24-System-Dateidialogs reagierte während
der Automatisierung unzuverlässig. Für den dortigen PDF-Belastungstest wurden
die zwölf synthetischen Einträge deshalb direkt in die zuvor leere, gesicherte
Testinstallation kopiert. Ein erfolgreicher Backup-Import über diesen alten
Dateidialog ist damit nicht nachgewiesen. Der App-Import selbst wurde auf
API 35 und 36 über den System-Dateidialog geprüft.

Auf API 36 wurde eine 40-seitige PDF abgewiesen. Eine 20-seitige PDF wurde
übernommen und die Schaltfläche für weitere Anhänge deaktiviert. Das
Google-Scanner-Fenster öffnete sich, zeigte jedoch seinen eigenen Fehler
„Something went wrong“. Der Abbruch kehrte ohne neuen Anhang und ohne
App-Absturz zum Formular zurück. Ein erfolgreicher Scan ist nicht nachgewiesen.

Für die Laufzeitprüfung werden ausschließlich neu angelegte Emulatoren mit
synthetischen Daten verwendet. Das Smartphone wurde auf Nutzerhinweis während
der Arbeiten getrennt. Seine Dev-Installation wurde in dieser Aufgabe weder
aktualisiert noch neu gestartet.

Das API-35-Abbild `google_apis_ps16k` meldet 16.384 Bytes Seitengröße. Vor der
Installation der App stürzte dessen `system_server` in ARTs MarkCompact-GC ab.
Für dieses isolierte Testabbild wurde
`device_config put runtime_native_boot enable_uffd_gc false` gesetzt und Android
neu gestartet. Diese Anpassung betrifft ausschließlich den Emulator. Der
[AOSP-Kernel-Fix](https://android.googlesource.com/kernel/common/+/38447e018c92f6ae182067a02a6954fa92b33a73)
beschreibt die Unverträglichkeit des UFFD-GC mit emulierten 16-KB-Seiten auf
x86_64. Die verwendete Property ist in
[ART dokumentiert](https://android.googlesource.com/platform/art/+/695e09b8af%5E!/).

## Freigabegrenze

Die Übergabe dient dem internen Play-Test. Es wurden keine Play-Console-Felder
gespeichert, keine Tester eingeladen und keine Veröffentlichung ausgelöst.
Der tatsächliche Play-Stand und die Freigaben des Kontoinhabers sind nicht
über eine angebundene Play Console überprüfbar.

Ein echter Kamera-Scan mit erstmaligem Modul-Download und Prozessverlust
während der Google-Oberfläche bleibt ein gesonderter Hardware-Test. Die
automatisierten nativen Lifecycle-Tests ersetzen diese Interaktion nicht.
Vor Produktion sind der interne Test, die Play-Vorabtests und die konkreten
Store-Erklärungen abzuschließen. Die Signiersicherung zusätzlich außerhalb
dieses Rechners aufbewahren.
