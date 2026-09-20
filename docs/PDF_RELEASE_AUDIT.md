# Technische PDF-Releaseprüfung

Dieser Bericht dokumentiert die frühere Prüfung von Version 1.0.0+1.
Den nachfolgenden Stand mit PDF-Limits, atomarer Wiederherstellung und eigener
Store-Signierung dokumentiert [Interner Play-Test 1.0.0 (3)](INTERNAL_RELEASE_1.0.0_3.md).

Stand: 20.09.2026. Geprüfte Ausgangsversion: `1.0.0+1`, Commit `7f3641b`.
Die Prüfung umfasst den aktuellen Quellstand einschließlich der in dieser
Aufgabe ergänzten Fehlerkorrekturen. Die Versionsnummer wurde nicht erhöht.

## Ergebnis und Freigabegrenze

Die automatisierte Prüfung bestätigt die unten beschriebenen Abläufe und
Fehlerfälle. Sie ist kein Nachweis für Fehlerfreiheit auf jedem Android-Gerät.
Es gibt noch keine uneingeschränkte Store-Release-Freigabe. Die Store-Signierung
ist nicht eingerichtet und `android/key.properties` fehlt. Ein signiertes
Store-AAB wurde weder erstellt noch geprüft.

Bei der ursprünglichen Prüfung wurden auf Nutzerwunsch keine App-Oberfläche,
kein Browser und kein Android-Emulator gestartet. Es wurden keine Screenshots
oder visuellen PDF-Prüfungen durchgeführt. Flutter-Tests laufen im
Testprozess. Native Tests laufen auf der JVM, bestehende Android-API-Tests
mit Robolectric. Das ist kein Lauf des Google-Scanners auf einem Gerät.
Installierte Apps und ihre Daten wurden nicht verändert.

## Nachprüfung und Dev-Update am 20.09.2026

Auf erneuten Nutzerauftrag wurde Commit `fb6bc58` nochmals geprüft.
Formatter und Analyzer sind ohne Befund. Alle 742 Flutter-Tests mit
PDF-Inhaltsprüfung und alle 31 erneut ausgeführten nativen JVM-Tests bestehen.
Es waren keine weiteren Codeänderungen erforderlich.

Wegen der nativen Scanner-Korrektur und des ausdrücklichen Update-Auftrags
wurde die Dev-APK neu gebaut und um 08:47 CEST auf dem angeschlossenen
Android-16-Gerät installiert. Paket `com.appfactory.vehicle_log.dev`,
Version `1.0.0+1`, Dev-Label, Debug-Flag und Installer wurden geprüft.
Die Signatur stimmt mit der vorhandenen Installation überein. Das Update
verwendete `adb install -r -t -g --no-streaming`. Die erste Installationszeit
blieb unverändert. Die Datenbank ist weiterhin vorhanden und alle zwölf
gespeicherten Anhangsdateien haben unveränderte Prüfsummen.

Die installierte APK stimmt bytegenau mit dem geprüften Build überein.
Die native Scanner-Sperre und ihr Dart-Kanal sind enthalten. Alle drei ABIs,
die ELF-Ausrichtung sämtlicher 64-Bit-Bibliotheken und ZIP-Ausrichtung sind
erneut geprüft. APK-SHA-256:
`630e959cae6a79e5571922b46523821edfb0fa040803068641b7b4b343085042`.

Die App wurde erfolgreich gestartet. Der laufende Prozess zeigt keine
Flutter-Fehler, unbehandelten Exceptions oder nativen Absturzmeldungen in
den geprüften Startprotokollen. Es gab keine visuellen Tests, keinen Emulator
und keine interaktive Scanner-Prüfung. Die Dev-Aktualisierung ersetzt daher
nicht die weiter unten beschriebenen Geräte- und Store-Freigabeprüfungen.

## Behobene Fehler

Beim Löschen von Einträgen oder Fahrzeugen konnten vorher Dateien verschwinden,
obwohl eine spätere Datenbankoperation fehlschlug. Auf Android werden die
Datensätze jetzt gemeinsam in einer Drift-Transaktion gelöscht. Danach folgt
eine Prüfung der verbleibenden Dateireferenzen. Geteilte Dateien bleiben
erhalten. Schlägt die Bereinigung fehl, bleibt gegebenenfalls eine verwaiste
Datei erhalten, ohne ein gespeichertes Dokument zu beschädigen.

Auch das Löschen einzelner gespeicherter Berichte erfolgt zuerst in der
Datenbank. Beim Erstellen eines Berichts wird dessen neue Datei entfernt,
wenn das Schreiben oder Speichern des Berichts fehlschlägt.

Nach erfolgreichem Speichern konnte ein nachfolgender Fehler bei der
Erinnerungsaktualisierung fälschlich als Speicherfehler erscheinen. Dieser
Fehler kann den bereits gespeicherten Eintrag nun nicht mehr verwerfen oder
den Editor zum Aufräumen seiner inzwischen gespeicherten Anhänge verleiten.

Das gepinnte Scanner-Plugin dereferenziert bei einer Scanner-Rückkehr seine
wartende native Antwort ohne Null-Prüfung. Nach Prozessverlust existiert
diese Antwort nicht mehr. Eine native Rückgabesperre verwirft solche
verwaisten und doppelten Ergebnisse, bevor sie das Plugin erreichen.
Abbruch und Startfehler lösen die Sperre. Die bestehenden Formularentwürfe
bleiben verfügbar. Ein Fehler beim Schließen des Scanners verwirft keine
bereits erhaltene PDF. Die Fehlermeldung nennt die Scanner-Voraussetzungen
und den vorhandenen PDF-Import als Alternative.

