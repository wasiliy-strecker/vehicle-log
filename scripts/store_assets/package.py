"""Validate and package already-rendered Play Store images. Does not edit pixels."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile

EXPECTED_AAB_SHA256 = "6e6d9a61184603a41644ec3cb71f8e847ae164b1051edec730aaea8811a0e830"
PHONE_ALT = [
    "Fahrzeugübersicht mit Pkw, Liefer-Lkw, Motorrad und E-Scooter sowie ihren letzten Einträgen",
    "Neuen Fahrzeugeintrag mit Aktivität, optionalem Kilometerstand, Werkstatt, Kosten, Fotos und PDFs erfassen",
    "Aktuelle Fahrzeugfotos mit Reihenfolge, Bearbeitung und weiteren Aufnahmemöglichkeiten",
    "Aktuelle PDF-Belege mit Musterrechnung und Prüfbericht sowie Auswahl- und Scan-Schaltfläche",
    "Fahrzeuggeschichte des Liefer-Lkw mit Wartungen, Kilometerständen und Notizen",
    "Fahrzeugerinnerung mit Intervall, Uhrzeit und normaler Benachrichtigung",
    "Echte PDF-Vorschau eines in der App erstellten Fahrzeugprotokolls mit Drucken und Teilen",
    "Einstellungen zum Erstellen und Wiederherstellen verschlüsselter Backups",
]
TABLET_ALT = [
    "Fahrzeugübersicht auf dem Tablet mit letzten Einträgen zu Pkw, Lkw und Motorrad",
    "Fahrzeuggeschichte des Liefer-Lkw auf dem Tablet mit Kilometerständen und Wartungseinträgen",
    "Gespeicherter Fahrzeugeintrag mit Kilometerstand, Werkstatt, Kosten, Datum und Notiz auf dem Tablet",
    "Echte Tablet-Vorschau eines in der App erstellten Fahrzeugprotokolls als PDF",
]


def verify_source(aab, apk):
    """Check the pinned release and all APK runtime payloads against its bundle."""
    if hashlib.sha256(aab.read_bytes()).hexdigest() != EXPECTED_AAB_SHA256:
        raise ValueError("Expected the reviewed Store AAB 1.0.0 build 3")
    verify_payloads(aab, apk)
    aapt = Path("/home/unknown/.local/android-sdk/build-tools/35.0.0/aapt")
    badging = subprocess.check_output([str(aapt), "dump", "badging", str(apk)], text=True)
    if "package: name='com.appfactory.vehicle_log' versionCode='3' versionName='1.0.0'" not in badging:
        raise ValueError("Unexpected capture package/version")
    if "application-debuggable" in badging:
        raise ValueError("Capture APK must be a release")
    return hashlib.sha256(apk.read_bytes()).hexdigest()


def verify_payloads(aab, apk):
    with zipfile.ZipFile(aab) as bundle, zipfile.ZipFile(apk) as installed:
        # bundletool adds these ART optimization profiles from bundle metadata.
        generated_profiles = {"assets/dexopt/baseline.prof", "assets/dexopt/baseline.profm"}
        names = [n for n in installed.namelist() if n.startswith(("assets/", "lib/"))
                 and not n.endswith("/") and n not in generated_profiles]
        expected = {n.removeprefix("base/") for n in bundle.namelist()
                    if n.startswith(("base/assets/", "base/lib/")) and not n.endswith("/")}
        if not names or set(names) != expected:
            raise ValueError("Missing or unexpected runtime assets/libraries")
        for name in names:
            if installed.read(name) != bundle.read("base/" + name):
                raise ValueError(f"Runtime payload differs from Store AAB: {name}")


def png_info(path, *, icon=False):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"Not a PNG: {path}")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    if depth != 8 or color != (6 if icon else 2):
        raise ValueError(f"Unexpected PNG bit depth or color mode: {path}")
    # Decode the complete image, rejecting truncated PNGs and corrupt payloads.
    subprocess.run(["convert", "-regard-warnings", str(path), "null:"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if icon:
        opaque = subprocess.check_output(["identify", "-format", "%[opaque]", str(path)])
        if opaque.strip().lower() != b"true":
            raise ValueError(f"Icon background must be fully opaque: {path}")
    return width, height, len(data), hashlib.sha256(data).hexdigest()


def validate(root):
    specs = {
        "icon": (1, (512, 512), 1_000_000),
        "feature": (1, (1024, 500), 15_000_000),
        "phone": (8, (1080, 1920), 8_000_000),
        "tablet7": (4, (1920, 1080), 8_000_000),
        "tablet10": (4, (2560, 1440), 8_000_000),
    }
    entries = []
    for group, (count, size, limit) in specs.items():
        paths = sorted((root / group).glob("*.png"))
        if len(paths) != count:
            raise ValueError(f"{group}: expected {count} images, got {len(paths)}")
        for index, path in enumerate(paths):
            width, height, length, digest = png_info(path, icon=group == "icon")
            if (width, height) != size or length > limit:
                raise ValueError(f"Dimensions/size outside specification: {path}")
            alt = (PHONE_ALT[index] if group == "phone" else
                   TABLET_ALT[index] if group.startswith("tablet") else
                   "Fahrzeugakte: Wartungen festhalten. Belege griffbereit." if group == "feature"
                   else "Fahrzeugakte App-Icon")
            if len(alt) > 140:
                raise ValueError("Alt text exceeds 140 characters")
            entries.append(dict(file=str(path.relative_to(root)), width=width,
                                height=height, bytes=length, sha256=digest, alt=alt))
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--aab", type=Path, required=True)
    args = parser.parse_args()
    digest = verify_source(args.aab, args.apk)
    entries = validate(args.output)
    photos = [{"file": p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
              for p in sorted(Path("assets/store_demo").glob("*.png"))]
    manifest = dict(
        source_aab=args.aab.name, aab_sha256=EXPECTED_AAB_SHA256,
        source_apk=args.apk.name, apk_sha256=digest,
        source_commit="c317a036daaae90580fba386c9ffd23ff0105471",
        package="com.appfactory.vehicle_log", version="1.0.0+3",
        source="Existing Store AAB extracted with bundletool. Release runtime payloads match byte for byte. Local emulator APK uses bundletool debug signing",
        captures="API 35, German app UI, light theme, Europe/Berlin. Phone 1080x1920 at 320 dpi. Tablet7 1920x1080 at 240 dpi. Tablet10 2560x1440 at 288 dpi",
        demo="4 fictional vehicles, 32 past entries, 5 generated photos, 2 PDF documents marked MUSTER. Imported through the app encrypted backup flow",
        photo_generator="Built-in imagegen. Prompts in assets/store_demo/prompts.json",
        pdf_previews="Phone: history with attachments. Tablets: compact history without attachments",
        capture_finding="High-resolution tablet preview with attachments exceeded the emulator's 192 MiB app heap. See docs/STORE_CAPTURE_FINDINGS.md",
        photo_sources=photos, assets=entries,
    )
    (args.output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    readme = """# Fahrzeugakte – Play-Store-Bilder

