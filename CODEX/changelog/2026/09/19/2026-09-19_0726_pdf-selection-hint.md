# PDF-Auswahl verständlicher beschriften

Der Menüpunkt heißt „PDF auswählen“. Beim Hinzufügen auf Android erklärt
ein Hinweis die Mehrfachauswahl durch längeres Drücken auf die erste Datei.
Beim Ersetzen erscheint dieser Hinweis nicht, weil nur eine PDF ersetzt wird.

Die bestehende Implementierung aktiviert beim Hinzufügen bereits
allowMultiple und das Android-Plugin setzt EXTRA_ALLOW_MULTIPLE. Beim
Ersetzen wird die Auswahl auf eine Datei begrenzt. Diese Optionen und die
Übernahme von zwei PDFs werden in den vorhandenen Entwurfstests geprüft.

Prüfung: Dart-Formatierung, Flutter-Analyse und gezielte Formular- und
Entwurfstests. Erfolgreicher Hot Reload auf dem verbundenen Smartphone.
Der gesperrte Smartphone-Dateidialog wurde nicht interaktiv geprüft.
Kein APK-Neubau oder Neustart.
