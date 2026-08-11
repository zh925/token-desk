# Fixture policy

Fixtures are test inputs, not evidence that a live Provider capability works. The
initial `v1` set is synthesized from official public documentation and manually
reviewed for privacy. A Connector may claim real support only after its separate
credentialed integration gate passes.

## Layout and metadata

- Put immutable payloads under `Fixtures/v<schema-version>/`.
- Register every JSON payload in `Fixtures/manifest.json`.
- Record the capability, success or error outcome, official source, source
  version/date, provenance, scenario, and redaction review in the manifest.
- Add a new versioned file when a Provider contract changes. Do not silently
  rewrite an old payload that existing tests depend on.
- Keep Provider transport payloads in `TokenDeskConnectors` tests. Map them to
  domain objects before exposing data to other modules.

The manifest distinguishes two permitted provenance values:

- `documentation-derived-synthetic`: constructed from a public contract; never
  sent by a real account.
- `manually-redacted-recording`: captured through an approved test account and
  reviewed field by field before commit.

`realAccountVerified` must remain `false` for documentation-derived samples.
Mock success proves decoding and mapping only; it never proves credentials,
account scope, rate limits, App Sandbox behavior, or production availability.

## Required redaction

Before committing a recording, remove or replace all of the following:

- credentials, authorization headers, cookies, and signed URLs;
- email addresses and personal names;
- remote account, organization, workspace, project, user, and API-key IDs;
- prompts, messages, generated content, tool arguments, and request bodies;
- request IDs or trace IDs that a Provider could correlate to a real account.

Prefer omitting sensitive optional fields. If an identifier field is required to
exercise decoding, use the exact value `fixture-redacted`; never preserve its
shape, prefix, length, hash, or last four characters. Use amounts, timestamps,
model names, and token counts invented for the fixture rather than perturbing
real values.

Record the four mandatory redaction classes in each manifest entry even when a
synthetic sample never contained them. `redactionReviewed: true` is a human
assertion and must not be added by a capture tool.

## Error fixtures

Keep errors minimal. The baseline covers authentication, permission, rate-limit,
decode, and unsupported-capability paths. Do not store raw response bodies inside
an error wrapper, because nested payloads can reintroduce secrets or user content.
Do not use a mocked 429 to claim that a Provider's real retry behavior passed.

## Local checks

Run both checks before committing fixture changes:

```sh
./scripts/fixture-lint.py
./scripts/secret-scan.sh
```

The fixture lint verifies manifest coverage, JSON syntax, required metadata,
capability coverage, and error coverage. The secret scan covers the entire Git
worktree and applies additional privacy rules to files under `Fixtures/`.

If a real credential is ever found, treat it as a security incident: revoke or
rotate it first, inspect Git history and CI artifacts, then remove the material.
Deleting only the current line is not sufficient remediation.
