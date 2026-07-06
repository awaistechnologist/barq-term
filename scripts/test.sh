#!/bin/bash
# Run the Barq test suite.
#
# With Command Line Tools (no Xcode), Testing.framework lives outside the
# default search paths — this script wires it up so `scripts/test.sh` always
# works. Extra args are passed through (e.g. --filter VaultStoreTests).
set -euo pipefail
cd "$(dirname "$0")/.."

FLAGS=()
CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d "$CLT_FRAMEWORKS/Testing.framework" ]; then
    FLAGS=(
        -Xswiftc -F"$CLT_FRAMEWORKS"
        -Xlinker -F"$CLT_FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$CLT_LIB"
    )
fi

swift test "${FLAGS[@]}" "$@"
