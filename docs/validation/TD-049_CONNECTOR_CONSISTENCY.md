# TD-049 Connector consistency and partial-failure evidence

> Reviewed: 2026-08-12. Sanitized fixtures and local tests are development-review evidence, not a
> credentialed Provider, signed Release App Sandbox, or long-running production acceptance pass.

## Consistency matrix

| Provider | Account and authentication | Data and currency source | Empty, stale, and degraded behavior |
|---|---|---|---|
| OpenAI | Organization/project hierarchy; Admin API key | Official Usage and Costs; response currency, exact `Decimal` | 401/403/429/network/server errors are normalized; cancellation is preserved |
| Anthropic | Organization-only; optional workspace; Admin API key | Official Usage and Cost Admin APIs; fractional cents converted exactly to USD | Personal scope is rejected before transport; pagination and rate-limit mapping are covered |
| DeepSeek | Local personal/organization hierarchy; API key | Official CNY balance; response usage is local; cost is a versioned estimate | No observed usage remains `notSynchronized`; sibling Provider syncs continue after failure |
| OpenRouter | Local account boundary; management key | Official Credits; configured currency because the payload omits it | Permission and 429 failures remain distinct from empty or zero Credits |
| Kimi | Local personal/organization hierarchy; API key | Official configured-currency balance; response usage is local; cost is estimated | No remote history is implied; normalized transport failures do not erase sibling data |
| Gemini | Local configured account | Response `usageMetadata` is local; cost requires a matching versioned price/currency | No observed usage is `notSynchronized`; inconsistent totals are rejected without persistence |
| GLM | Local configured account/workspace | Response usage is local; cost requires a matching versioned CNY price | Plan and balance are value-free `unsupported` states |
| MiniMax | Local configured account | Response usage is local; optional versioned estimate | Token Plan, pay-as-you-go Token, and balance are not mixed; business errors are not persisted |
| Codex | No P0 credential or transport while GATE-02 is closed | No production value source; demo fixture is permanently marked | Every capability is `unsupported`; Token UI remains selectable but value-free and unavailable |

## Automated evidence

- Every concrete Connector invokes `ProviderConnectorContractTestCase`, which checks declared versus
  unsupported capabilities and Provider/account ownership.
- Connector suites cover sanitized successful mappings, source labels, hierarchy, exact currencies,
  authentication, permission, 429 `Retry-After`, decoding, network/server mapping, and cancellation.
- `providerSettingsCatalogMatchesCapabilitiesAndExcludesCredentiallessCodex` locks the eight
  configurable Provider entries to the approved capability matrix and keeps Codex out of the
  credential editor while GATE-02 is closed.
- `allNineMVPProvidersAreSelectableWithoutInventingCodexValues` switches all nine Token UI entries;
  Codex renders an unavailable, value-free GATE-02 explanation across range changes.
- `oneFailedProviderDoesNotAffectTheOtherEightMVPProviders` runs a nine-Provider sync with one
  authentication failure and verifies eight successful writes plus an isolated failed result.
- Fixture lint, secret scan, strict Swift 6 tests, format lint, and Debug/Release builds remain the
  per-PR quality gate.

## Review conclusion and deferred release acceptance

The development delivery is reviewable when the automated gates above pass. Real Provider account
scope, actual payload variance, rate-limit timing, offline/stale UI with production repositories,
and signed Release App Sandbox execution remain unverified without credentials and a release build.
They belong to TD-057, TD-061, and TD-064 and must not be reported as passed by this task.
