#!/usr/bin/env python3

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "Fixtures"
MANIFEST = FIXTURES / "manifest.json"
CAPABILITIES = {"plan", "usage", "cost", "balance", "credits", "errors"}
DATA_CAPABILITIES = CAPABILITIES - {"errors"}
ERROR_SCENARIOS = {"authentication", "permission", "rate-limit", "decoding", "unsupported"}
PROVENANCE = {"documentation-derived-synthetic", "manually-redacted-recording"}
REDACTIONS = {"credentials", "email", "remote-account-identifiers", "request-body"}


def fail(message: str) -> None:
    print(f"Fixture lint failed: {message}", file=sys.stderr)
    raise SystemExit(1)


try:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"cannot read manifest: {error}")

if manifest.get("schemaVersion") != 1:
    fail("manifest schemaVersion must be 1")

entries = manifest.get("entries")
if not isinstance(entries, list) or not entries:
    fail("manifest entries must be a non-empty array")

registered: set[str] = set()
covered_capabilities: set[str] = set()
covered_errors: set[str] = set()

for index, entry in enumerate(entries):
    label = f"entry {index}"
    if not isinstance(entry, dict):
        fail(f"{label} must be an object")

    path = entry.get("path")
    if not isinstance(path, str) or not path.startswith("v1/") or ".." in Path(path).parts:
        fail(f"{label} has an invalid path")
    if path in registered:
        fail(f"duplicate manifest path: {path}")
    registered.add(path)

    capability = entry.get("capability")
    if capability not in CAPABILITIES:
        fail(f"{path} has an unknown capability")
    outcome = entry.get("outcome")
    if outcome not in {"success", "error"}:
        fail(f"{path} has an invalid outcome")
    if capability in DATA_CAPABILITIES and outcome == "success":
        covered_capabilities.add(capability)
    if capability == "errors" and outcome == "error":
        covered_errors.add(entry.get("scenario"))

    source = entry.get("source")
    if not isinstance(source, str) or not source.startswith("https://"):
        fail(f"{path} must name an HTTPS source")
    if not isinstance(entry.get("sourceVersion"), str) or not entry["sourceVersion"].strip():
        fail(f"{path} must name a source version or review date")
    if entry.get("provenance") not in PROVENANCE:
        fail(f"{path} has an invalid provenance")
    if entry.get("redactionReviewed") is not True:
        fail(f"{path} has not been manually reviewed for redaction")
    if set(entry.get("redactions", [])) != REDACTIONS:
        fail(f"{path} must record all mandatory redaction classes")
    if entry.get("provenance") == "documentation-derived-synthetic" and entry.get("realAccountVerified") is not False:
        fail(f"{path} cannot claim real-account verification")

    fixture_path = FIXTURES / path
    try:
        json.loads(fixture_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot parse {path}: {error}")

files = {
    path.relative_to(FIXTURES).as_posix()
    for path in (FIXTURES / "v1").rglob("*.json")
}
if files != registered:
    missing = sorted(files - registered)
    absent = sorted(registered - files)
    fail(f"manifest mismatch; unregistered={missing}, missing={absent}")
if covered_capabilities != DATA_CAPABILITIES:
    fail(f"missing success capability fixtures: {sorted(DATA_CAPABILITIES - covered_capabilities)}")
if covered_errors != ERROR_SCENARIOS:
    fail(f"missing error scenarios: {sorted(ERROR_SCENARIOS - covered_errors)}")

print(f"Fixture lint passed: {len(entries)} payloads registered.")
