# Fahrzeugakte App-Icon

Das aktuelle Motiv ist ein silberblaues Fahrzeug mit Dokumenten auf stahlblauem
Hintergrund. `fahrzeugakte_mark.png` ist das transparente Original aus dem
integrierten Imagegen-Tool mit 1254 × 1254 Pixeln. Es ersetzt die frühere einfache
SVG-Zeichnung. Die Ausgabegrößen werden daraus reproduzierbar abgeleitet.

`scripts/render_app_icons.sh` erstellt aus diesem Original das 1024-Pixel-Icon,
die Android-, iOS- und Web-Varianten sowie den separaten Android-Vordergrund
mit 1080 × 1080 Pixeln. Android ab API 26 verwendet ein adaptives Icon.
Das Motiv sitzt mit ausreichend Abstand im sicheren Innenbereich.
Android ab API 31 verwendet dieses große Icon ausdrücklich für den Startbildschirm.
Das Startbild wird nicht aus den kleinen Legacy-Launcher-PNGs vergrößert.

Referenzen: [Adaptive Icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
und [Android-Startbildschirm](https://developer.android.com/develop/ui/views/launch/splash-screen).

## Erzeugungsprompt

Integriertes Imagegen-Tool, keine CLI und kein separater API-Aufruf.

```text
Use case: logo-brand
Asset type: final production Android launcher and splash-screen artwork for a German vehicle maintenance log app, Fahrzeugakte.
Create ONE exceptionally crisp premium app icon, square 2048 by 2048 pixels if possible. A refined modern unbranded silver-blue passenger car in a restrained front three-quarter view, combined with a slim pale vehicle document/logbook behind it. The vehicle must look elegant and convincingly proportioned, with a sculpted hood, dark windshield, precise slim headlights and dark tires. Sophisticated editorial product illustration with gentle dimensional shading and clean decisive edges, not a cartoon, not a toy, not a generic smiling taxi pictogram. Use a small number of substantial shapes so it is readable at launcher size.
Background: perfectly flat solid deep steel navy #243D53 extending to all four edges. No rounded outer container or border. Palette: silver, icy pale blue, white, muted steel blue and charcoal, no other bright colors.
Composition: centered compact unified emblem, entire car and document contained within the central 60 percent of the square, with generous uniform navy negative space. The car is the main subject, the document is a quieter secondary cue with only two understated lines. All essential artwork should comfortably survive a circular app-icon crop.
No text, lettering, numbers, brands, badges, watermarks, scenery, road or extra symbols. No fuzzy glow, no heavy gradients in the background. Output the final artwork itself, not a phone mockup, no variants or grids.
```

## Nachbearbeitungsprompt

```text
Use case: background-extraction
Edit target: the attached generated Fahrzeugakte app emblem.
Keep the exact elegant silver-blue car, its realistic proportions, colors and the two pale document sheets.
Clean the cutout precisely: remove every stray white speck, ragged white halo, colored pixel and background remnant around the paper, car and shadow. Crisp clean antialiased silhouettes. Remove the broad floor shadow and keep only a subtle compact contact shadow under the tires.
Output genuinely transparent background with clean alpha, never a black or navy background. No logo, text or extra elements.
Center the entire finished emblem inside the central 60 percent of a square canvas with generous transparent padding on all sides, for Android adaptive icon safe area. Maintain the highest available native resolution and fine edge quality.
```
