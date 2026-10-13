#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "CONFIGURATION must be release or debug" >&2
    exit 1
fi
./scripts/swift-tool.sh build -c "$configuration"
bin_dir="$(./scripts/swift-tool.sh build -c "$configuration" --show-bin-path)"
app="dist/JC2Mac.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/JC2Mac" "$app/Contents/MacOS/JC2Mac"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
# Finder can annotate a launched build; those attributes invalidate a subsequent signature.
xattr -cr "$app"
# The default app has NO restricted entitlements. Ad-hoc signing does not grant virtual HID access.
if [[ -n "${VIRTUAL_HID_PROFILE:-}" ]]; then
    if [[ -z "${SIGNING_IDENTITY:-}" || "$SIGNING_IDENTITY" == "-" ]]; then
        echo "VIRTUAL_HID_PROFILE requires an Apple-approved profile and a matching SIGNING_IDENTITY" >&2
        exit 1
    fi
    cp "$VIRTUAL_HID_PROFILE" "$app/Contents/embedded.provisionprofile"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" --entitlements Resources/VirtualHID.entitlements "$app"
else
    rm -f "$app/Contents/embedded.provisionprofile"
    codesign --force --sign "${SIGNING_IDENTITY:--}" "$app"
fi
codesign --verify --strict "$app"
echo "Built $PWD/$app"
