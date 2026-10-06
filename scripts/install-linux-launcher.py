#!/usr/bin/env python3
"""Install this workspace's flower icon and launcher in the current user menu."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
APP_ID = "cn.familygarden.red_flowers"
DATA = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")


def exec_argument(value):
    escaped = str(value).replace("\\", "\\\\\\\\").replace('"', '\\\\"')
    escaped = escaped.replace("$", "\\\\$").replace("`", "\\\\`")
    return f'"{escaped}"'


def main():
    applications = DATA / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    for size in (48, 512):
        source = (ROOT / "assets/icon.png" if size == 512 else ROOT /
                  "android/app/src/main/res/mipmap-mdpi/ic_launcher.png")
        icon = DATA / f"icons/hicolor/{size}x{size}/apps/{APP_ID}.png"
        icon.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, icon)
    scalable = DATA / f"icons/hicolor/scalable/apps/{APP_ID}.svg"
    scalable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "assets/icon.svg", scalable)
    desktop = applications / f"{APP_ID}.desktop"
    desktop.write_text(
        "[Desktop Entry]\nType=Application\nName=小花园\n"
        "Comment=记录小朋友的小红花和成长\n"
        f"Exec=bash {exec_argument(ROOT / 'scripts/start-linux.sh')}\n"
        f"Icon={APP_ID}\nTerminal=false\nCategories=Education;\n"
        f"StartupWMClass={APP_ID}\nStartupNotify=true\n"
    )
    for command in (("update-desktop-database", str(applications)),
                    ("gtk-update-icon-cache", "--force", "--ignore-theme-index", str(DATA / "icons/hicolor")),
                    ("kbuildsycoca6", "--noincremental")):
        if shutil.which(command[0]):
            subprocess.run(command, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False)
    print("Installed 小花园 in the Linux application menu with the flower icon")


if __name__ == "__main__":
    main()
