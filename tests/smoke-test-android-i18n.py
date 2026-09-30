#!/usr/bin/env python3
"""Check Android Spanish/English resources and Kotlin string references."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android-app/app/src/main/res"
SOURCE = ROOT / "android-app/app/src"


def strings(path: Path) -> dict[str, str]:
    root = ET.parse(path).getroot()
    return {
        item.attrib["name"]: "".join(item.itertext())
        for item in root
        if item.tag == "string"
    }


def placeholders(value: str) -> list[str]:
    return sorted(re.findall(r"%(?:\d+\$)?[sd]|%%", value))


spanish = strings(RES / "values/strings.xml")
english = strings(RES / "values-en/strings.xml")
errors: list[str] = []

if set(spanish) != set(english):
    errors.append(
        "resource keys differ: "
        f"missing English={sorted(set(spanish) - set(english))}; "
        f"missing Spanish={sorted(set(english) - set(spanish))}"
    )
for key in set(spanish) & set(english):
    if placeholders(spanish[key]) != placeholders(english[key]):
        errors.append(f"format placeholders differ for {key}")

references: set[str] = set()
for path in SOURCE.rglob("*.kt"):
    references.update(re.findall(r"R\.string\.([A-Za-z0-9_]+)", path.read_text()))
missing_references = references - set(spanish)
if missing_references:
    errors.append(f"unresolved R.string references: {sorted(missing_references)}")

locale_root = ET.parse(RES / "xml/locales_config.xml").getroot()
declared_locales = {
    item.attrib["{http://schemas.android.com/apk/res/android}name"]
    for item in locale_root.findall("locale")
}
if declared_locales != {"en", "es"}:
    errors.append(f"locale config must declare en and es; found {sorted(declared_locales)}")

if errors:
    for error in errors:
        print(f"FAIL: {error}")
    sys.exit(1)

print(
    f"Android i18n OK: {len(spanish)} matching EN/ES strings, "
    f"{len(references)} resolved Kotlin references, locales en/es."
)
