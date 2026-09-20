"""Real UI capture utilities. Always restricted to the dedicated emulator."""
from pathlib import Path
import re
import subprocess
import time

from device import Device


class Capture(Device):
    def dashboard(self):
        self.run("shell", "am", "force-stop", "com.appfactory.vehicle_log")
        self.run("shell", "am", "start", "-n", "com.appfactory.vehicle_log/.MainActivity")
        time.sleep(2)
        if not self.has("Familienauto") or not self.has("Liefer-Lkw"):
            raise ValueError("Import the synthetic Demo.fzbackup before capturing")

    def report(self, mode="Mit Fotos und PDFs"):
        self.tap("Fahrzeugprotokoll für den Fahrzeugverlauf erstellen")
        self.tap(mode)
        for _ in range(30):
            if self.has("Teilen"):
                time.sleep(2)
                return
            time.sleep(1)
        raise ValueError("Generated PDF preview did not open")

    def geometry(self, width, height, density):
        self.width, self.height = width, height
        self.run("shell", "wm", "size", f"{width}x{height}")
        self.run("shell", "wm", "density", str(density))
        self.run("shell", "cmd", "uimode", "night", "no")
        self.run("shell", "cmd", "alarm", "set-timezone", "Europe/Berlin")
        time.sleep(2)
        subprocess.run(["python3", str(Path(__file__).with_name("device.py")),
                        self.serial, "status"], check=True)

    def has(self, label):
        return any(n.get("text", "").startswith(label) or
                   n.get("content-desc", "").startswith(label) for n in self.nodes())

    def swipe(self, distance=None):
        distance = distance or int(self.height * .6)
        start = int(self.height * .84)
        self.run("shell", "input", "swipe", str(self.width // 2), str(start),
                 str(self.width // 2), str(max(int(self.height * .18), start - distance)), "450")
        time.sleep(.3)

    def scroll_pdf(self):
        # Stay inside the PDF viewport, above the fixed print/share actions.
        self.run("shell", "input", "swipe", str(self.width // 2), str(round(self.height * .72)),
                 str(self.width // 2), str(round(self.height * .18)), "450")
        time.sleep(.5)

    def reveal(self, label):
        for _ in range(16):
            if self.has(label):
                return
            self.swipe()
        raise ValueError(f"Could not reveal {label}")

    def align(self, label, top):
        previous_y = None
        for _ in range(12):
            node = next((n for n in self.nodes() if
                         n.get("content-desc", "").startswith(label) or
                         n.get("text", "").startswith(label)), None)
            if node is None:
                self.swipe()
                continue
            _, y, _, _ = map(int, re.findall(r"\d+", node.get("bounds")))
            # Android touch slop makes sub-32px gestures taps, not scrolling.
            # Also stop at the real end of the scrollable content.
            if y <= top + 32 or y == previous_y:
                return
            previous_y = y
            self.swipe(y - top)
        raise ValueError(f"Could not align {label}")

    def capture(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        time.sleep(1.5)
        path.write_bytes(self.run("exec-out", "screencap", "-p"))
        subprocess.run(["convert", str(path), f"PNG24:{path}"], check=True)
        print(path, flush=True)
