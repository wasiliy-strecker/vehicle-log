# Datenschutz-Update dauerhaft auf dem Smartphone installieren

Auf ausdrücklichen Nutzerwunsch die Dev-APK mit der aktuellen Datenschutz-
Verlinkung aus Commit 7f25536 neu gebaut. Der vorherige Hot-Reload-Versuch
hatte mangels wiederauffindbarer Debug-Verbindung die laufende App nicht
aktualisiert. Der jetzt beauftragte APK-Build liefert die Änderung dauerhaft.

Zielpaket com.appfactory.vehicle_log.dev, installierte Version 1.0.0+1,
Debug-Flag und Installer geprüft. Das Zertifikat des vom Gerät gelesenen APKs
stimmt mit dem neuen APK überein. Paketkennung, Version, Debug-Flag und der
neue vehicle-log-Datenschutz-Link im gebauten APK wurden geprüft.
Datenbewahrende Installation mit adb install -r -t -g --no-streaming erfolgreich.
Keine Deinstallation, Datenlöschung oder Versionsänderung.

Die bereits für 7f25536 erfolgreichen Formatierungs-, Analyse- und 175
gezielten Testprüfungen gelten unverändert. In dieser Aufgabe wurden nur
AGENTS.md und dieser Changelog geändert. Dokumentation und Whitespace geprüft.
Keine visuellen Smartphone-Tests.

Die neue dauerhafte Nutzeranweisung ist in AGENTS.md festgehalten:
Abgeschlossene Änderungen für Fahrzeugakte immer committen und nach origin
pushen. main ist der Standardbranch. Die Datenschutzänderung war bereits
gepusht, dieser Dokumentationsstand folgt mit eigenem Commit.
