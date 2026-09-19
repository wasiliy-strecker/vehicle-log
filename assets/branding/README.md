# Fahrzeugakte App-Icon

Ein schlichtes Auto von vorn in Eisweiß auf Stahlblau. Keine fotorealistischen
Details, Schatten oder eingebetteten Hintergrundflächen im Symbol.
`fahrzeugakte_mark.svg` ist die transparente Vektorquelle. Windschutzscheibe,
Scheinwerfer und die Fläche außerhalb des Autos sind tatsächlich durchsichtig.

`scripts/render_app_icons.sh` erzeugt aus denselben Pfaden den nativen Android-
Vordergrund und alle PNGs für Android, iOS und Web. Benötigt werden Python 3 mit
PyGObject, Cairo und Rsvg sowie ImageMagick. Rsvg rendert die Kurven unmittelbar
mit 1024 Pixeln. Daraus werden die kleineren PNGs abgeleitet.

Das adaptive Android-Icon kombiniert den transparenten Vektor mit der
Launcher-Farbe `#243D53`. Das Motiv liegt im sicheren Innenbereich des
108-dp-Viewports. Der Startbildschirm ab Android 12 verwendet ausdrücklich nur
den Vektor und einen transparenten Icon-Hintergrund. Die gesamte Startfläche
verwendet in beiden Themes dieselbe Farbe `#243D53`. Es gibt kein zusätzliches
Rechteck oder einen andersfarbigen Hintergrund innerhalb der Grafik.

Referenzen: [Adaptive Icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
und [Android-Startbildschirm](https://developer.android.com/develop/ui/views/launch/splash-screen).

## Manuelle Sichtprüfung

Die exportierte Grafik lokal auf saubere Kurven und Lesbarkeit prüfen.
Nach datenbewahrender Aktualisierung der Dev-APK prüft der Nutzer auf seinem
Smartphone das Launcher-Icon und einen normalen Kaltstart. Erwartet werden
das einfache Auto, vollständig sichtbare Räder und eine einheitliche
Startfläche ohne rechteckige Ränder. Auch im Dunkelmodus prüfen.
Codex führt auf ausdrücklichen Wunsch keine visuellen Smartphone-Tests aus.
