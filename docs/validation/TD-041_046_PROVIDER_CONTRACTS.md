# TD-041/042/043/046 Provider contract evidence

> Reviewed: 2026-08-12. Documentation-derived fixtures and local tests are not evidence of a
> credentialed production or App Sandbox integration pass.

## Capability matrix

| Provider | Credential and account boundary | Usage | Cost | Balance/Credits | Currency |
|---|---|---|---|---|---|
| Anthropic | Admin API key; organization accounts only; optional configured workspace filter | Official Usage Admin API, grouped by model/workspace | Official Cost Admin API, daily | Unsupported | API returns USD fractional cents; connector divides exact `Decimal` by 100 |
| DeepSeek | API key; local personal/organization scope and hierarchy remain isolated | Successful response `usage` recorded locally; no historical usage claim | Versioned local estimate only | Official Balance API | Balance response currency is authoritative; estimate currency must be configured |
| OpenRouter | Management key; local personal/organization scope remains isolated | Unsupported by Credits API | Cumulative consumption is not converted into interval cost | Official Credits API: total credited, total consumed, available | Must be configured because the Credits payload omits a currency code |
| Kimi/Moonshot | API key; local personal/organization scope and hierarchy remain isolated | Successful response `usage` recorded locally; no historical usage claim | Versioned local estimate only | Official Balance API | Balance and estimate currencies must be configured because the payload omits a code |

DeepSeek and Kimi response ingestion is an exactly-once caller contract. Token Desk discards the
response ID and content rather than persisting a remote identifier, prompt, or completion for
deduplication. An atomic repository add prevents concurrent responses in the same minute from
overwriting one another.

## Endpoint and limit evidence

- Anthropic: `GET /v1/organizations/usage_report/messages` and
  `GET /v1/organizations/cost_report`, `x-api-key` plus `anthropic-version: 2023-06-01`.
  Usage supports minute/hour/day buckets; cost is daily; this connector requests at most 31 daily
  buckets per page and follows opaque pagination cursors. The official guide recommends sustained
  polling no more than once per minute.
- DeepSeek: `GET /user/balance` with bearer authentication. Token and cache-hit/cache-miss counts
  come only from successful completion response `usage` fields in this implementation.
- OpenRouter: `GET /api/v1/credits` with a management key. `total_credits - total_usage` is retained
  as available Credits without converting cumulative usage into a dated cost bucket.
- Kimi/Moonshot: `GET /v1/users/me/balance` with bearer authentication. Token and optional cached
  token counts come only from successful completion response `usage` fields.

All reads use HTTPS, a 30-second request timeout, cancellation checks, normalized 401/403/429/5xx
errors, and `Retry-After` propagation for numeric 429 responses. No connector invents a numeric
Provider rate limit when the public endpoint contract does not publish one.

## Failure and privacy behavior

- Capability absence returns `.unsupported`; supported-but-not-yet-priced local costs return
  `.notSynchronized`; an authoritative empty balance response remains distinct from a zero.
- `SyncCoordinator` retains its Provider-parallel isolation: authentication, permission, rate-limit,
  decoding, or service failure from one connector does not cancel successful sibling Providers.
- Credentials are fetched through `CredentialStore` only for request construction. Fixtures contain
  no headers, prompts, completions, emails, or real remote identifiers.
- Contract tests do not access the network. Real Admin/management/API-key scope, documented limit
  behavior, production availability, and Release App Sandbox execution remain a later credentialed
  integration acceptance gate.

## Official references

- Anthropic Usage and Cost API: <https://platform.claude.com/docs/en/manage-claude/usage-cost-api>
- DeepSeek Balance API: <https://api-docs.deepseek.com/zh-cn/api/get-user-balance>
- DeepSeek response usage: <https://api-docs.deepseek.com/api/create-chat-completion>
- OpenRouter Credits API: <https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits>
- Kimi Balance API: <https://platform.kimi.ai/docs/api/balance>
- Kimi response usage: <https://platform.kimi.ai/docs/api/chat>
