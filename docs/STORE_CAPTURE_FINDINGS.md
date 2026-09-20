# Befund aus den Store-Aufnahmen vom 20.09.2026

## Speicherabsturz der hochauflösenden PDF-Vorschau

Store 1.0.0+3, Paket `com.appfactory.vehicle_log`, unveränderte Runtime aus der
bereits vorhandenen AAB. Eigener API-35-x86_64-Emulator mit 2048 MiB RAM,
Android-App-Heap-Limit 192 MiB. Darstellung 2560×1440 Pixel bei 288 dpi.

Nach Import des fiktiven Store-Backups: Liefer-Lkw öffnen und Fahrzeugprotokoll
für den Fahrzeugverlauf erstellen. Variante „Mit Fotos und PDFs“ wählen.
Der Verlauf umfasst acht Einträge, ein Fahrzeugfoto und zwei einseitige PDFs.
Beim Aufbau der PDF-Vorschau wurde die App vom Android-Prozess beendet.

Logcat 20:12:00:

```text
Process: com.appfactory.vehicle_log
java.lang.OutOfMemoryError: Failed to allocate a 68447120 byte allocation
with 25165824 free bytes and 25MB until OOM
at java.util.Arrays.copyOf
at java.io.ByteArrayOutputStream.grow
at java.io.ByteArrayOutputStream.ensureCapacity
at java.io.ByteArrayOutputStream.write
```

Das spricht für einen zu hohen Speicherbedarf bei der nativen Ausgabe der
PDF-Vorschaubilder. Die genaue Ursache wurde in dieser Asset-Aufgabe nicht
weiter isoliert. Das ist kein Nachweis für einen Fehler im gespeicherten PDF
und keine Aussage über alle Tablets oder physische Geräte.

Die Variante mit Anhängen ließ sich bei 1080×1920 und 1920×1080 Pixeln anzeigen.
Für beide finalen Tablet-Aufnahmen wird der reguläre kompakte Export verwendet.
Die 2560×1440-Vorschau dieses kompakten Exports wurde separat aufgenommen.
Kein App-Code wurde angepasst und kein neuer Release erstellt.

Vor einer umfassenden Freigabe für hochauflösende Tablets sollte die native
PDF-Rasterisierung mit begrenztem Heap geprüft und bei Bedarf in Auflösung
und Speicherbedarf begrenzt werden. Die grünen Flutter-Host-Tests decken diesen
nativen Speichergrenzfall nicht ab.
