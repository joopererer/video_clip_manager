"""Stage 3 UI Automation probe: dump the accessibility tree of the running fixture app.

Usage: VCM_STAGE=stage3 python tool/stage3_uia_probe.py [out_file]
Reads the pid from capture-session.json (written by stage2_desktop_capture.py launch).
Used to prove which screen is actually showing before any screenshot is accepted.
"""
import json
import os
import sys
from pathlib import Path

from pywinauto import Application

ROOT = Path(__file__).resolve().parents[1]
STAGE = os.environ.get("VCM_STAGE", "stage3")
STATE = ROOT / f"docs/ui-upgrade/logs/{STAGE}/capture-session.json"


def main():
    data = json.loads(STATE.read_text(encoding="utf-8"))
    app = Application(backend="uia").connect(process=data["pid"])
    window = app.top_window()
    lines = []
    for item in window.descendants():
        info = item.element_info
        name = (info.name or "").replace("\n", " ")
        if name:
            r = item.rectangle()
            lines.append(f"{info.control_type}\t{name}\t{r.left},{r.top},{r.right},{r.bottom}")
    text = "\n".join(lines)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
