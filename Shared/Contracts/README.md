# Daisy cross-platform contracts

This directory is the platform-neutral source of truth for behavior that must not drift between the macOS and Windows clients. Native UI, persistence paths, login integration, and child-process control intentionally stay outside this contract.

`Fixtures/conformance.json` is executable specification data consumed unchanged by both native core test suites. A behavior change is complete only when the contract, the Swift core, the .NET core, and both conformance runners agree.

## Contract v1

### Configuration editing

- Tokens are trimmed, may not contain embedded CR/LF characters, and are serialized as `GITHUB_TOKEN=<token>\n` using LF.
- A LiteLLM version must be an exact numeric/PEP 440-style release; floating channels such as `latest` are rejected.
- Claude settings must be a JSON object. Canonical output uses two-space indentation, LF line endings, lexicographically sorted object keys, and no trailing newline.

### Model handling

- Empty model IDs are discarded and exact duplicate IDs are collapsed.
- Models are grouped by case-insensitive prefix: `gpt`, then `claude`, then all others. Within a group, sort by case-insensitive ordinal ID and then exact ordinal ID.
- LiteLLM entries use provider prefix `github_copilot/`.
- IDs containing `embedding` use mode `embedding`; IDs containing `codex`, `o1`, `o3`, or `o4` use mode `responses`; all others use mode `chat` and omit `model_info`.
- YAML transformations emit LF line endings. Model membership is based on an exact `litellm_params.model` scalar, not substring matching.

### Models API

- Request `GET http://127.0.0.1:4141/v1/models?limit=1000`.
- The response root must be an object with a `data` array.
- Array elements without a non-empty string `id` are ignored; valid IDs then follow the model normalization rules above.

### GitHub device flow

- Begin and token requests use the GitHub JSON endpoints, client ID, scope, and OAuth grant type recorded in the conformance fixture.
- Polling never runs faster than five seconds. An `authorization_pending` result continues unchanged; `slow_down` adds five seconds to all later polls.
- Token, pending, slow-down, and terminal failure responses are classified by the core libraries so native networking code cannot interpret them differently.

## Dependency direction

```text
Shared/Contracts  ->  macOS/DaisyCore  ->  macOS/DaisyApp
                  ->  Windows/Daisy.Core -> Windows/Daisy.Windows
```

Neither core library imports a UI toolkit or launches a process.
