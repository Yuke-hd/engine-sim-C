#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
swift build -c release --scratch-path "$probe_dir/build"
bin_path=$(swift build -c release --show-bin-path --scratch-path "$probe_dir/build")
objects=()
while IFS= read -r -d '' object; do objects+=("$object"); done < <(
    find "$bin_path/EngineSimCore.build" -name '*.o' -print0
)
clang++ -std=c++17 -DNDEBUG -include string.h -fdelayed-template-parsing \
    -D__forceinline=inline -I include -I swift -I swift/include \
    swift/Tests/ForceGuard/main.cpp "${objects[@]}" -o "$probe_dir/force_guard"
"$probe_dir/force_guard"
