# Daisy for Windows

The Windows client is a native .NET 8 WPF companion to the macOS SwiftUI app. It manages the same `copilot-api` and LiteLLM services and provides Services, Models, Config, and Logs views plus a system-tray menu.

## Requirements

- Windows 10 version 1809 or newer, or Windows 11
- Node.js 20.16 or newer with `node.exe` and npm on `PATH`
- Python 3.10 through 3.14 with `py.exe` or `python.exe` on `PATH`

The published build is self-contained, so users do not need to install .NET.

## Run from source

```powershell
dotnet run --project .\Windows\Daisy.Windows\Daisy.Windows.csproj
```

## Create a distributable build

From the repository root:

```powershell
.\Windows\publish.ps1
```

The default x64 build is written to `artifacts\Daisy-win-x64\`. Build for Windows on Arm with:

```powershell
.\Windows\publish.ps1 -Runtime win-arm64
```

Run `Daisy.exe` from the published directory. GitHub Actions also produces x64 and Arm64 artifacts for pushes, pull requests, and manual workflow runs.

## Data and lifecycle

Daisy stores Windows-specific application data under `%LOCALAPPDATA%\Daisy\`:

- `litellm-config.yaml`
- `litellm-version.txt`
- `litellm-venv\`
- `copilot-runtime\`
- `models-cache.json`

The managed LiteLLM environment uses the bundled open-source proxy dependency
manifest and explicitly removes the separately licensed `litellm-enterprise`
package.

The GitHub token is stored in Windows Credential Manager. Existing
`copilot-api.env` files are migrated and removed on first launch.

Claude Code settings remain at `%USERPROFILE%\.claude\settings.json`.

Both managed services are child processes. Closing the window keeps Daisy in the system tray; choosing **Exit** from the tray stops both process trees. Daisy does not kill an unrelated process occupying port 4141 or 4000; it reports the conflict instead.

Both HTTP services bind only to `127.0.0.1`. Daisy's managed `copilot-api`
runtime disables permissive CORS and removes its unauthenticated `/token` route.

## Release note

Production downloads should be Authenticode-signed. Unsigned local and CI builds can trigger Microsoft Defender SmartScreen even when the binary is safe.
