#!/bin/sh

set -eu

usage() {
    echo "usage: ALLOW_ADHOC=1 $0 <TokenDesk.xcarchive>" >&2
    echo "Omit ALLOW_ADHOC for release acceptance with an Apple signing identity." >&2
    exit 64
}

fail() {
    echo "release archive verification failed: $*" >&2
    exit 1
}

archive_path=${1:-}
[ -n "$archive_path" ] || usage
[ $# -eq 1 ] || usage
[ -d "$archive_path" ] || fail "archive does not exist: $archive_path"

app_path="$archive_path/Products/Applications/TokenDesk.app"
info_plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/TokenDesk"
entitlements_file=$(mktemp "${TMPDIR:-/tmp}/tokendesk-entitlements.XXXXXX")
trap 'rm -f "$entitlements_file"' EXIT HUP INT TERM

[ -d "$app_path" ] || fail "TokenDesk.app is missing"
[ -f "$info_plist" ] || fail "Info.plist is missing"
[ -x "$executable" ] || fail "main executable is missing or not executable"

codesign --verify --deep --strict --verbose=2 "$app_path"

signature_details=$(codesign -dvv "$app_path" 2>&1)
if printf '%s\n' "$signature_details" | grep -Fq 'Signature=adhoc'; then
    [ "${ALLOW_ADHOC:-0}" = 1 ] || fail "ad-hoc signature is not release acceptance"
    signing_kind="ad-hoc (development evidence only)"
else
    printf '%s\n' "$signature_details" | grep -Eq '^Authority=(Apple Development|Apple Distribution):' \
        || fail "signature is not from an accepted Apple application identity"
    signing_kind=$(printf '%s\n' "$signature_details" | sed -n 's/^Authority=//p' | head -n 1)
fi

codesign -d --xml --entitlements - "$app_path" >"$entitlements_file" 2>/dev/null \
    || fail "could not extract signed entitlements"
plutil -lint "$entitlements_file" >/dev/null

required_entitlements='com.apple.security.app-sandbox
com.apple.security.files.user-selected.read-write
com.apple.security.network.client
com.apple.security.personal-information.location'
printf '%s\n' "$required_entitlements" | while IFS= read -r entitlement; do
    value=$(
        /usr/libexec/PlistBuddy -c "Print :$entitlement" "$entitlements_file" 2>/dev/null \
            || true
    )
    [ "$value" = true ] || fail "required entitlement is missing or false: $entitlement"
done

actual_keys=$(
    plutil -convert json -o - "$entitlements_file" \
        | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin))))'
)
unexpected_keys=$(
    printf '%s\n' "$actual_keys" \
        | grep -Ev '^(application-identifier|com\.apple\.application-identifier|com\.apple\.developer\.team-identifier|com\.apple\.security\.app-sandbox|com\.apple\.security\.files\.user-selected\.read-write|com\.apple\.security\.network\.client|com\.apple\.security\.personal-information\.location|keychain-access-groups)$' \
        || true
)
[ -z "$unexpected_keys" ] || fail "unexpected signed entitlements: $unexpected_keys"

printf '%s\n' "$actual_keys" \
    | grep -Eq 'temporary-exception|\.files\.(all|downloads|documents|pictures|music|movies)\.' \
    && fail "temporary exception or broad file entitlement detected"

printf '%s\n' "$signature_details" | grep -Eq 'flags=.*runtime' \
    || fail "Hardened Runtime flag is missing"

bundle_id=$(plutil -extract CFBundleIdentifier raw "$info_plist")
[ "$bundle_id" = app.tokendesk.TokenDesk ] || fail "unexpected bundle identifier: $bundle_id"
minimum_system=$(plutil -extract LSMinimumSystemVersion raw "$info_plist")
case "$minimum_system" in
    14.* | 15.* | 16.* | 17.* | 18.* | 19.* | 20.* | 21.* | 22.* | 23.* | 24.* | 25.* | 26.*) ;;
    *) fail "minimum macOS version is below 14 or malformed: $minimum_system" ;;
esac
location_usage=$(plutil -extract NSLocationUsageDescription raw "$info_plist")
[ -n "$location_usage" ] || fail "NSLocationUsageDescription is empty"

linked_libraries=$(otool -L "$executable")
printf '%s\n' "$linked_libraries" | grep -Fq '/System/Library/PrivateFrameworks/' \
    && fail "main executable links a private framework"

archive_application_properties="$archive_path/Info.plist"
[ -f "$archive_application_properties" ] || fail "archive Info.plist is missing"
archive_bundle_id=$(
    plutil -extract ApplicationProperties.CFBundleIdentifier raw "$archive_application_properties"
)
[ "$archive_bundle_id" = "$bundle_id" ] || fail "archive bundle identifier does not match app"

architectures=$(lipo -archs "$executable")
printf 'Verified TokenDesk Release archive\n'
printf '  signature: %s\n' "$signing_kind"
printf '  bundle: %s\n' "$bundle_id"
printf '  minimum macOS: %s\n' "$minimum_system"
printf '  architectures: %s\n' "$architectures"
printf '  entitlements: %s\n' "$(printf '%s' "$actual_keys" | tr '\n' ' ')"
