# Fiktive Store-Beispiele

Diese fünf Fotos wurden mit dem eingebauten imagegen-Werkzeug erzeugt.
Die vollständigen Prompts stehen in `prompts.json`. Sie zeigen keine echten
Kundenfahrzeuge oder persönlichen Daten und sind keine Produktfotos eines Herstellers.

Der Host-Test `test/tooling/store_demo_backup_test.dart` erzeugt dazu vier
Fahrzeuge, 32 Einträge und zwei deutlich als MUSTER gekennzeichnete PDF-Belege.
Er prüft den regulären verschlüsselten Backup-Roundtrip einschließlich Dateien,
Reihenfolge und Hashes. Das Demo-Passwort lautet `Demo2026`.

Die Dateien werden nicht als Laufzeit-Assets in die App eingebunden.
Sie dienen ausschließlich den Store-Aufnahmen im eigenen Emulator.
