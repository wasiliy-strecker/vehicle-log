# Neues Fahrzeug-Icon und dauerhaft installierter Datumspicker

Der letzte vom Nutzer erstellte Smartphone-Screenshot zeigte ein vergrößertes,
unscharfes Startsymbol mit einfacher Autozeichnung. Das Motiv wurde mit dem
integrierten Imagegen-Tool neu gestaltet. Transparentes Original mit 1254 × 1254
Pixeln, 1024-Pixel-App-Icon und reproduzierbare Android-, iOS- und Web-Ausgaben.
Die vollständigen Prompts stehen in `assets/branding/README.md`.

Android verwendet ab API 26 ein adaptives Icon mit separatem 1080-Pixel-Vordergrund.
Das sichtbare Motiv liegt innerhalb des sicheren Kreises. Explizite Start-Themes
ab Android 12 verwenden dieses große Icon vor einem stahlblauen Hintergrund
in beiden Helligkeitsmodi. Das alte SVG wird nicht mehr als Quelle verwendet.
Fachliche Verarbeitung und Datenformate bleiben unverändert.

Der Erstzulassungs-Picker war bereits korrekt im aktuellen Dart-Code eingebunden.
Die zuvor installierte Dev-APK vom 19.09.2026 um 06:32 enthielt ihn noch nicht.
Ihre Laufzeitdatei enthielt weder `FirstRegistrationField` noch den Picker-Titel.
Hot Reload hatte diese Änderung nur für die damalige Sitzung bereitgestellt.
Der wegen nativer Icon-Ressourcen erforderliche neue Dev-Build installiert jetzt
auch den Datumspicker und die übrigen aktuellen Änderungen dauerhaft.

## Prüfung und Gerät

`dart format --output=none --set-exit-if-changed lib test` und
`flutter analyze --no-pub` erfolgreich. 21 gezielte Flutter-Tests für
Erstzulassung und App-Abläufe erfolgreich. 160 Paritäts- und Theme-Tests erfolgreich.
Shell-Syntax und Android-XML geprüft. Der sichtbare Vordergrund passt in den
sicheren kreisförmigen Bereich. Die tatsächlich gebaute APK enthält pixelgleich
die finale Grafik und den Datumspicker. `flutter build apk --debug --flavor dev
--no-pub` erfolgreich.

Vor Installation Zielpaket `com.appfactory.vehicle_log.dev`, Version 1.0.0+1,
Debug-Flag und fehlenden Store-Installer geprüft. Signierzertifikat der neuen
APK stimmt mit der vorhandenen Dev-Installation überein. Datenbewahrendes Update
mit `adb install -r -t -g --no-streaming` erfolgreich, App anschließend gestartet.
Keine Deinstallation und keine Datenlöschung. Versionsnummer unverändert.

Der Nutzer übernimmt die visuelle Smartphone-Prüfung ausdrücklich selbst.
Eine bereits begonnene Startaufzeichnung wurde nicht visuell ausgewertet und
die lokalen Aufzeichnungsdateien wurden entfernt. Es wurden keine Formulare
auf dem Smartphone bearbeitet oder gespeichert. Die Geräteprüfung des neuen
Icons und des Pickers bleibt beim Nutzer.
