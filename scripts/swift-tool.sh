#!/bin/bash
# Keep compiler caches local and support the standalone Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-modules"
command="${1:?Expected build or test}"
shift
args=(--build-system native --disable-sandbox --cache-path "$PWD/.build/pm-cache" --config-path "$PWD/.build/pm-config" --security-path "$PWD/.build/pm-security")
if [[ "$command" == "test" ]]; then
    dev_dir="$(xcode-select -p)"
    framework_dir="$dev_dir/Library/Developer/Frameworks"
    if [[ -d "$framework_dir/Testing.framework" ]]; then
        args+=(--disable-xctest -Xswiftc -F -Xswiftc "$framework_dir"
            -Xswiftc -plugin-path -Xswiftc "$dev_dir/usr/lib/swift/host/plugins/testing"
            -Xlinker -F -Xlinker "$framework_dir" -Xlinker -rpath -Xlinker "$framework_dir")
    else
        args+=(--disable-xctest)
    fi
fi
exec swift "$command" "${args[@]}" "$@"
