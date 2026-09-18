# Synthetische Backups der Quell-App

Die beiden Dateien wurden unverändert aus Mein Pflanzenbuch übernommen.
Sie enthalten keine Nutzerdaten und keine echten Fotos. Das öffentliche
Testpasswort lautet jeweils `fixture-only`.

`legacy_single_photo_v3.pfbackup` stammt aus Pflanzenbuch-Commit `df9638e`.
Die Version-3-Datei enthält eine synthetische Pflanze, einen Gieß-Eintrag
und vier Testbytes als Foto.

`legacy_multiple_photos_v4.pfbackup` stammt aus Pflanzenbuch-Commit `01767af`.
Die Version-4-Datei enthält eine synthetische Pflanze, einen Wachstumseintrag,
drei aktuelle Testfotos und ein archiviertes Testfoto mit einer Fotoänderung.

In Fahrzeugakte prüfen diese Dateien die Zurückweisung fremder Backups vor
Schreibzugriffen. Sie werden ausdrücklich nicht als historische
Fahrzeugakte-Backups ausgegeben. Eigene Fahrzeugakte-Backups mit Fahrzeugdaten,
Fotos, PDFs und Revisionen werden in den Roundtrip-Tests erzeugt und geprüft.
