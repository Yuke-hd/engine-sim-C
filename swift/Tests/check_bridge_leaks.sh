#!/bin/bash
# macOS native lifecycle check, independent of XCTest's retained allocations.
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build
bin_path=$(swift build --show-bin-path)
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
objects=()
while IFS= read -r -d '' object; do objects+=("$object"); done < <(
    find "$bin_path/EngineSimCore.build" -name '*.o' -print0
)
clang++ -std=c++17 -I swift/include \
    swift/Tests/BridgeLifecycle/main.cpp "${objects[@]}" -o "$probe_dir/lifecycle"
leaks --atExit -- "$probe_dir/lifecycle"
