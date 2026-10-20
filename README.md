# Daisy

Daisy is a desktop app for running a local Copilot-powered proxy stack while the app is open. It has a macOS SwiftUI client and a Windows WPF client.

It manages two local services:

- `copilot-api` on `http://localhost:4141`
- `litellm-proxy` on `http://localhost:4000`

Daisy starts these services as child processes, shows their status and logs, lets you edit their configuration, and stops them when the app quits normally.

The clients share a language-neutral behavioral contract for configuration editing, model handling, and HTTP protocol details. Swift and .NET core libraries run the same conformance fixtures so native implementations cannot silently drift.

## Features

- Start, stop, and restart `copilot-api` and `litellm-proxy`
- Edit the GitHub token used by `copilot-api`
- Edit the LiteLLM proxy config file
- Add or remove models from the LiteLLM config in the Models view
- View per-service or combined logs
- Cache and manually refresh the available model list
- Menu bar or system-tray controls for quick service actions
- LiteLLM runs in an isolated Python venv (auto-installed on first launch)

## One-command install

Install the latest release for macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/saragluna/daisy/main/install.sh | bash
```

The macOS installer downloads the universal release, verifies its SHA-256
checksum and Developer ID signature, requires Gatekeeper acceptance, installs
it to `~/Applications/Daisy.app`, and launches it.

Install the latest release from PowerShell on Windows:

```powershell
irm https://raw.githubusercontent.com/saragluna/daisy/main/install.ps1 | iex
```

The Windows installer selects x64 or Arm64 automatically, verifies its SHA-256
checksum, installs it under `%LOCALAPPDATA%\Programs\Daisy`, adds a Start menu
shortcut, and launches it. Node.js and Python are still required for Daisy's
managed services; see the platform requirements below.

Set `DAISY_VERSION` before running either command to install a specific release
tag. Both installers also support `DAISY_INSTALL_DIR` and `DAISY_NO_LAUNCH=1`.

## macOS Requirements

- macOS 14 or newer
- Swift 5.9 or newer
- Node.js 20.16 or newer with `node` and `npm` on `PATH`
- Python 3.10 through 3.14 (for the LiteLLM venv)

## macOS Service Model

Daisy does not install launchd jobs for its managed services.

Instead, it starts `copilot-api` and `litellm-proxy` with `Process` while Daisy is running. This keeps the lifecycle simple: open Daisy to run the stack, quit Daisy to stop it.

When starting `copilot-api`, Daisy also attempts to unload the old `com.copilot-api` launchd job if it exists, so the old background service does not compete for port `4141`.

## macOS Configuration

The GitHub token is stored in macOS Keychain. Other app data is stored in
`~/Library/Application Support/com.daisy.Daisy/`:

- `litellm-config.yaml` - LiteLLM proxy model config
- `litellm-version.txt` - Exact, pinned LiteLLM version
- `litellm-venv/` - Isolated Python venv for LiteLLM
- `copilot-runtime/` - Lockfile-pinned, hardened `copilot-api` runtime

Legacy tokens in Daisy-owned environment files are migrated to Keychain on first
launch. Configs from `~/Projects/litellm-proxy/config.yaml` are also migrated.

You can edit the token and LiteLLM config from Daisy's Config view. Restart the respective service after changing config.

## Build And Run on macOS

```bash
./run.sh
```

To build the app bundle without launching it (for example, in CI):

```bash
./run.sh --build-only
```

## Windows

The native Windows client has the same Services, Models, Config, and Logs workflow, including system-tray controls and open-at-login support. It requires Node.js and Python on `PATH`; distributable builds include the .NET runtime.

Run it from source on Windows:

```powershell
dotnet run --project .\Windows\Daisy.Windows\Daisy.Windows.csproj
```

Create a self-contained x64 build:

```powershell
.\Windows\publish.ps1
```

See [Windows/README.md](Windows/README.md) for requirements, Arm64 builds, data locations, and release-signing notes.

## Contract Tests

Run both platform conformance suites from the repository root:

```bash
swift test
dotnet run --project Tests/Windows/Daisy.Core.ContractTests/Daisy.Core.ContractTests.csproj
```

The normative behavior and shared fixtures live in [`Shared/Contracts`](Shared/Contracts/README.md). UI and process lifecycle behavior remain native.

## Continuous Integration

The `CI` GitHub Actions workflow builds all supported packages on every push,
pull request, and manual run:

- `Daisy-macOS` contains the macOS `.app` bundle in a ZIP archive.
- `Daisy-win-x64` and `Daisy-win-arm64` contain self-contained Windows builds.

The generated packages are available from the workflow run's **Artifacts**
section. CI artifacts are unsigned development builds.

Pushing a `v*` tag runs the `Release` workflow. It publishes a universal macOS
archive, x64 and Arm64 Windows archives, and `SHA256SUMS` to GitHub Releases for
the one-command installers. macOS releases fail closed unless the following
repository secrets are configured:

- `MACOS_CERTIFICATE_BASE64` - base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD` - password for that `.p12`
- `APPLE_API_KEY_BASE64` - base64-encoded App Store Connect API `.p8` key
- `APPLE_API_KEY_ID` - App Store Connect API key ID
- `APPLE_API_ISSUER_ID` - App Store Connect API issuer ID

The workflow signs with the hardened runtime, submits the app to Apple's notary
service, staples the ticket, and verifies Gatekeeper acceptance before it can
publish the macOS archive.

## Project Structure

```text
macOS/
├── DaisyCore/                  # UI-free Swift implementation of shared contracts
└── DaisyApp/                   # SwiftUI, persistence, login item, and process control

Windows/
├── Daisy.Core/                 # UI-free .NET implementation of shared contracts
├── Daisy.Windows/              # WPF, persistence, startup, and process control
└── publish.ps1                 # Self-contained x64/Arm64 publisher

Shared/Contracts/               # Normative spec and cross-platform JSON fixtures
Tests/
├── macOS/DaisyCoreTests/       # Swift conformance runner
└── Windows/Daisy.Core.ContractTests/ # .NET conformance runner
```

## Notes

- Daisy stops child processes during normal app termination.
- Force-killing Daisy may leave child processes behind because macOS does not run normal termination hooks for a killed process.
- Model refresh is manual and cached so the UI remains useful when `copilot-api` is not currently reachable.
- Both managed HTTP services bind only to `127.0.0.1`. Daisy's managed `copilot-api` runtime also disables permissive CORS and removes its unauthenticated `/token` route.
- Daisy installs exact, reviewed `copilot-api` and LiteLLM versions instead of executing floating `latest` releases.
- Daisy installs LiteLLM's open-source proxy dependencies explicitly and excludes the separately licensed `litellm-enterprise` package.
- Managed runtime packages and their licenses are documented in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
