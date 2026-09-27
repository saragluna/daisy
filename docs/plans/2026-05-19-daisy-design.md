# Daisy Design

## Goal

Daisy replaces Copilot API Manager as a local macOS controller for two process-managed services: `copilot-api` and `litellm-proxy`. The services should run only while Daisy chooses to run them, with clear start, stop, restart, config, model, and log surfaces.

## Product Shape

The app is renamed Daisy in the window title, bundle metadata, and menu bar copy. The old single-service Status page is removed. The primary sidebar becomes:

- Services
- Models
- Logs
- Config

The Services page shows one card per managed service. Each card exposes state, endpoint, start/stop/restart controls, and a concise config location. Models keeps the current cached model list and manual refresh behavior. Logs shows the combined Daisy-managed process logs with service labels.

## Process Management

Daisy manages child processes directly with `Process`, not launchd. Starting Daisy does not automatically install or create launch agents. When the user starts a service, Daisy starts the matching script/command and captures stdout/stderr into memory and log files. When Daisy quits, it terminates any child processes it owns.

The existing launchd-managed `com.copilot-api` service is treated as legacy. Daisy should detect and stop it before starting its own `copilot-api` process to avoid port conflicts.

## Service Commands

`copilot-api` uses the token from the platform credential store and launches the
lockfile-managed runtime installed in Daisy's application-data directory:

```bash
node /path/to/copilot-runtime/node_modules/copilot-api/dist/main.js start
```

`litellm-proxy` launches:

```bash
litellm --config /path/to/litellm-config.yaml --host 127.0.0.1 --port 4000
```

Its editable config is stored in Daisy's platform-specific application-data directory.

## Config

The Config page has two sections:

- Copilot API: GitHub token editor backed by macOS Keychain or Windows Credential Manager.
- LiteLLM Proxy: YAML text editor backed by Daisy's application-data directory.

Saving config does not silently restart services. The UI should make restart explicit after changes.

## Logs

Logs are stored in Daisy-owned memory and can also be written under `~/.config/daisy/logs/`. Log rendering must stay line-based and lazy to avoid the previous large-Text switching lag.

## Validation

Build with `swift build -c release`, deploy the binary and resource bundle into `build/Daisy.app`, and launch it. Verify the app opens as Daisy, can start/stop both services, keeps model refresh manual, and switches to/from Logs without large-text lag.
