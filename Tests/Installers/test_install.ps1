param(
    [string]$ArchivePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$installerPath = Join-Path $repositoryRoot "install.ps1"
$temporaryDir = Join-Path ([IO.Path]::GetTempPath()) ("daisy-installer-test-" + [Guid]::NewGuid().ToString("N"))
$releaseDir = Join-Path $temporaryDir "release"
$sourceDir = Join-Path $temporaryDir "source"
$installDir = Join-Path (Join-Path $temporaryDir "installed") "Daisy"

$architecture = $env:PROCESSOR_ARCHITEW6432
if ([string]::IsNullOrWhiteSpace($architecture)) {
    $architecture = $env:PROCESSOR_ARCHITECTURE
}

switch ($architecture.ToUpperInvariant()) {
    "AMD64" { $runtime = "win-x64" }
    "ARM64" { $runtime = "win-arm64" }
    default { throw "Unsupported test architecture: $architecture" }
}

$archiveName = "Daisy-$runtime.zip"
$resolvedArchivePath = $null
if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
    $resolvedArchivePath = (Resolve-Path -LiteralPath $ArchivePath).Path
}

function New-FakeRelease {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseVersion
    )

    Remove-Item -LiteralPath $releaseDir, $sourceDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $releaseDir, $sourceDir -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $sourceDir "Daisy.exe") -Value "fake executable" -Encoding Ascii
    Set-Content -LiteralPath (Join-Path $sourceDir "version.txt") -Value $ReleaseVersion -Encoding Ascii

    $archivePath = Join-Path $releaseDir $archiveName
    Compress-Archive -Path (Join-Path $sourceDir "*") -DestinationPath $archivePath
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $releaseDir "SHA256SUMS") -Value "$hash  $archiveName" -Encoding Ascii
}

function Invoke-TestInstaller {
    & $installerPath -NoLaunch -NoShortcut
}

$previousDownloadBaseUrl = $env:DAISY_DOWNLOAD_BASE_URL
$previousInstallDir = $env:DAISY_INSTALL_DIR
$previousNoLaunch = $env:DAISY_NO_LAUNCH
$previousNoShortcut = $env:DAISY_NO_SHORTCUT

New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
$releasePath = (Resolve-Path -LiteralPath $releaseDir).Path + [IO.Path]::DirectorySeparatorChar
$releaseUri = [Uri]::new($releasePath)

try {
    $env:DAISY_DOWNLOAD_BASE_URL = $releaseUri.AbsoluteUri.TrimEnd("/")
    $env:DAISY_INSTALL_DIR = $installDir
    $env:DAISY_NO_LAUNCH = "1"
    $env:DAISY_NO_SHORTCUT = "1"

    if ($null -ne $resolvedArchivePath) {
        $releaseArchivePath = Join-Path $releaseDir $archiveName
        Copy-Item -LiteralPath $resolvedArchivePath -Destination $releaseArchivePath
        $hash = (Get-FileHash -LiteralPath $releaseArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        Set-Content -LiteralPath (Join-Path $releaseDir "SHA256SUMS") -Value "$hash  $archiveName" -Encoding Ascii

        Invoke-TestInstaller
        if (-not (Test-Path -LiteralPath (Join-Path $installDir "Daisy.exe") -PathType Leaf)) {
            throw "installer did not install the packaged Daisy.exe"
        }

        Write-Host "Packaged Windows installer test passed"
        return
    }

    New-FakeRelease -ReleaseVersion "first"
    Invoke-TestInstaller

    if (-not (Test-Path -LiteralPath (Join-Path $installDir "Daisy.exe") -PathType Leaf)) {
        throw "installer did not install Daisy.exe"
    }
    if ((Get-Content -LiteralPath (Join-Path $installDir "version.txt") -Raw).Trim() -ne "first") {
        throw "installer did not install the first version"
    }

    Set-Content -LiteralPath (Join-Path $installDir "stale-file") -Value "stale"
    New-FakeRelease -ReleaseVersion "second"
    Invoke-TestInstaller

    if ((Get-Content -LiteralPath (Join-Path $installDir "version.txt") -Raw).Trim() -ne "second") {
        throw "installer did not install the second version"
    }
    if (Test-Path -LiteralPath (Join-Path $installDir "stale-file")) {
        throw "installer left stale files behind"
    }

    New-FakeRelease -ReleaseVersion "corrupt"
    Set-Content -LiteralPath (Join-Path $releaseDir "SHA256SUMS") -Value (("0" * 64) + "  $archiveName") -Encoding Ascii

    $checksumRejected = $false
    try {
        Invoke-TestInstaller
    }
    catch {
        if ($_.Exception.Message -like "*checksum verification failed*") {
            $checksumRejected = $true
        }
        else {
            throw
        }
    }

    if (-not $checksumRejected) {
        throw "installer accepted a bad checksum"
    }
    if ((Get-Content -LiteralPath (Join-Path $installDir "version.txt") -Raw).Trim() -ne "second") {
        throw "failed installation changed the installed version"
    }

    Write-Host "Windows installer tests passed"
}
finally {
    $env:DAISY_DOWNLOAD_BASE_URL = $previousDownloadBaseUrl
    $env:DAISY_INSTALL_DIR = $previousInstallDir
    $env:DAISY_NO_LAUNCH = $previousNoLaunch
    $env:DAISY_NO_SHORTCUT = $previousNoShortcut
    Remove-Item -LiteralPath $temporaryDir -Recurse -Force -ErrorAction SilentlyContinue
}
