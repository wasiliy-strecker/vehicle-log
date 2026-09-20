# PDF-Korrekturen erneut prüfen und Dev-App aktualisieren

Commit `fb6bc58` auf erneuten Nutzerauftrag vollständig nachgeprüft.
Keine weiteren Codeänderungen erforderlich. Formatter und Analyzer ohne
Befund, 742 Flutter-Tests mit PDF-Inhaltsprüfung und 31 erneut ausgeführte
native JVM-Tests erfolgreich.

Dev-APK wegen der nativen Scanner-Korrektur und des ausdrücklichen
Update-Auftrags neu gebaut. Paket `com.appfactory.vehicle_log.dev`,
Version `1.0.0+1`, Debug-Flag, Label und Installer kontrolliert.
Signatur mit der vorhandenen Dev-Installation verglichen und bestätigt.
Native Scanner-Sperre und Dart-Kanal in der APK nachgewiesen.
ARM32, ARM64, x86_64 und 16-KB-Ausrichtung geprüft.

APK um 08:47 CEST mit `adb install -r -t -g --no-streaming` datenbewahrend
installiert. Installierte APK stimmt bytegenau mit dem geprüften Build
überein. Alle zwölf Anhangsdateien behalten ihre Prüfsummen und die bestehende
Datenbank ist weiterhin vorhanden. Erste Installationszeit unverändert.
App erfolgreich gestartet, keine Fehlermarker im geprüften Startprotokoll.

Keine visuellen Prüfungen, kein Emulator und keine interaktive Scanner-Prüfung.
Kein Store-Build, keine Versionsänderung und kein Upload. Prüfbericht um das
autorisierte Dev-Update und die verbleibenden Freigabegrenzen ergänzt.

APK-SHA-256:
`630e959cae6a79e5571922b46523821edfb0fa040803068641b7b4b343085042`.