## Prüfumfang

| Ablauf | Technischer Nachweis |
| --- | --- |
| PDF-Import | Echte mehrseitige PDFs, Mehrfachauswahl, Großschreibung der Endung, unveränderte Originalbytes, gemischte gültige und beschädigte Auswahl, fehlender lokaler Pfad und Abbruch |
| Ungültige Anhänge | Passwortschutz, beschädigte Dateien, fehlende Dateien, falsche Seitenzahlen und veränderte Prüfsummen werden geprüft |
| Scan | Method-Channel-Vertrag, 20 Seiten, Full-Modus, JPEG/PDF, kein Galerieimport, Abbruch, fehlende PDF, Start- und Schließfehler sowie native Prozessverlust-Sperre |
| Bearbeiten | Hinzufügen, Ersetzen, Entfernen, Reihenfolge, Entwurfswiederherstellung und Rollback bei fehlgeschlagener Entwurfsspeicherung |
| Löschen | Echte SQLite-Fehler per Trigger, atomarer Rollback von Einträgen und Berichten, unveränderte Dateien bei Fehlern und Schutz geteilter Anhänge |
| Einzel-PDF | Aktuelle Fotos und PDFs, gespeicherte Anhangsreihenfolge, Zuordnung, durchsuchbarer Originaltext und Querformat |
| Fahrzeugverlauf | Eintragsreihenfolge, Zuordnung der PDFs zum Eintrag, kompakte und vollständige Variante sowie Erhalt bereits gespeicherter Berichte |
| Bestand und Backup | Bestehende Migrationen, alte Anhangsreferenzen, Verschlüsselung und Wiederherstellung in der vollständigen Suite |

Die Tests verwenden synthetische Dokumente. PDF-Inhalte werden mit PDFium und
Poppler als Daten geprüft. Es findet keine visuelle Betrachtung statt.

## Android-Unterstützung

Die lokale Flutter-Konfiguration und die vorhandene Dev-APK setzen
`minSdkVersion 24` voraus, entsprechend Android 7.0. Target- und Compile-SDK
sind 36. Die vorhandene APK enthält die Flutter-, PDFium- und
SQLite-Bibliotheken für `armeabi-v7a`, `arm64-v8a` und `x86_64`.

Alle geprüften nativen ARM64- und x86_64-Bibliotheken der vorhandenen
Dev-APK haben ELF-LOAD-Ausrichtungen von mindestens 16 KB. Die APK besteht
auch `zipalign -c -P 16 -v 4`. Das ist eine statische Prüfung des bereits
vorhandenen Dev-Artefakts vom 19.09.2026. Es enthält die neuen Korrekturen
noch nicht. Das endgültige Store-AAB muss eigenständig geprüft werden.
Die Android-Vorgaben sind in der
[offiziellen Dokumentation zu 16-KB-Seitengrößen](https://developer.android.com/guide/practices/page-sizes)
beschrieben.

Der Google-Dokumentscanner verlangt zusätzlich Google Play Services und
mindestens 1,7 GB Gesamt-RAM. Seine Komponenten werden bei Bedarf beim
ersten Start heruntergeladen. Diese Einschränkungen folgen aus der
[offiziellen ML-Kit-Dokumentation](https://developers.google.com/ml-kit/vision/doc-scanner/android).
PDF-Import und lokale PDF-Verarbeitung benötigen den Scanner nicht.
Ein pauschales Versprechen, dass Scannen auf jedem Android-Gerät ab API 24
funktioniert, wäre daher falsch.

## Reproduzierbare Prüfung

Abschlussergebnis: 742 Flutter-Tests einschließlich PDF-Inhaltsprüfung
bestanden. 31 native JVM-Tests bestanden. `flutter analyze` ohne Befund.
185 Dart-Dateien sind formatiert. `git diff --check` ist ohne Befund.
Die eingefrorenen Quellreferenzen und ursprünglichen SHA-256-Werte der
Paritätsprüfung sind unverändert.

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
TZ=Europe/Berlin flutter test --dart-define=PDF_TEXT_AUDIT=true --concurrency=1
```

Im Verzeichnis `android/`, mit vollständigem JDK:

```bash
./gradlew :app:testDevDebugUnitTest --max-workers=2
```

Die zuerst verwendete System-Java-Installation enthielt keinen Java-Compiler.
Der native Testlauf wurde mit dem vorhandenen vollständigen lokalen JDK 21
ausgeführt. Es wurde keine System-Java-Installation verändert.

## Vor einer endgültigen Freigabe

Store-Signierung einrichten und den fertigen Store-Build mit Paketkennung,
Version, Signatur, Berechtigungen und nativen Bibliotheken prüfen.

Die aktualisierte native Scanner-Anbindung auf echten Android-Geräten prüfen.
Relevant sind der erste Komponenten-Download, Mehrseitenscan, Abbruch,
App-Prozessverlust während des externen Scanners, erneuter Scan und Import
über unterschiedliche Dateianbieter. Die Unterstützung von Android 7,
aktuellen Android-Versionen und Geräten mit 16-KB-Seiten muss anhand einer
festgelegten Gerätematrix bestätigt werden. Große bildbasierte PDFs brauchen
zusätzlich einen Speichertest auf einem Gerät mit wenig RAM.

Diese interaktiven Scanner- und Emulatorprüfungen wurden nicht vorweggenommen.
Sie benötigen gemäß Nutzerauftrag eine vorherige Rückfrage. Die neue native
Scanner-Absicherung wurde mit dem oben dokumentierten autorisierten
Dev-Update ausgeliefert. Ein Hot Reload allein aktualisiert Kotlin-Code nicht.
