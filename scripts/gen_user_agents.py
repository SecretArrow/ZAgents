#!/usr/bin/env python3
"""Generates lib/data/user_agents.g.dart for ZAgents (v1.7.0+).

Builds a validated database of exactly 500 unique, realistic User-Agent
strings (250 desktop + 250 Android) from curated component pools.

Realism rules enforced here (and re-asserted in Dart tests):
  * every string follows the exact wire format of a real browser;
  * Edge/EdgA majors always equal their bundled Chromium major;
  * Samsung Internet majors use their real bundled Chromium major
    (25.0->119, 26.0->124, 27.0->125);
  * phone UAs carry the `Mobile` token, tablet UAs never do;
  * Android versions are plausible for each device model;
  * Firefox on macOS uses the dotted `Mac OS X 10.15` token while
    Chromium/Safari use `10_15_7` (exactly like the real browsers);
  * Firefox on Android never includes a device model (like the real app),
    so its uniqueness space is (Android version, rv);
  * no fabricated exotic vendors (no Huawei Chrome, etc.).

Run:  python3 scripts/gen_user_agents.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "lib" / "data" / "user_agents.g.dart"

# ----------------------------------------------------------------------------
# Component pools (real browser versions / real model codes only).
# ----------------------------------------------------------------------------

CHROME_MAJORS = list(range(120, 144))            # 120..143 (real trains)
FIREFOX_MAJORS = list(range(124, 150))           # 124..149 (real trains)
# Apple Safari versions (real): 17.6 + the 18.x line + the 26.x line.
SAFARI_VERSIONS = [
    "17.6", "18.0", "18.1", "18.2", "18.3", "18.4", "18.5", "18.6",
    "26.0", "26.1", "26.2", "26.3", "26.4",
]
# Opera desktop pairs (Chromium major -> OPR major).
OPERA_PAIRS = {c: c - 20 for c in range(136, 144)}   # 136..143 -> 116..123
OPERA_MOBILE_OFFSET = 44                              # Chromium 130 -> OPR/86
# Samsung Internet -> bundled Chromium major (real pairings).
SAMSUNG_PAIRS = [(25.0, 119), (26.0, 124), (27.0, 125)]
# Vivaldi desktop versions (7.x line) with their Chromium base.
VIVALDI_PAIRS = [
    ("7.2.3621.50", 137),
    ("7.3.3635.7", 138),
    ("7.4.3684.55", 139),
    ("7.5.3735.41", 140),
    ("7.6.3787.50", 141),
]

WIN = "Windows NT 10.0; Win64; x64"        # Windows 10 and 11 both report 10.0
MAC_CHROMIUM = "Macintosh; Intel Mac OS X 10_15_7"   # Chromium/Safari token
MAC_FIREFOX = "Macintosh; Intel Mac OS X 10.15"      # Firefox token
LINUX = "X11; Linux x86_64"

# ----------------------------------------------------------------------------
# Android device pool: model token in UA -> (display name, allowed Android
# versions, kind). Real model codes only; Huawei is intentionally absent
# (Chrome does not ship there).
# ----------------------------------------------------------------------------

PHONE = "phone"
TABLET = "tablet"

ANDROID_DEVICES: dict[str, tuple[str, list[int], str]] = {
    # Samsung phones
    "SM-S928B": ("Samsung Galaxy S24 Ultra", [14, 15, 16], PHONE),
    "SM-S926B": ("Samsung Galaxy S24+", [14, 15, 16], PHONE),
    "SM-S921B": ("Samsung Galaxy S24", [14, 15, 16], PHONE),
    "SM-S918B": ("Samsung Galaxy S23 Ultra", [14, 15], PHONE),
    "SM-S911B": ("Samsung Galaxy S23", [14, 15], PHONE),
    "SM-A556B": ("Samsung Galaxy A55 5G", [14, 15], PHONE),
    "SM-A546B": ("Samsung Galaxy A54 5G", [13, 14, 15], PHONE),
    "SM-A346B": ("Samsung Galaxy A34 5G", [13, 14, 15], PHONE),
    # Google
    "Pixel 9 Pro": ("Google Pixel 9 Pro", [14, 15, 16], PHONE),
    "Pixel 9": ("Google Pixel 9", [14, 15, 16], PHONE),
    "Pixel 9a": ("Google Pixel 9a", [15, 16], PHONE),
    "Pixel 8 Pro": ("Google Pixel 8 Pro", [14, 15, 16], PHONE),
    "Pixel 8": ("Google Pixel 8", [14, 15, 16], PHONE),
    "Pixel 8a": ("Google Pixel 8a", [14, 15, 16], PHONE),
    "Pixel 7 Pro": ("Google Pixel 7 Pro", [13, 14, 15], PHONE),
    "Pixel 7": ("Google Pixel 7", [13, 14, 15], PHONE),
    "Pixel 7a": ("Google Pixel 7a", [13, 14, 15], PHONE),
    "Pixel 6a": ("Google Pixel 6a", [13, 14, 15], PHONE),
    # Xiaomi / Redmi (global model codes)
    "23021RAAEG": ("Xiaomi Redmi Note 12 5G", [13, 14], PHONE),
    "M2101K6G": ("Xiaomi Redmi Note 10 5G", [13, 14], PHONE),
    "2201117TY": ("Xiaomi Redmi 10C", [13, 14], PHONE),
    # OPPO / vivo / realme / OnePlus / Motorola / Nothing / Infinix / TECNO
    "CPH2451": ("OPPO Reno8 Pro 5G", [13, 14], PHONE),
    "CPH2519": ("OPPO Find N2 Flip", [13, 14], PHONE),
    "V2227": ("vivo X90 Pro", [13, 14], PHONE),
    "V2249": ("vivo V25", [13, 14], PHONE),
    "RMX3521": ("realme GT Neo 3", [13, 14], PHONE),
    "RMX3771": ("realme 11 Pro 5G", [13, 14], PHONE),
    "CPH2449": ("OnePlus 11 5G", [13, 14, 15], PHONE),
    "CPH2557": ("OnePlus 12R 5G", [14, 15], PHONE),
    "LE2123": ("OnePlus 9 Pro 5G", [13, 14], PHONE),
    "XT2341-3": ("Motorola Moto G84 5G", [13, 14], PHONE),
    "XT2303-2": ("Motorola Edge 40", [13, 14, 15], PHONE),
    "A063": ("Nothing Phone (1)", [13, 14], PHONE),
    "Infinix X6819": ("Infinix Note 30", [13, 14], PHONE),
    "TECNO KI7": ("TECNO Spark 10", [13, 14], PHONE),
    # Tablets (their UA must NOT contain the Mobile token)
    "SM-X910": ("Samsung Galaxy Tab S9+", [14, 15], TABLET),
    "SM-X710": ("Samsung Galaxy Tab S9", [14, 15], TABLET),
    "SM-X210": ("Samsung Galaxy Tab A9+", [14, 15], TABLET),
    "SM-X200": ("Samsung Galaxy Tab A9", [14, 15], TABLET),
    "Pixel Tablet": ("Google Pixel Tablet", [14, 15], TABLET),
    "23043RP34G": ("Xiaomi Pad 6", [14, 15], TABLET),
}

SAMSUNG_PHONES = [
    m for m, v in ANDROID_DEVICES.items() if v[2] == PHONE and m.startswith("SM-")
]
ALL_PHONES = [m for m, v in ANDROID_DEVICES.items() if v[2] == PHONE]
TABLETS = [m for m, v in ANDROID_DEVICES.items() if v[2] == TABLET]

# ----------------------------------------------------------------------------
# Records
# ----------------------------------------------------------------------------

records: list[dict] = []  # {id, category, browser, label, ua}
_seen: set[str] = set()


def add(category: str, browser: str, label: str, ua: str) -> None:
    if ua in _seen:
        sys.exit(f"FATAL: duplicate UA produced: {ua}")
    _seen.add(ua)
    records.append(
        {
            "id": len(records) + 1,
            "category": category,
            "browser": browser,
            "label": label,
            "ua": ua,
        }
    )


def chromium_ua(platform: str, chrome: int, extra: str = "") -> str:
    tail = f" {extra}" if extra else ""
    return (
        f"Mozilla/5.0 ({platform}) AppleWebKit/537.36 (KHTML, like Gecko) "
        f"Chrome/{chrome}.0.0.0 Safari/537.36{tail}"
    )


def firefox_desktop_ua(platform_dots: str, version: str) -> str:
    return (
        f"Mozilla/5.0 ({platform_dots}; rv:{version.split('.')[0]}.0) "
        f"Gecko/20100101 Firefox/{version}"
    )


def android_ua(model: str, android: int, chrome: int, extra: str = "") -> str:
    kind = ANDROID_DEVICES[model][2]
    mobile = "Mobile " if kind == PHONE else ""
    tail = f" {extra}" if extra else ""
    return (
        f"Mozilla/5.0 (Linux; Android {android}; {model}) AppleWebKit/537.36 "
        f"(KHTML, like Gecko) Chrome/{chrome}.0.0.0 {mobile}Safari/537.36{tail}"
    )


def interleave(groups):
    """Round-robin across per-model combo lists for a natural spread."""
    out = []
    idx = 0
    total = sum(len(g) for g in groups)
    while len(out) < total:
        for g in groups:
            if idx < len(g):
                out.append(g[idx])
        idx += 1
    return out


# ----------------------------- DESKTOP (250) --------------------------------

# Chrome desktop — 68
for major in CHROME_MAJORS:                    # 24 Windows
    add("desktop", "chrome", f"Chrome {major} · Windows 10/11", chromium_ua(WIN, major))
for major in CHROME_MAJORS:                    # 24 macOS
    add("desktop", "chrome", f"Chrome {major} · macOS", chromium_ua(MAC_CHROMIUM, major))
for major in range(120, 140):                  # 20 Linux
    add("desktop", "chrome", f"Chrome {major} · Linux", chromium_ua(LINUX, major))

# Edge desktop — 44 (Edge major always equals its Chromium major)
for major in CHROME_MAJORS:                    # 24 Windows
    add("desktop", "edge", f"Edge {major} · Windows 10/11",
        chromium_ua(WIN, major, f"Edg/{major}.0.0.0"))
for major in range(134, 144):                  # 10 macOS
    add("desktop", "edge", f"Edge {major} · macOS",
        chromium_ua(MAC_CHROMIUM, major, f"Edg/{major}.0.0.0"))
for major in range(134, 144):                  # 10 Linux
    add("desktop", "edge", f"Edge {major} · Linux",
        chromium_ua(LINUX, major, f"Edg/{major}.0.0.0"))

# Firefox desktop — 104 (point releases are real: Firefox ships .0.1 fixes)
for major in FIREFOX_MAJORS:                   # 52 Windows (.0 / .0.1)
    add("desktop", "firefox", f"Firefox {major}.0 · Windows 10/11",
        firefox_desktop_ua(WIN, f"{major}.0"))
    add("desktop", "firefox", f"Firefox {major}.0.1 · Windows 10/11",
        firefox_desktop_ua(WIN, f"{major}.0.1"))
for major in FIREFOX_MAJORS:                   # 26 macOS
    add("desktop", "firefox", f"Firefox {major}.0 · macOS",
        firefox_desktop_ua(MAC_FIREFOX, f"{major}.0"))
for major in FIREFOX_MAJORS:                   # 26 Linux
    add("desktop", "firefox", f"Firefox {major}.0 · Linux",
        firefox_desktop_ua(LINUX, f"{major}.0"))

# Safari macOS — 13 (Safari still reports 10_15_7)
for v in SAFARI_VERSIONS:
    add("desktop", "safari", f"Safari {v} · macOS",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        f"(KHTML, like Gecko) Version/{v} Safari/605.1.15")

# Opera desktop — 14 (OPR bundles a specific Chromium)
for chrome, opr in sorted(OPERA_PAIRS.items()):          # 8 Windows
    add("desktop", "opera", f"Opera {opr} (Chromium {chrome}) · Windows 10/11",
        chromium_ua(WIN, chrome, f"OPR/{opr}.0.0.0"))
for chrome, opr in sorted(OPERA_PAIRS.items())[2:]:      # 6 macOS
    add("desktop", "opera", f"Opera {opr} (Chromium {chrome}) · macOS",
        chromium_ua(MAC_CHROMIUM, chrome, f"OPR/{opr}.0.0.0"))

# Vivaldi desktop — 7
for vivaldi, chrome in VIVALDI_PAIRS:                    # 5 Windows
    short = ".".join(vivaldi.split(".")[:2])
    add("desktop", "vivaldi", f"Vivaldi {short} · Windows 10/11",
        chromium_ua(WIN, chrome, f"Vivaldi/{vivaldi}"))
for vivaldi, chrome in VIVALDI_PAIRS[3:]:                # 2 macOS
    short = ".".join(vivaldi.split(".")[:2])
    add("desktop", "vivaldi", f"Vivaldi {short} · macOS",
        chromium_ua(MAC_CHROMIUM, chrome, f"Vivaldi/{vivaldi}"))

assert len(records) == 250, f"desktop count = {len(records)}"

# ----------------------------- ANDROID (250) ---------------------------------

android_before = len(records)

# Chrome phone — 120: round-robin over every phone model.
groups = []
for model in ALL_PHONES:
    androids = ANDROID_DEVICES[model][1]
    combos = [
        (model, androids[i % len(androids)], CHROME_MAJORS[(i * 7) % len(CHROME_MAJORS)])
        for i in range(24 * len(androids))
    ]
    groups.append(combos)
seen_combo: set[tuple] = set()
for model, android, chrome in interleave(groups)[:120]:
    guard = 0
    while (model, android, chrome) in seen_combo:
        guard += 1
        if guard > len(CHROME_MAJORS):
            sys.exit("FATAL: could not dedupe chrome phone pool")
        chrome = CHROME_MAJORS[(CHROME_MAJORS.index(chrome) + 1) % len(CHROME_MAJORS)]
    seen_combo.add((model, android, chrome))
    name = ANDROID_DEVICES[model][0]
    add("android", "chrome", f"Chrome {chrome} · {name} (Android {android})",
        android_ua(model, android, chrome))

# Samsung Internet — 40 (real bundled Chromium majors).
groups = []
for model in SAMSUNG_PHONES:
    combos = [
        (model, android, sb)
        for android in ANDROID_DEVICES[model][1]
        for sb, _ in SAMSUNG_PAIRS
    ]
    groups.append(combos)
samsung_chrome = {int(s): c for s, c in SAMSUNG_PAIRS}
for model, android, sb in interleave(groups)[:40]:
    chrome = samsung_chrome[int(sb)]
    name = ANDROID_DEVICES[model][0]
    add("android", "samsungInternet",
        f"Samsung Internet {sb:.0f} · {name} (Android {android})",
        f"Mozilla/5.0 (Linux; Android {android}; {model}) AppleWebKit/537.36 "
        f"(KHTML, like Gecko) SamsungBrowser/{sb:.0f}.0 Chrome/{chrome}.0.0.0 "
        f"Mobile Safari/537.36")

# Chrome tablet — 20: no Mobile token (exactly like real Android tablets).
groups = []
for model in TABLETS:
    androids = ANDROID_DEVICES[model][1]
    combos = [
        (model, androids[i % len(androids)], CHROME_MAJORS[(i * 5) % len(CHROME_MAJORS)])
        for i in range(24 * len(androids))
    ]
    groups.append(combos)
seen_combo.clear()
for model, android, chrome in interleave(groups)[:20]:
    guard = 0
    while (model, android, chrome) in seen_combo:
        guard += 1
        if guard > len(CHROME_MAJORS):
            sys.exit("FATAL: could not dedupe chrome tablet pool")
        chrome = CHROME_MAJORS[(CHROME_MAJORS.index(chrome) + 1) % len(CHROME_MAJORS)]
    seen_combo.add((model, android, chrome))
    name = ANDROID_DEVICES[model][0]
    add("android", "chrome", f"Chrome {chrome} · {name} (Android {android})",
        android_ua(model, android, chrome))

# Firefox Android — 30 (24 phone + 6 tablet, real Gecko format).
# NOTE: Firefox on Android does NOT put the device model in its UA, so the
# uniqueness space is (Android version, rv). Labels name a plausible
# representative device for each Android version.
FF_PHONE_MODEL = {13: "Pixel 7", 14: "Pixel 8", 15: "Pixel 9", 16: "Pixel 9 Pro"}
count = 0
for rv in FIREFOX_MAJORS:
    if count >= 24:
        break
    for android in (13, 14, 15, 16):
        if count >= 24:
            break
        model = FF_PHONE_MODEL[android]
        name = ANDROID_DEVICES[model][0]
        add("android", "firefox", f"Firefox {rv} · {name} (Android {android})",
            f"Mozilla/5.0 (Android {android}; Mobile; rv:{rv}.0) Gecko/{rv}.0 "
            f"Firefox/{rv}.0")
        count += 1
assert count == 24, f"firefox phone = {count}"
FF_TABLET_MODEL = {14: "SM-X910", 15: "Pixel Tablet"}
count = 0
for rv in FIREFOX_MAJORS:
    if count >= 6:
        break
    for android in (14, 15):
        if count >= 6:
            break
        model = FF_TABLET_MODEL[android]
        name = ANDROID_DEVICES[model][0]
        add("android", "firefox", f"Firefox {rv} · {name} (Android {android})",
            f"Mozilla/5.0 (Android {android}; Tablet; rv:{rv}.0) Gecko/{rv}.0 "
            f"Firefox/{rv}.0")
        count += 1
assert count == 6, f"firefox tablet = {count}"

# Edge Android — 20 (EdgA major == Chromium major).
edge_models = [
    "SM-S921B", "Pixel 8 Pro", "SM-A546B", "Pixel 7", "CPH2451",
    "V2249", "RMX3771", "CPH2449", "Pixel 8a", "SM-A556B",
]
groups = []
for model in edge_models:
    androids = ANDROID_DEVICES[model][1]
    combos = [
        (model, androids[i % len(androids)], CHROME_MAJORS[(i * 3) % len(CHROME_MAJORS)])
        for i in range(24 * len(androids))
    ]
    groups.append(combos)
for model, android, chrome in interleave(groups)[:20]:
    name = ANDROID_DEVICES[model][0]
    add("android", "edge", f"Edge {chrome} · {name} (Android {android})",
        android_ua(model, android, chrome, f"EdgA/{chrome}.0.0.0"))

# Opera Mobile — 20 (OPR = Chromium - 44, real-world offset).
opera_models = [
    "SM-S928B", "Pixel 9", "SM-A346B", "Pixel 7a", "23021RAAEG",
    "CPH2519", "RMX3521", "XT2303-2", "V2227", "Pixel 6a",
]
groups = []
for model in opera_models:
    androids = ANDROID_DEVICES[model][1]
    combos = [
        (model, androids[i % len(androids)], CHROME_MAJORS[(i * 5) % len(CHROME_MAJORS)])
        for i in range(24 * len(androids))
    ]
    groups.append(combos)
for model, android, chrome in interleave(groups)[:20]:
    opr = chrome - OPERA_MOBILE_OFFSET
    name = ANDROID_DEVICES[model][0]
    add("android", "opera", f"Opera {opr} · {name} (Android {android})",
        android_ua(model, android, chrome, f"OPR/{opr}.0.0.0"))

android_count = len(records) - android_before
assert android_count == 250, f"android count = {android_count}"

# ----------------------------------------------------------------------------
# Validation (mirrored in test/unit/user_agent_test.dart)
# ----------------------------------------------------------------------------

R_CHROME_DESKTOP = re.compile(
    r"^Mozilla/5\.0 \((?P<plat>Windows NT 10\.0; Win64; x64|Macintosh; "
    r"Intel Mac OS X 10_15_7|X11; Linux x86_64)\) AppleWebKit/537\.36 "
    r"\(KHTML, like Gecko\) Chrome/(?P<c>\d+)\.0\.0\.0 Safari/537\.36"
)
R_EDGE_DESKTOP = re.compile(R_CHROME_DESKTOP.pattern + r" Edg/(?P<e>\d+)\.0\.0\.0$")
R_FIREFOX_DESKTOP = re.compile(
    r"^Mozilla/5\.0 \((?P<plat>Windows NT 10\.0; Win64; x64|Macintosh; "
    r"Intel Mac OS X 10\.15|X11; Linux x86_64); rv:\d+\.0\) Gecko/20100101 "
    r"Firefox/\d+\.\d+(\.\d+)?$"
)
R_SAFARI = re.compile(
    r"^Mozilla/5\.0 \(Macintosh; Intel Mac OS X 10_15_7\) "
    r"AppleWebKit/605\.1\.15 \(KHTML, like Gecko\) Version/\d+\.\d+ "
    r"Safari/605\.1\.15$"
)
R_OPERA_DESKTOP = re.compile(R_CHROME_DESKTOP.pattern + r" OPR/(?P<o>\d+)\.0\.0\.0$")
R_VIVALDI_DESKTOP = re.compile(
    R_CHROME_DESKTOP.pattern + r" Vivaldi/\d+\.\d+\.\d+\.\d+$"
)
R_CHROME_ANDROID = re.compile(
    r"^Mozilla/5\.0 \(Linux; Android (?P<a>\d+); (?P<model>[^)]+)\) "
    r"AppleWebKit/537\.36 \(KHTML, like Gecko\) Chrome/(?P<c>\d+)\.0\.0\.0 "
    r"(?P<mobile>Mobile )?Safari/537\.36$"
)
R_SAMSUNG = re.compile(
    r"^Mozilla/5\.0 \(Linux; Android (?P<a>\d+); (?P<model>SM-[^)]+)\) "
    r"AppleWebKit/537\.36 \(KHTML, like Gecko\) SamsungBrowser/(?P<s>\d+)\.0 "
    r"Chrome/(?P<c>\d+)\.0\.0\.0 Mobile Safari/537\.36$"
)
R_FIREFOX_ANDROID = re.compile(
    r"^Mozilla/5\.0 \(Android (?P<a>\d+); (?P<kind>Mobile|Tablet); "
    r"rv:(?P<rv>\d+)\.0\) Gecko/(?P=rv)\.0 Firefox/(?P<f>\d+)\.0$"
)
R_EDGE_ANDROID = re.compile(
    R_CHROME_ANDROID.pattern[:-1] + r" EdgA/(?P<e>\d+)\.0\.0\.0$"
)
R_OPERA_ANDROID = re.compile(
    R_CHROME_ANDROID.pattern[:-1] + r" OPR/(?P<o>\d+)\.0\.0\.0$"
)

SAMSUNG_CHROME_MAP = {int(s): c for s, c in SAMSUNG_PAIRS}

for r in records:
    ua = r["ua"]
    cat, browser = r["category"], r["browser"]
    if cat == "desktop":
        if browser == "chrome":
            assert R_CHROME_DESKTOP.match(ua), ua
        elif browser == "edge":
            m = R_EDGE_DESKTOP.match(ua)
            assert m and m.group("e") == m.group("c"), ua
        elif browser == "firefox":
            assert R_FIREFOX_DESKTOP.match(ua), ua
        elif browser == "safari":
            assert R_SAFARI.match(ua), ua
        elif browser == "opera":
            m = R_OPERA_DESKTOP.match(ua)
            assert m and OPERA_PAIRS.get(int(m.group("c"))) == int(m.group("o")), ua
        elif browser == "vivaldi":
            assert R_VIVALDI_DESKTOP.match(ua), ua
        else:
            sys.exit(f"unknown desktop browser {browser}")
    else:
        if browser == "chrome":
            m = R_CHROME_ANDROID.match(ua)
            assert m, ua
            model = m.group("model")
            assert model in ANDROID_DEVICES, f"unknown model: {ua}"
            kind = ANDROID_DEVICES[model][2]
            assert (m.group("mobile") == "Mobile ") == (kind == PHONE), ua
            assert int(m.group("a")) in ANDROID_DEVICES[model][1], ua
        elif browser == "samsungInternet":
            m = R_SAMSUNG.match(ua)
            assert m, ua
            assert SAMSUNG_CHROME_MAP[int(m.group("s"))] == int(m.group("c")), ua
            assert int(m.group("a")) in ANDROID_DEVICES[m.group("model")][1], ua
        elif browser == "firefox":
            m = R_FIREFOX_ANDROID.match(ua)
            assert m and m.group("f") == m.group("rv"), ua
        elif browser == "edge":
            m = R_EDGE_ANDROID.match(ua)
            assert m and m.group("e") == m.group("c"), ua
            assert m.group("mobile") == "Mobile ", ua
            assert int(m.group("a")) in ANDROID_DEVICES[m.group("model")][1], ua
        elif browser == "opera":
            m = R_OPERA_ANDROID.match(ua)
            assert m and int(m.group("o")) == int(m.group("c")) - OPERA_MOBILE_OFFSET, ua
            assert m.group("mobile") == "Mobile ", ua
            assert int(m.group("a")) in ANDROID_DEVICES[m.group("model")][1], ua
        else:
            sys.exit(f"unknown android browser {browser}")

assert len({r["ua"] for r in records}) == 500, "UA strings must be globally unique"
assert len({r["id"] for r in records}) == 500
assert sum(1 for r in records if r["category"] == "desktop") == 250
assert sum(1 for r in records if r["category"] == "android") == 250

# ----------------------------------------------------------------------------
# Emit Dart
# ----------------------------------------------------------------------------


def dart_str(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


BROWSER_ENUM = {
    "chrome": "UserAgentBrowser.chrome",
    "edge": "UserAgentBrowser.edge",
    "firefox": "UserAgentBrowser.firefox",
    "safari": "UserAgentBrowser.safari",
    "opera": "UserAgentBrowser.opera",
    "samsungInternet": "UserAgentBrowser.samsungInternet",
    "vivaldi": "UserAgentBrowser.vivaldi",
}

lines = [
    "// GENERATED FILE — do not edit by hand.",
    "// Regenerate with: python3 scripts/gen_user_agents.py",
    "//",
    "// Database of 500 unique, realistic User-Agent strings (250 desktop +",
    "// 250 Android) composed from curated pools of real browser versions and",
    "// real device model codes. Every entry is format-validated against the",
    "// wire format of the browser it represents (see scripts/gen_user_agents.py",
    "// and test/unit/user_agent_test.dart for the enforced rules).",
    "import '../models/user_agent.dart';",
    "",
    "/// 500 validated User-Agent records: 250 desktop + 250 Android.",
    "const List<UserAgentRecord> kUserAgentDatabase = <UserAgentRecord>[",
]
for r in records:
    lines.append(
        "  UserAgentRecord(\n"
        f"    id: {r['id']},\n"
        f"    category: UserAgentCategory.{r['category']},\n"
        f"    browser: {BROWSER_ENUM[r['browser']]},\n"
        f"    label: '{dart_str(r['label'])}',\n"
        f"    ua: '{dart_str(r['ua'])}',\n"
        "  ),"
    )
lines.append("];")
lines.append("")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(lines), encoding="utf-8")

by_family: dict[str, int] = {}
for r in records:
    key = f"{r['category']}/{r['browser']}"
    by_family[key] = by_family.get(key, 0) + 1
print(f"OK: wrote {len(records)} records to {OUT}")
for k in sorted(by_family):
    print(f"  {k}: {by_family[k]}")
