# Schlichtes Fahrzeug-Icon mit transparentem Vordergrund

Das zuletzt vom Nutzer aufgenommene Smartphone-Bild zeigte ein detailliertes
Auto mit einer abweichenden rechteckigen Hintergrundfläche. Das Motiv wurde
auf Wunsch durch eine einfache eisweiße Auto-Silhouette ersetzt.

Eine transparente SVG-Quelle erzeugt den nativen Android-Vektor und sämtliche
Launcher-PNGs für Android, iOS und Web. Der Startbildschirm verwendet in beiden
Themes direkt den Vektor mit transparentem Icon-Hintergrund. Die detaillierten
Rasterquellen wurden entfernt. Renderweg und manuelle Prüfschritte sind in
assets/branding/README.md dokumentiert. Keine Änderung an Dart-Verarbeitung,
Datenformaten oder Versionsnummern.

Prüfung: dart format lib test ohne Änderungen, flutter analyze --no-pub ohne
Befunde, 177 Tests aus test/parity, test/app/app_theme_test.dart und
test/widget_test.dart erfolgreich. Shell-Syntax, transparente Aussparungen,
adaptiver Sicherheitskreis und identische SVG-/Android-Pfade geprüft.
Die neue Grafik lokal angesehen. Der gebaute APK-Vordergrund ist ein Vektor.

Wegen nativer Icon- und Theme-Ressourcen Dev-APK neu gebaut. Installiertes
Zielpaket com.appfactory.vehicle_log.dev, Version 1.0.0+1, Debug-Status und
Installer geprüft. Signatur des installierten und neuen APKs stimmt überein.
Update mit adb install -r -t -g --no-streaming erfolgreich und App gestartet.
Keine Deinstallation oder Datenlöschung. Keine visuellen Smartphone-Tests.
Die Sichtprüfung auf dem Smartphone übernimmt ausdrücklich der Nutzer.
