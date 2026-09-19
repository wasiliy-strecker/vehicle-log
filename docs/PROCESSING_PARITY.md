# Abgleich mit Mein Pflanzenbuch

## Bearbeiten ohne Korrekturverlauf

Seit dem Nutzerauftrag vom 19.09.2026 ersetzt einfaches Bearbeiten und Speichern
in dieser App den früher übernommenen Korrekturablauf. Diese Änderung gilt
auch für die unten dokumentierten älteren Übernahmestände.

Die Verlauf-Card, Vorher-/Nachher-Fotos beziehungsweise PDFs, Korrekturgrund
und Protokollierungshinweise entfallen. Die normale Eintragsliste bleibt
bestehen. Fotoauswahl, Entwürfe, Sortierung, Erinnerungen und aktuelle
PDF-Berichte bleiben verfügbar.

`MeterReadingService.update` benötigt keinen Grund und speichert mit `save`
ohne neue Revision. Aktuelle Anhänge werden bei Änderungen nicht als neue
historische Versionen gesammelt. Bestehende historische Listen und Revisionen
bleiben erhalten. Wird ein aktueller Anhang noch von einer alten Revision
referenziert, bleibt auch seine Metadatenzuordnung erhalten. Alte Foto-Revisionen
mit SHA-256 statt IDs werden ebenfalls berücksichtigt.

Entfernte Dateien und Foto-Caches werden erst nach erfolgreichem Speichern
und Prüfung verbleibender Referenzen bereinigt. Bei Fehlern bleibt eine
verwaiste Datei gegebenenfalls liegen, ohne den gespeicherten Eintrag oder
seine neuen Anhänge zu verwerfen. Es erfolgt keine pauschale Altdatei-Bereinigung.
Schema, Backupversion und eingefrorene Quellhashes bleiben unverändert.
Legacy-Revisionen werden weiterhin gesichert und wiederhergestellt.

`editing_without_history_test.dart` prüft Änderungen ohne neue Revision,
Erhalt alter ID-/Hash-Referenzen, geteilte Dateipfade sowie Speicher- und
Bereinigungsfehler. Die bisherigen Ablaufprüfungen erwarten jetzt den aktuellen
Stand. Legacy-Backupprüfungen verwenden ausdrücklich gespeicherte Altversionen.

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

Im Formular fasst eine Card mit „Aktuelle PDFs“ und Anzahl die PDF-Liste
und den Button „PDF auswählen/scannen“ zusammen, entsprechend der Foto-Card.
Ohne Anhänge erscheint „Keine aktuellen PDFs“. Auswahl, Scannen und
Dokumentaktionen verwenden weiterhin dieselben Abläufe.

Ab zwei aktuellen PDFs bietet die PDF-Card zusätzlich Sortieren durch
längeres Drücken und Verschieben, einschließlich Zielmarkierung und Scrollen
am Formularrand. Der Hinweis steht wie bei Fotos direkt unter der Überschrift.
Die Fotokomponente bleibt unverändert. Die PDF-Komponente meldet geordnete
Dokument-IDs an die vorhandene `changeDocuments`-Methode. Entwürfe, Korrekturen
und gespeicherte Reihenfolgen verwenden weiterhin die bestehenden Datenwege.
Während Verarbeitung oder Speichern und in reinen Ansichten ist Ziehen
deaktiviert. `document_sorting_widget_test.dart` prüft die Bedienung und
Wiederherstellung der Reihenfolge.

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

## Datumsauswahl für die Erstzulassung

Die Erstzulassung öffnet auf Wunsch des Nutzers einen Kalender mit
Jahresauswahl zuerst. Ein bestätigtes Datum wird als TT.MM.JJJJ gespeichert.
Das Feld bleibt optional und kann geleert werden. Bestehende MM.JJJJ-Angaben
werden nicht beim Öffnen oder bei Änderungen anderer Fahrzeugfelder umgeschrieben.
Abbrechen erhält den bisherigen Wert. Datenbank, Backups und PDF-Ausgabe
verwenden weiterhin dasselbe Textfeld. Es ist keine Migration erforderlich.
`first_registration_picker_test.dart` prüft Auswahl, Abbruch, Entfernen,
Speichern und die Verträglichkeit mit bisherigen Monatsangaben.
