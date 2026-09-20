# Interner Play-Test 1.0.0 (3)

## Einordnung

Store-Paket: `com.appfactory.vehicle_log`. Die Dev-App verwendet weiterhin
`com.appfactory.vehicle_log.dev`. Dieses Dokument bereitet den manuellen
Upload vor. Es wurde keine Veröffentlichung und keine Play-Console-Eingabe
vorgenommen. Der technische Prüfbericht nennt die tatsächlich durchgeführten
Prüfungen und die Grenzen des Nachweises.

## Release-Titel

```text
1.0.0 (3) – Sichere Backups und automatische PDF-Aufteilung
```

## Release-Notizen

```text
<de-DE>
Fahrzeugakte für den internen Test.
Backups werden bei Speicherfehlern vollständig zurückgerollt.
PDF-Anhänge: bis zu 20 Seiten und 50 MB pro Eintrag, maximal 25 MB je Datei.
Große Fahrzeugprotokolle werden automatisch auf mehrere PDFs mit bis zu 100 Seiten und 50 MB je Teil verteilt. Alle Teile lassen sich gemeinsam teilen.
Die Datenschutzhinweise zum Dokumentscanner wurden ergänzt.
</de-DE>
```

## App-Name

```text
Fahrzeugakte
```

## Kurzbeschreibung

```text
Wartungen, Reparaturen und Belege lokal verwalten. Mit PDF-Export und Backup.
```

## Vollständige Beschreibung

```text
Deine Fahrzeuggeschichte an einem Ort.

Mit Fahrzeugakte dokumentierst du Wartungen, Reparaturen, HU/AU und Kilometerstände. Ergänze Werkstatt, Kosten und Notizen und ordne Fotos und PDF-Belege direkt dem passenden Eintrag zu.

Erfasse deine Fahrzeuge mit optionalem Kennzeichen, Marke und Modell, FIN und Erstzulassung. Richte freiwillige Erinnerungen ein und behalte deine Einträge im Blick.

Importiere vorhandene PDFs oder erfasse Dokumente mit dem Android-Dokumentscanner. Pro Eintrag sind insgesamt bis zu 20 PDF-Seiten und 50 MB möglich. Eine einzelne PDF darf bis zu 25 MB groß sein. Der Scanner benötigt Google Play Services und mindestens 1,7 GB RAM. Beim ersten Start kann ein Download erforderlich sein.

Erstelle kompakte Fahrzeugprotokolle oder vollständige Berichte mit Fotos und PDF-Seiten. Große Verläufe werden automatisch auf mehrere nummerierte PDFs mit höchstens 100 Seiten und 50 MB je Teil verteilt. Du kannst die Teile ansehen und gemeinsam teilen.

Deine Fahrzeugdaten bleiben im privaten Speicher der App. Fahrzeugakte benötigt kein Konto und bietet keine Werbung oder Cloud-Synchronisation. Google Play Services können für den Dokumentscanner technische Diagnose- und Nutzungsdaten verarbeiten. Details stehen in der Datenschutzerklärung.

Sichere deine Daten mit einem passwortgeschützten, verschlüsselten Backup. Bewahre das Passwort sicher auf. Es kann nicht wiederhergestellt werden.

Die App dient der privaten Dokumentation und ersetzt keine amtlichen Nachweise.
```

## Kontaktdaten und Zuordnung

Support: contact@appfabrik-ai.de

Datenschutzerklärung:
https://github.com/wasiliy-strecker/vehicle-log/blob/main/PRIVACY.md

Quellcode: https://github.com/wasiliy-strecker/vehicle-log

Passende Kategorie: Autos & Fahrzeuge. Keine Werbung, keine Käufe und kein
Konto. Die Funktionen sind ohne Login erreichbar. Content Rating, Zielgruppe,
Länderauswahl und notwendige Erklärungen müssen im konkreten Play-Eintrag
vom Kontoinhaber bestätigt werden.

## Datensicherheit vorbereiten

Fahrzeugdaten, Kennzeichen, FIN, Notizen, Fotos und PDF-Inhalte werden lokal
verarbeitet. Es besteht kein Entwickler-Backend. Exporte werden nur nach
Nutzeraktion an die gewählte App oder den gewählten Speicherort übergeben.

Der Scanner verwendet `play-services-mlkit-document-scanner:16.0.0` über
Google Play Services. Google nennt für ML Kit Geräte- und App-Informationen,
Kennungen, Nutzungsereignisse und Diagnosemetriken. Eine pauschale Angabe
„keine Daten erhoben“ ist deshalb nicht als geprüft freigegeben.

Für die Datensicherheit sind insbesondere Geräte- oder andere IDs,
App-Interaktionen und Diagnoseinformationen zu prüfen. Zweck ist Analyse
beziehungsweise Diagnose durch den SDK-Anbieter. Google nennt HTTPS für
Übertragungen und keine Weitergabe dieser SDK-Daten an weitere Dritte.
Die freiwillige Scanner-Nutzung erlaubt den alternativen PDF-Import.
Die konkrete Abgrenzung zwischen SDK-Verarbeitung und Google Play Services
sowie die Pflichtfelder des aktuellen Play-Formulars müssen beim Upload
abgeglichen werden. Dieses Dokument behauptet keine durchgeführte
Netzwerkaufzeichnung und keine Freigabe durch Google.

Quellen, geprüft am 20.09.2026:
[ML Kit Terms & Privacy](https://developers.google.com/ml-kit/terms),
[Google Play data disclosure](https://developers.google.com/ml-kit/android-data-disclosure).

## Schlüssel aufbewahren

Der eigene Upload-Schlüssel liegt außerhalb des Repositories unter
`~/.local/share/app-factory/signing/fahrzeugakte/`. Eine lokale Kopie liegt
unter `~/backups/fahrzeugakte-signing/`. Zugangsdaten und Schlüssel sind nur
für den lokalen Benutzer lesbar. Die lokale Kopie schützt nicht vor dem
Verlust dieses Rechners. Vor dauerhaftem Play-Betrieb auch außerhalb dieses
Rechners sicher aufbewahren. Keine Schlüssel oder Passwörter in GitHub,
Release-Notizen oder öffentliche Store-Felder übernehmen.
