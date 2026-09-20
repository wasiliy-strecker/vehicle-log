# Aktuellen Dev-Stand erneut auf dem Smartphone installieren

Auf ausdrücklichen Nutzerwunsch die Änderungen aus Commit c317a03 als Dev-APK
neu gebaut. Installiert ist jetzt Fahrzeugakte Dev 1.0.0+3 mit den aktuellen
PDF-Grenzen, mehrteiligen Protokollen und Absicherungen der Wiederherstellung.
Die bereits vorhandene Versionsnummer wurde nicht zusätzlich erhöht.

Vor dem Update com.appfactory.vehicle_log.dev, installierte Version 1.0.0+1,
Debug-Flag und Installer geprüft. Die Signatur des vom Gerät gelesenen APKs
stimmt mit dem neuen APK überein. Zielpaket, Version 1.0.0+3 und Debug-Flag des
neuen Builds geprüft. Installation mit adb install -r -t -g --no-streaming
erfolgreich und App gestartet. Der SHA-256-Wert der installierten APK entspricht
dem neuen Build. Keine Deinstallation oder Datenlöschung.

Der zugrunde liegende Code war bereits committet und gepusht. Seine erfolgreichen
Prüfungen sind im Changelog zu c317a03 dokumentiert: Formatter, Analyzer,
761 Flutter-Tests mit PDF-Textprüfung und 31 native JVM-Tests. Keine erneuten
Codeänderungen. Für diesen Dokumentationseintrag Inhalt und Whitespace geprüft.
Keine visuellen Smartphone-Tests. Dev-Sitzung für spätere Live-Updates geöffnet.
