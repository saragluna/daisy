# Daisy

A desktop app with native macOS SwiftUI and Windows WPF clients that manages local `copilot-api` and `litellm-proxy` processes while the app is running.

## Build & Run

```bash
./run.sh
```

## Project Structure

- `macOS/DaisyApp/` - Native SwiftUI app and process integration
- `macOS/DaisyCore/` - UI-free Swift contract implementation
- `Windows/Daisy.Windows/` - Native WPF app and process integration
- `Windows/Daisy.Core/` - UI-free .NET contract implementation
- `Shared/Contracts/` - Normative cross-platform behavior and fixtures
- `Tests/` - Swift and .NET conformance runners

## Notes

- Daisy starts `copilot-api` and `litellm-proxy` as child processes, not launchd jobs.
- Daisy stops child processes on app termination.
- Keep UI and process control native. Put configuration editing, model handling, and HTTP protocol rules in both core libraries and update the shared fixture whenever behavior changes.
- The GitHub token is stored in macOS Keychain. Other app data is stored in `~/Library/Application Support/com.daisy.Daisy/`:
  - `litellm-config.yaml` - LiteLLM proxy model config
  - `litellm-version.txt` - Exact LiteLLM version pin
  - `litellm-venv/` - Isolated Python venv for LiteLLM
- Legacy Daisy-owned token files and configs are auto-migrated on first launch.
