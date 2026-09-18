# Abgleich mit Mein Pflanzenbuch

Direkte Vorlage ist Pflanzenbuch-Commit
`0fa2f85d26047f1f22ef6fae17cf93d000ca66e3`. Fahrzeugakte enthält eine unabhängige
Kopie seiner versionierten Flutter- und Plattformquellen. Interne Meter- und
Reading-Namen sowie Enum-Werte bleiben für den Abgleich erhalten. Es gibt
keine Runtime-Abhängigkeit auf eine Nachbar-App.

`test/parity/pflanzenbuch_processing_reference.json` enthält unveränderte
Quellhashes der Dart- und nativen Hauptdateien. Autorisierte Abweichungen stehen
mit lokalem Hash, Begründung und Testnachweisen in
`test/parity/vehicle_processing_exceptions.json`. Ursprüngliche Referenzdateien
für ZählerLog und Strick & Häkelbuch bleiben ebenfalls unverändert.
Die Paritätstests prüfen unveränderte Dateien direkt und Änderungen gegen
dokumentierte Ausnahmen. Sie benötigen keinen anderen Checkout.

## Autorisierte Unterschiede

App-Identität, Ressourcen, Icons, Theme und Texte sind auf Fahrzeugakte
umgestellt. Die vorhandenen Felder `meterNumber` und `location` tragen
Kennzeichen und Marke/Modell. FIN und Erstzulassung ergänzen das Fahrzeug.
Werkstatt, optionale Kosten in Cent sowie geordnete aktuelle und historische
PDF-Anhänge ergänzen den Eintrag. Die Vorschläge heißen Wartung, Reparatur,
HU/AU und Kilometerstand. Freie Aktivitäten bleiben möglich. Messwerte gleicher
Einheit werden unabhängig von der Aktivität verglichen.

Schema 8 ergänzt diese Felder und Dokumentänderungen in Revisionen. Migrationen
behalten vorhandene Daten und Prüfsummen. Leere neue Felder werden nicht nachträglich
in alte Manifest-JSONs eingefügt. Dokumentdateipfade gehen wie Fotopfade nicht in
den Inhalts-Hash ein. Inhalt, Identität und Reihenfolge der PDFs dagegen schon.

Die vorhandene Foto-Session verwaltet zusätzlich PDF-Entwürfe. Vor dem Öffnen
eines externen Pickers oder Scanners werden Eingaben und Anhänge gespeichert.
Abbruch, fehlgeschlagenes Speichern, Wiederherstellung und Verwerfen erhalten
gespeicherte Dateien. Bereits übernommene Dokumente erkennen veraltete Entwürfe.
Ein noch nicht abgeschlossener Scan wird nach Prozessverlust nicht automatisch
wiederaufgenommen. Die bestehenden Fotoabläufe bleiben erhalten.

Der Scanner ist app-lokal mit demselben Plugin und denselben Optionen wie in
AI Contract Manager eingebunden: `google_mlkit_document_scanner` 0.4.1,
Full-Modus, maximal 20 Seiten, JPEG und PDF, kein Galerieimport. Es wird nur die
fertige PDF übernommen. Kein Gateway, OCR-Aufruf oder automatische Feldanalyse.

PDF-Anhänge werden mit `pdfrx` 2.4.7 und dessen PDFium-Engine lokal geprüft,
angezeigt und unverändert aufbewahrt. Beim vollständigen Export folgen sie
unmittelbar auf den zugehörigen Eintrag, mit Trennseiten zur Zuordnung. Die
Seiten werden als PDF-Seiten übernommen. Durchsuchbarer Text und Querformat
bleiben erhalten. Der kompakte Export nennt nur Dateinamen. Fehlende oder
beschädigte Anhänge werden nicht stillschweigend ausgelassen.

Backup-Version 6 erweitert die vorhandene Verschlüsselung und Dateireparatur
um PDF-Anhänge. Formatkennung `fahrzeugakte_backup` und Endung `.fzbackup`
trennen die neue App von fremden Backups. Die unveränderten synthetischen
Pflanzenbuch-Fixtures prüfen ausdrücklich die Zurückweisung fremder Backups.

Pflanzenspezifische Store-Demos, veröffentlichte Release-Angaben und zugehörige
Demo-Generatoren wurden nicht als Fahrzeugakte-Inhalte übernommen.
Signierschlüssel, Caches und Build-Ausgaben wurden ebenfalls nicht kopiert.

## Prüfung

Die übernommene Suite deckt Fotoauswahl, Reihenfolge, Korrekturen, Entwürfe,
Erinnerungen, PDFs, Backup-Verschlüsselung und Datei-Reparaturen ab. Texte und
Scrollwege wurden an die neue Oberfläche angepasst. Die Fachergänzungen werden
zusätzlich über `vehicle_documents_test.dart`, `vehicle_entry_screen_test.dart`,
`vehicle_migration_test.dart`, `document_draft_test.dart`,
`document_scanner_test.dart` und `vehicle_pdf_attachments_test.dart` geprüft.
Die PDF-Prüfung verwendet echte mehrseitige PDFs und kontrolliert Inhalt,
Seitenreihenfolge, Querformat und unveränderte Originaldateien.
