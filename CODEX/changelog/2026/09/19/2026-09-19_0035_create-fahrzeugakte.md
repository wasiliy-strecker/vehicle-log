# Fahrzeugakte als eigenständige App

Pflanzenbuch-Commit `0fa2f85d26047f1f22ef6fae17cf93d000ca66e3` app-lokal übernommen.
Eigene Dev-/Store-Identität, Fahrzeugtexte, Icons und Stahlblau-/Anthrazit-Theme.
Die vorhandenen Foto-, Korrektur-, Erinnerungs- und Backup-Abläufe bleiben die Grundlage.

Fahrzeuge erhalten optionale FIN und Erstzulassung. Einträge ergänzen Werkstatt,
Kosten in Cent und mehrere PDF-Dokumente. Der Android-Dokumentscanner verwendet
Plugin und Einstellungen aus AI Contract Manager. PDFs lassen sich öffnen,
teilen, ersetzen, entfernen und sortieren. Entwürfe und Korrekturen erhalten
aktuelle sowie frühere Anhänge. Keine automatische Analyse und kein Gateway.

Vollständige Einzel- und Verlaufsprotokolle übernehmen Original-PDF-Seiten direkt
nach dem jeweiligen Eintrag. Kompakte Protokolle nennen die Anhänge. Text und
Querformat bleiben erhalten. Beschädigte, fehlende und passwortgeschützte PDFs
werden ausdrücklich behandelt. Die Verlaufstabelle passt längere Fahrzeugbegriffe
an und zeigt Kilometerdifferenzen unabhängig von der Aktivität.

Schema 8 und Backup-Version 6 enthalten alle neuen Daten und PDF-Dateien.
Quellhashes der Vorlage und ältere Paritätsreferenzen bleiben unverändert.
Autorisierte Abweichungen sind mit eigenen Hashes, Begründungen und Tests erfasst.
Dokumentation und Offline-Datenschutzerklärung wurden angepasst. Fremde Backups
werden abgewiesen. Keine Signierschlüssel oder Store-Demos anderer Apps übernommen.

Prüfung: `dart format --output=none --set-exit-if-changed lib test` und
`flutter analyze` erfolgreich. 712 Flutter-Tests einschließlich PDF-Textaudit
unter Europe/Berlin erfolgreich. 28 native Android-Tests erfolgreich, ausgeführt
mit vollständigem JDK 21 aus `~/.local/jdk-21`.
`flutter build apk --debug --flavor dev` erfolgreich.

Browser-Vorschau auf Port 53545 visuell geprüft und per Hot Reload aktualisiert.
Android-Dev-App erstmals im Emulator installiert. Synthetische mehrseitige PDF
importiert, beide Seiten einschließlich Querformat geöffnet und den zugehörigen
Eintrag gespeichert. Der native Export enthält vier Seiten in korrekter
Reihenfolge, darunter beide durchsuchbaren Originalseiten. Der Aufruf des
Scanners erreicht Googles ModuleDownloadActivity. Google meldet im Emulator
„Something went wrong“. Abbrechen kehrt zur App zurück. Ein echtes Smartphone
war nicht verbunden. Ein realer Kameradokumentscan bleibt eine Geräteprüfung.
