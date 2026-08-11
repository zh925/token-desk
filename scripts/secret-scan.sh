#!/bin/bash

set -euo pipefail

patterns=(
    'AKIA[0-9A-Z]{16}'
    'sk-[A-Za-z0-9_-]{20,}'
    'sk-ant-[A-Za-z0-9_-]{20,}'
    'gh[pousr]_[A-Za-z0-9]{30,}'
    'AIza[0-9A-Za-z_-]{35}'
    'xox[baprs]-[0-9A-Za-z-]{10,}'
    'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    'Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+[A-Za-z0-9._~+/-]{8,}'
    '-----BEGIN (RSA|EC|OPENSSH|DSA)? ?PRIVATE KEY-----'
)

fixture_patterns=(
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    '"(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|cookie|set-cookie|credential|password|secret|token)"[[:space:]]*:'
    '"(request[_-]?body|prompt|messages|tool[_-]?arguments|generated[_-]?content)"[[:space:]]*:'
)

fixture_identifier_pattern='"(organization|org|workspace|project|account|user|request|trace)[_-]?id"[[:space:]]*:'

has_findings=0
for pattern in "${patterns[@]}"; do
    while IFS= read -r -d '' file; do
        if [[ "$file" == "scripts/secret-scan.sh" ]]; then
            continue
        fi

        if grep -nEIH -e "$pattern" "$file"; then
            has_findings=1
        fi
    done < <(git ls-files -co --exclude-standard -z)
done

while IFS= read -r -d '' file; do
    [[ "$file" == Fixtures/* ]] || continue
    for pattern in "${fixture_patterns[@]}"; do
        if grep -nEIH -e "$pattern" "$file"; then
            has_findings=1
        fi
    done
    while IFS= read -r finding; do
        if [[ "$finding" != *'"fixture-redacted"'* && "$finding" != *': null'* ]]; then
            echo "$file:$finding"
            has_findings=1
        fi
    done < <(grep -nEI -e "$fixture_identifier_pattern" "$file" || true)
done < <(git ls-files -co --exclude-standard -z)

if [[ "$has_findings" -ne 0 ]]; then
    echo "Potential secret material detected. Review and rotate any real credential."
    exit 1
fi

echo "Secret scan passed."
