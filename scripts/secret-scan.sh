#!/bin/bash

set -euo pipefail

patterns=(
    'AKIA[0-9A-Z]{16}'
    'sk-[A-Za-z0-9_-]{20,}'
    'sk-ant-[A-Za-z0-9_-]{20,}'
    'gh[pousr]_[A-Za-z0-9]{30,}'
    '-----BEGIN (RSA|EC|OPENSSH|DSA)? ?PRIVATE KEY-----'
)

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

if [[ "$has_findings" -ne 0 ]]; then
    echo "Potential secret material detected. Review and rotate any real credential."
    exit 1
fi

echo "Secret scan passed."
