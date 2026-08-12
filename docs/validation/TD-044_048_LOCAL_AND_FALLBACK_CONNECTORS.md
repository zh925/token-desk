# TD-044/045/047/048 local and fallback connector evidence

> Reviewed: 2026-08-12. Documentation-derived fixtures and local contract tests are not evidence
> of a credentialed production account, Provider rate limit, or Release App Sandbox pass.

## Capability decision

| Provider | Plan | Usage | Cost | Balance | P0 presentation |
|---|---|---|---|---|---|
| Gemini | Unsupported | Successful `generateContent` response `usageMetadata` is aggregated locally | Optional versioned local estimate | Unsupported | Before the first locally observed response, show `notSynchronized`; never imply remote history |
| GLM | Unsupported | Successful chat-completion `usage` is aggregated locally, including documented cached prompt tokens | Optional versioned local estimate | Unsupported | Plan and balance remain value-free `unsupported` states |
| MiniMax | Unsupported in this connector | Successful text-response `usage` is aggregated locally | Optional versioned local estimate | Unsupported | Token Plan, pay-as-you-go Token usage, and balance are not mixed |
| Codex | Unsupported while GATE-02 is closed | Unsupported | Unsupported | Unsupported | Show “官方生产接口暂不可用”; fixture cards remain permanently marked “演示数据 · 不代表真实额度” |

The MiniMax Token Plan page now names an authenticated remaining-usage endpoint, but does not
publish a stable response field schema that can be mapped to `PlanWindow` without inference. The
connector therefore does not decode community-observed fields or convert a remaining-time value
into a percentage/reset window. A later credentialed contract task may enable `plan` only after the
official response schema, account scope, error behavior, and Release sandbox path are verified.

## Mapping and privacy rules

- Each ingestion method is an exactly-once caller contract for one successful response. The local
  repository performs the atomic add; repeated calls intentionally add repeated usage.
- Prompt totals include cached input. The connector subtracts the documented cached portion into
  the independent `cachedInput` category and rejects negative, overflowing, or inconsistent totals.
- Gemini thinking tokens remain output usage rather than disappearing from the billable total.
- Only model, Provider timestamp (or Gemini local receipt time), and usage counts cross the DTO
  boundary. Prompts, choices, generated content, response IDs, request IDs, and credentials are not
  decoded or persisted.
- Credentials are checked through `CredentialStore`; none are placed in fixtures, logs, database
  rows, exports, or documentation.
- Costs are emitted only when an effective, versioned pricing rule and explicit currency match the
  local usage bucket. Otherwise the supported estimate remains `notSynchronized`.

## Automated evidence

- `GeminiConnectorContractTests`: cache/thinking mapping, local source, estimated cost, inconsistent
  total rejection, and no-history behavior.
- `GLMConnectorContractTests`: documented response usage, cache split, account hierarchy, and
  explicit unsupported plan/balance.
- `MiniMaxConnectorContractTests`: response usage, business-error rejection, and independent
  unsupported plan/balance.
- `CodexP0ConnectorContractTests`: all data capabilities unsupported, no credential or transport
  side effect, and unavailable health state.
- Feature tests verify that Gemini `notSynchronized` and GLM/MiniMax/Codex `unsupported` states
  remain value-free UI data; Codex fallback copy names the GATE-02 privacy boundary.
- Fixture lint and secret scan cover the three new documentation-derived usage payloads and the
  permanent Codex demonstration marker.

## Official references

- Gemini GenerateContent response and UsageMetadata:
  <https://ai.google.dev/api/generate-content>
- GLM chat completion response usage:
  <https://docs.bigmodel.cn/api-reference/%E6%A8%A1%E5%9E%8B-api/%E5%AF%B9%E8%AF%9D%E8%A1%A5%E5%85%A8>
- MiniMax text response usage:
  <https://platform.minimax.io/docs/api-reference/text-post>
- MiniMax Token Plan and remaining-usage endpoint notice:
  <https://platform.minimax.io/docs/token-plan/faq>
- Codex GATE-02 decision: `docs/spikes/GATE-02_CODEX_APP_SERVER_SANDBOX.md`

## Deferred integration acceptance

Real account validation remains separate: API-key scope, actual provider payload variance, official
rate-limit behavior, production endpoint availability, and signed Release App Sandbox execution.
These unverified items do not authorize scraping, cookies, private interfaces, reading another app's
container, or using the user's existing Codex process.
