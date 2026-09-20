# Fahrzeugakte für den internen Play-Test vorbereiten

PDF-Anhänge auf zusammen 20 Seiten und 50 MB pro Eintrag sowie 25 MB je Datei
begrenzen. Scanner und Formular verwenden das Restbudget. Größere Altdaten
bleiben nutzbar. Fehlgeschlagene Importe und Ersetzungen bewahren alte Dateien.

Große Fahrzeugprotokolle automatisch auf Teile mit höchstens 100 Seiten und
50 MB einschließlich Deckblatt aufteilen. Alle Teile gemeinsam teilen,
getrennt speichern und erneut öffnen. Inhalte vollständig und in Reihenfolge
übernehmen. Exportgruppen gemeinsam speichern und bei Fehlern zurückrollen.

Backup-Wiederherstellung und Reparaturen in einer Drift-Transaktion speichern.
Neue Dateipfade verwenden und nur eigene unreferenzierte Dateien bereinigen.
Erinnerungen nach dem Commit abgleichen. Datenbank- und Backup-Schema bewahren.

Eigene Store-Signierung und geschützte lokale Sicherung außerhalb von Git
einrichten. ML-Kit-Datenschutzhinweise und kopierbare deutsche Store-Unterlagen
ergänzen. Signierte finale AAB 1.0.0 (3) erzeugen. Zwischenstand Build 2 erhalten.

Prüfung: Formatter und Analyzer ohne Befund. Alle 761 Flutter-Tests mit
PDF-Textprüfung sowie 31 native JVM-Tests bestehen. AAB und APK signiert,
Paket, Version, Berechtigungen, alle ABIs und 16-KB-Ausrichtung geprüft.
240-seitigen Verlauf auf API 24 und im 16-KB-Abbild vollständig exportiert.
Auf API 36 Backup-Import, 40-Seiten-Ablehnung, 20-Seiten-Annahme, Daten- und
Entwurfserhalt beim Update sowie die finale Fehlermeldung geprüft.

Grenzen: Der alte API-24-Dateidialog war automatisiert nicht zuverlässig
bedienbar. Der Google-Scanner meldete im API-36-Emulator einen eigenen Fehler.
Abbruch funktioniert. Erfolgreicher echter Scan und Play-Freigabetests bleiben
offen. Smartphone-Installation und Nutzerdaten unverändert. Kein Play-Upload.
Details in docs/INTERNAL_RELEASE_1.0.0_3.md.
