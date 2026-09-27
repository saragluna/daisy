param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "Daisy.Windows\Daisy.Windows.csproj"
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$output = Join-Path $repositoryRoot "artifacts\Daisy-$Runtime"

dotnet publish $project `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    --output $output `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

foreach ($runtimeFile in @("litellm-requirements.txt", "litellm-runtime-version.txt")) {
    $runtimePath = Join-Path $output $runtimeFile
    if (-not (Test-Path $runtimePath -PathType Leaf)) {
        throw "Published app is missing bundled LiteLLM runtime file: $runtimeFile"
    }
}

Write-Host "Published Daisy for $Runtime to $output"
