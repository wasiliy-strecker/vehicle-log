"""Capture the real Store release after importing the synthetic encrypted backup."""
import argparse

from capture import Capture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("serial")
    parser.add_argument("kind", choices=["phone", "tablet7", "tablet10"])
    parser.add_argument("output")
    args = parser.parse_args()
    d = Capture(args.serial)
    width, height, density = {
        "phone": (1080, 1920, 320),
        "tablet7": (1920, 1080, 240),
        "tablet10": (2560, 1440, 288),
    }[args.kind]
    d.geometry(width, height, density)
    if args.kind == "phone":
        folder = f"{args.output}/raw/phone"
        d.dashboard()
        d.capture(f"{folder}/01.png")
        d.tap("Familienauto")
        d.tap("Eintrag erfassen")
        d.tap("Ohne Foto erfassen")
        d.tap("Wartung")
        d.capture(f"{folder}/02.png")
        d.tap("Zurück")
        d.tap("Eintrag verwerfen")
        d.tap("Zurück")
        d.tap("Dokumentiert am 18.09.2026, 10:00 Uhr")
        d.tap("Bearbeiten")
        d.capture(f"{folder}/03.png")
        d.dashboard()
        d.tap("Liefer-Lkw")
        d.reveal("Dokumentiert am 17.09.2026, 10:00 Uhr")
        d.tap("Dokumentiert am 17.09.2026, 10:00 Uhr")
        d.tap("Bearbeiten")
        d.align("Aktuelle PDFs (2)", 230)
        d.capture(f"{folder}/04.png")
        d.dashboard()
        d.tap("Liefer-Lkw")
        d.align("Dokumentiert am 17.09.2026, 10:00 Uhr", 350)
        d.capture(f"{folder}/05.png")
        d.dashboard()
        d.run("shell", "pm", "grant", "com.appfactory.vehicle_log", "android.permission.POST_NOTIFICATIONS")
        d.tap("Familienauto")
        d.tap("Fahrzeug & Erinnerung bearbeiten")
        d.tap("Fahrzeugerinnerung")
        d.align("Fahrzeugerinnerung", 280)
        d.swipe(70)
        d.capture(f"{folder}/06.png")
        d.tap("Zurück")
        d.tap("Änderungen verwerfen")
        d.dashboard()
        d.tap("Liefer-Lkw")
        d.report()
        d.capture(f"{folder}/07.png")
        d.dashboard()
        d.tap("Einstellungen")
        d.capture(f"{folder}/08.png")
    else:
        folder = f"{args.output}/{args.kind}"
        d.dashboard()
        d.capture(f"{folder}/01-dashboard.png")
        d.tap("Liefer-Lkw")
        d.align("Dokumentiert am 17.09.2026, 10:00 Uhr", round(170 * density / 160))
        d.capture(f"{folder}/02-history.png")
        d.dashboard()
        d.tap("Familienauto")
        d.reveal("Dokumentiert am 18.09.2026, 10:00 Uhr")
        d.tap("Dokumentiert am 18.09.2026, 10:00 Uhr")
        d.align("Reifenwechsel · 64820 km", round(105 * density / 160))
        d.capture(f"{folder}/03-reading.png")
        d.dashboard()
        d.tap("Liefer-Lkw")
        d.reveal("Fahrzeugprotokoll für den Fahrzeugverlauf erstellen")
        d.report("Kompakt ohne Anhänge")
        d.scroll_pdf()
        d.capture(f"{folder}/04-pdf.png")
    d.dashboard()


if __name__ == "__main__":
    main()
