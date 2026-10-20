[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallDir,
    [switch]$NoLaunch,
    [switch]$NoShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvironmentValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$DefaultValue
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value
}

function Get-DaisyFile {
    param(
        [Parameter(Mandatory = $true)]
        [Uri]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if ($Uri.IsFile) {
        Copy-Item -LiteralPath $Uri.LocalPath -Destination $Destination
        return
    }

    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-EnvironmentValue -Name "DAISY_VERSION" -DefaultValue "latest"
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = [Environment]::GetEnvironmentVariable("DAISY_INSTALL_DIR")
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw "Daisy installer: LOCALAPPDATA is not available"
        }
        $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Daisy"
    }
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir)

if ((Get-EnvironmentValue -Name "DAISY_NO_LAUNCH" -DefaultValue "0") -eq "1") {
    $NoLaunch = $true
}

if ((Get-EnvironmentValue -Name "DAISY_NO_SHORTCUT" -DefaultValue "0") -eq "1") {
    $NoShortcut = $true
}

$repository = Get-EnvironmentValue -Name "DAISY_REPOSITORY" -DefaultValue "saragluna/daisy"
$downloadBaseUrl = [Environment]::GetEnvironmentVariable("DAISY_DOWNLOAD_BASE_URL")
if ([string]::IsNullOrWhiteSpace($downloadBaseUrl)) {
    if ($Version -eq "latest") {
        $downloadBaseUrl = "https://github.com/$repository/releases/latest/download"
    }
    else {
        $downloadBaseUrl = "https://github.com/$repository/releases/download/$Version"
    }
}
$downloadBaseUrl = $downloadBaseUrl.TrimEnd("/")

$baseUri = [Uri]$downloadBaseUrl
if (($baseUri.Scheme -ne "https") -and (-not $baseUri.IsFile)) {
    throw "Daisy installer: download URL must use HTTPS"
}

$isWindowsPlatform = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [Runtime.InteropServices.OSPlatform]::Windows
)
if ((-not $isWindowsPlatform) -and (-not $baseUri.IsFile)) {
    throw "Daisy installer: this installer is for Windows; use install.sh on macOS"
}
if (-not $baseUri.IsFile) {
    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    )
}

$architecture = $env:PROCESSOR_ARCHITEW6432
if ([string]::IsNullOrWhiteSpace($architecture)) {
    $architecture = $env:PROCESSOR_ARCHITECTURE
}

switch ($architecture.ToUpperInvariant()) {
    "AMD64" { $runtime = "win-x64" }
    "ARM64" { $runtime = "win-arm64" }
    default { throw "Daisy installer: unsupported Windows architecture: $architecture" }
}

$archiveName = "Daisy-$runtime.zip"
$checksumName = "SHA256SUMS"
$temporaryDir = Join-Path ([IO.Path]::GetTempPath()) ("daisy-install-" + [Guid]::NewGuid().ToString("N"))
$extractDir = Join-Path $temporaryDir "extracted"
$parentDir = Split-Path -Parent $InstallDir
$stagingDir = Join-Path $parentDir (".Daisy.install." + [Guid]::NewGuid().ToString("N"))
$backupDir = Join-Path $parentDir (".Daisy.backup." + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Path $temporaryDir, $extractDir -Force | Out-Null

    $archivePath = Join-Path $temporaryDir $archiveName
    $checksumPath = Join-Path $temporaryDir $checksumName

    Write-Host "Downloading Daisy $Version for $runtime..."
    Get-DaisyFile -Uri ([Uri]("$downloadBaseUrl/$archiveName")) -Destination $archivePath
    Get-DaisyFile -Uri ([Uri]("$downloadBaseUrl/$checksumName")) -Destination $checksumPath

    $escapedArchiveName = [Regex]::Escape($archiveName)
    $checksumLine = Get-Content -LiteralPath $checksumPath | Where-Object {
        $_ -match "^[0-9a-fA-F]{64}\s+\*?$escapedArchiveName$"
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($checksumLine)) {
        throw "Daisy installer: $checksumName does not contain $archiveName"
    }

    $expectedChecksum = ($checksumLine -split "\s+")[0].ToUpperInvariant()
    $actualChecksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualChecksum -ne $expectedChecksum) {
        throw "Daisy installer: checksum verification failed for $archiveName"
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir -Force
    $sourceExecutable = Join-Path $extractDir "Daisy.exe"
    if (-not (Test-Path -LiteralPath $sourceExecutable -PathType Leaf)) {
        throw "Daisy installer: release archive does not contain Daisy.exe"
    }

    $runningDaisy = $null
    if ($isWindowsPlatform) {
        $runningDaisy = Get-Process -Name "Daisy" -ErrorAction SilentlyContinue
    }
    if ($null -ne $runningDaisy) {
        throw "Daisy installer: exit Daisy from the system tray before updating"
    }

    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    Move-Item -LiteralPath $extractDir -Destination $stagingDir

    $hadPrevious = Test-Path -LiteralPath $InstallDir
    if ($hadPrevious) {
        Move-Item -LiteralPath $InstallDir -Destination $backupDir
    }

    try {
        Move-Item -LiteralPath $stagingDir -Destination $InstallDir
    }
    catch {
        if ($hadPrevious -and (Test-Path -LiteralPath $backupDir)) {
            Move-Item -LiteralPath $backupDir -Destination $InstallDir
        }
        throw
    }

    if ($hadPrevious -and (Test-Path -LiteralPath $backupDir)) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force
    }

    $installedExecutable = Join-Path $InstallDir "Daisy.exe"

    if (-not $NoShortcut) {
        $programsDir = [Environment]::GetFolderPath("Programs")
        $shortcutDir = Join-Path $programsDir "Daisy"
        $shortcutPath = Join-Path $shortcutDir "Daisy.lnk"
        New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $installedExecutable
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.IconLocation = "$installedExecutable,0"
        $shortcut.Save()
    }

    Write-Host "Installed Daisy at $InstallDir"

    if (-not $NoLaunch) {
        Start-Process -FilePath $installedExecutable
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDir) {
        Remove-Item -LiteralPath $temporaryDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force
    }
}
