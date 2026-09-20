# PDF-Abläufe technisch prüfen und absichern

PDF-Import, Android-Scan, Bearbeiten, Reihenfolge, Entfernen, Hinzufügen,
Einzel-PDFs, Fahrzeugverläufe und die zugehörigen Datenwege geprüft.

Android-Löschungen über eine gemeinsame Drift-Transaktion abgesichert.
Dateien erst nach erfolgreicher Löschung und Prüfung verbleibender Referenzen
bereinigen. Berichtslöschungen erhalten ihre Datei bei Datenbankfehlern.
Fehlgeschlagene Berichtserstellungen räumen ihre neue Datei wieder auf.
Fehler beim Aktualisieren von Erinnerungen können gespeicherte Einträge
nicht mehr nachträglich als fehlgeschlagen melden.

Native Scanner-Rückgaben nach Prozessverlust oder doppelte Rückgaben werden
vor dem gepinnten Plugin abgefangen. Scanner-Start und Abschluss verwenden
einen app-lokalen Lifecycle-Kanal. Scanner-Voraussetzungen und PDF-Import als
Alternative in der Fehlermeldung präzisiert.

Regressionstests für SQLite-Rollbacks, Mehrfachimport, PDF-Entwürfe, aktuelle
Anhangsreihenfolge, unveränderte ältere Berichte und Scanner-Lifecycle ergänzt.
Paritätsausnahmen fortgeschrieben, ursprüngliche Quellhashes erhalten.
Prüfbericht unter `docs/PDF_RELEASE_AUDIT.md` angelegt.

Verifiziert: Formatter, `flutter analyze`, 742 Flutter-Tests mit
`PDF_TEXT_AUDIT=true`, 31 native JVM-Tests und `git diff --check` erfolgreich.
Vorhandene Dev-APK statisch auf API-Minimum, ABIs und 16-KB-Ausrichtung geprüft.

Keine visuellen Prüfungen, kein Emulator, kein App-Start und keine Installation.
Keine neue Versionsnummer, kein Release-Build und kein Upload. Store-Signierung
und tatsächliche Gerätematrix bleiben vor einer endgültigen Freigabe offen.
Die Kotlin-Korrektur benötigt bei einem später autorisierten Gerätetest eine
aktualisierte Dev-APK. Die vorhandene Installation enthält sie noch nicht.