Die 18 PNG-Dateien sind fertig für den Upload. Video kannst du leer lassen.

## In der Play Console zuordnen

| Feld | Ordner / Datei |
| --- | --- |
| App icon | `icon/app-icon.png` |
| Feature graphic | `feature/feature-graphic.png` |
| Phone screenshots | `phone/01.png` bis `08.png`, in dieser Reihenfolge |
| 7-inch tablet screenshots | alle vier PNGs aus `tablet7`, nach Dateinamen sortiert |
| 10-inch tablet screenshots | alle vier PNGs aus `tablet10`, nach Dateinamen sortiert |

`VORSCHAU.png` ist nur die Gesamtübersicht und nicht zum Store-Upload bestimmt.
`raw/` enthält Arbeitsmaterial. Das ZIP enthält ausschließlich die 18 fertigen
Upload-Bilder, diese Anleitung, das Prüfmanifest und die Gesamtübersicht.

## Herkunft

Echte Screenshots des vorhandenen Store-Releases 1.0.0+3 aus Commit
`c317a036daaae90580fba386c9ffd23ff0105471` im eigenen Android-35-Emulator.
Die APK wurde mit bundletool aus der vorhandenen AAB extrahiert und nur für
diesen Emulator lokal signiert. Laufzeitdateien und Assets stimmen bytegenau
mit der AAB überein. Kein Flutter-Neubau und kein neuer Release.
Das private Smartphone wurde nicht benutzt. Es wurde nichts hochgeladen.

Smartphone-Bilder zeigen vollständige, proportional skalierte App-Aufnahmen
unter einer Überschrift. Die beiden Tablet-Reihen wurden separat in echter
Tablet-Geometrie aufgenommen. Sie enthalten keine Werbeüberschriften.
Die Statusleiste verwendet den Android-Demomodus mit 09:41 Uhr.
Keine App-Inhalte wurden nachgebaut, übermalt oder aus Screenshots entfernt.

Pkw, Liefer-Lkw, Motorrad und E-Scooter sowie alle Einträge sind erfundene
Beispiele. Fünf Fahrzeugfotos wurden mit dem eingebauten imagegen-Werkzeug
erzeugt. Die Quellen und Prompts liegen unter `assets/store_demo/`.
Die zwei PDF-Belege sind ausdrücklich als MUSTER gekennzeichnet.
Das reguläre verschlüsselte Demo-Backup wurde in der echten App importiert.
Die PDF-Vorschau zeigt ein tatsächlich dort erzeugtes Fahrzeugprotokoll.
Die Tablet-Aufnahmen zeigen die reguläre Variante „Kompakt ohne Anhänge“.
Ein Speicherabsturz bei der hochauflösenden Vorschau mit Anhängen ist im
Projekt unter `docs/STORE_CAPTURE_FINDINGS.md` dokumentiert.

Das Icon ist PNG32 mit vollständig deckendem Hintergrund. Alle übrigen
Upload-Bilder sind PNG24 ohne Transparenz. Maße, Dateigrößen, SHA-256 und
deutsche Alt-Texte stehen im Prüfmanifest.

## Bildbeschreibungen für die Play Console

"""
    readme += "\n".join(f"{e['file']}\n{e['alt']}\n" for e in entries)
    (args.output / "README.md").write_text(readme)
    archive = args.output / "fahrzeugakte-play-store-bilder.zip"
    files = [entry["file"] for entry in entries] + ["README.md", "manifest.json", "VORSCHAU.png"]
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as result:
        for relative in files:
            path = args.output / relative
            if not path.is_file():
                raise ValueError(f"Missing delivery file: {path}")
            result.write(path, relative)
    with zipfile.ZipFile(archive) as result:
        if result.testzip() is not None or set(result.namelist()) != set(files):
            raise ValueError("Archive verification failed")
    print(f"Validated {len(entries)} upload images. Largest: {max(e['bytes'] for e in entries):,} bytes")
    print(archive)


if __name__ == "__main__":
    main()
