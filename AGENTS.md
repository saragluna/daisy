# Daisy

A desktop app with macOS SwiftUI and Windows WPF clients that manages local `copilot-api` and `litellm-proxy` processes while the app is running.

## Build & Run

```bash
./run.sh
```

On Windows, build a self-contained package with `Windows\publish.ps1`.

Run cross-platform contract checks with `swift test` and `dotnet run --project Tests/Windows/Daisy.Core.ContractTests/Daisy.Core.ContractTests.csproj`.

## Project Structure

- `macOS/DaisyApp/` - Native SwiftUI, persistence, login item, and process control
- `macOS/DaisyCore/` - UI-free Swift contract implementation
- `build/Daisy.app/` - Local app bundle
- `Windows/Daisy.Windows/` - Native .NET 8 WPF, persistence, startup, and process control
- `Windows/Daisy.Core/` - UI-free .NET contract implementation
- `Windows/publish.ps1` - Windows x64/Arm64 publisher
- `Shared/Contracts/` - Normative cross-platform specification and fixtures
- `Tests/` - Native runners for the shared conformance fixtures

## Notes

- Daisy starts `copilot-api` and `litellm-proxy` as child processes, not launchd jobs.
- Daisy stops child processes on app termination.
- Platform paths and process lifecycle stay native; configuration editing, model handling, and HTTP protocol behavior belong in the core libraries and shared contract.
