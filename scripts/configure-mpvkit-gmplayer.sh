#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="$root/MPVKit/Package.swift"
sources="$root/MPVKit/Sources/GMPlayerFork"

rm -rf "$sources"
mkdir -p "$sources"
cp -R "$root/Vendor/GMPlayerKit/." "$sources/"

python3 - "$package" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

if 'name: "GMPlayerKit"' in text:
    raise SystemExit(0)

product_anchor = '''        .library(
            name: "MPVKit-GPL",
            targets: ["_MPVKit-GPL"]
        ),
'''
product = product_anchor + '''        .library(
            name: "GMPlayerKit",
            targets: ["GMPlayerKit"]
        ),
'''

target_anchor = '''
        .binaryTarget(
            name: "Libmpv-GPL",
'''
targets = '''
        .target(
            name: "CGMTimestamp",
            path: "Sources/GMPlayerFork/CGMTimestamp",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CFFmpeg",
            dependencies: ["Libavcodec", "Libavformat", "Libavutil", "Libdovi", "CGMTimestamp"],
            path: "Sources/GMPlayerFork/CFFmpeg",
            sources: ["compat.c", "dovi.c", "probe.c", "remux.c"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"), .linkedLibrary("bz2"), .linkedLibrary("iconv"),
                .linkedFramework("CoreFoundation"), .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"), .linkedFramework("VideoToolbox"),
                .linkedFramework("AudioToolbox"), .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "CGMStream",
            dependencies: ["Libavcodec", "Libavformat", "Libavutil", "Libdovi", "CGMTimestamp", "CFFmpeg"],
            path: "Sources/GMPlayerFork/CGMStream",
            publicHeadersPath: "include"
        ),
        .target(
            name: "GMPlayerKit",
            dependencies: ["CFFmpeg", "CGMStream"],
            path: "Sources/GMPlayerFork/GMPlayerKit"
        ),
''' + target_anchor

if product_anchor not in text or target_anchor not in text:
    raise SystemExit("MPVKit manifest layout changed")
text = text.replace(product_anchor, product, 1).replace(target_anchor, targets, 1)
path.write_text(text)
PY
