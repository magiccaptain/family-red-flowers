#!/usr/bin/env python3
"""Render Android and Linux icons from the same small red flower SVG."""
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/icon.svg"
RES = ROOT / "android/app/src/main/res"
ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)


def render(size, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "--width", str(size), "--height", str(size),
                    "--output", str(destination), str(SOURCE)], check=True)


def android_attr(name):
    return f"{{{ANDROID_NS}}}{name}"


def write_xml(element, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(element)
    ET.ElementTree(element).write(destination, encoding="utf-8", xml_declaration=True)


def main():
    if not shutil.which("rsvg-convert"):
        raise SystemExit("Please install librsvg2-bin to render the shared SVG icon.")
    render(512, ROOT / "assets/icon.png")
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                          "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(size, RES / f"mipmap-{density}/ic_launcher.png")

    svg = ET.parse(SOURCE).getroot()
    background = next(e for e in svg if e.tag.endswith("}rect")).attrib["fill"]
    vector = ET.Element("vector", {
        android_attr("width"): "108dp", android_attr("height"): "108dp",
        android_attr("viewportWidth"): "108", android_attr("viewportHeight"): "108",
    })
    group = ET.SubElement(vector, "group", {
        android_attr("scaleX"): "0.140625", android_attr("scaleY"): "0.140625",
        android_attr("translateX"): "18", android_attr("translateY"): "18",
    })

    def shapes(element, inherited_fill="#000000"):
        fill = element.attrib.get("fill", inherited_fill)
        tag = element.tag.rsplit("}", 1)[-1]
        if tag == "circle":
            x, y, r = (float(element.attrib[k]) for k in ("cx", "cy", "r"))
            path = (f"M{x-r:g},{y:g} A{r:g},{r:g} 0,1,0 {x+r:g},{y:g} "
                    f"A{r:g},{r:g} 0,1,0 {x-r:g},{y:g} Z")
        elif tag == "path":
            path = element.attrib["d"]
        else:
            for child in element:
                shapes(child, fill)
            return
        attrs = {android_attr("pathData"): path,
                 android_attr("fillColor"): "#00000000" if fill == "none" else fill}
        for svg_name, android_name in (("stroke", "strokeColor"),
                                       ("stroke-width", "strokeWidth"),
                                       ("stroke-linecap", "strokeLineCap")):
            if svg_name in element.attrib:
                attrs[android_attr(android_name)] = element.attrib[svg_name]
        ET.SubElement(group, "path", attrs)

    shapes(svg)
    write_xml(vector, RES / "drawable/ic_launcher_foreground.xml")
    colors = ET.Element("resources")
    ET.SubElement(colors, "color", {"name": "app_icon_background"}).text = background
    write_xml(colors, RES / "values/icon_colors.xml")
    adaptive = ET.Element("adaptive-icon")
    ET.SubElement(adaptive, "background", {android_attr("drawable"): "@color/app_icon_background"})
    ET.SubElement(adaptive, "foreground", {android_attr("drawable"): "@drawable/ic_launcher_foreground"})
    write_xml(adaptive, RES / "mipmap-anydpi-v26/ic_launcher.xml")
    print("Generated Android and Linux icons from assets/icon.svg")


if __name__ == "__main__":
    main()
