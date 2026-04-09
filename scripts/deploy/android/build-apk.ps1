param(
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..\..\..\agent'),
    [string]$FlutterCommand = 'flutter',
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\..\release\android\RemoteControlAgent.apk')
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

$projectRoot = Resolve-AbsolutePath $ProjectRoot
$outputPath = Resolve-AbsolutePath $OutputPath

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'pubspec.yaml'))) {
    throw "Flutter project not found: $projectRoot"
}

$flutter = Get-Command $FlutterCommand -ErrorAction Stop

Push-Location $projectRoot
try {
    & $flutter.Source build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$builtApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path -LiteralPath $builtApk)) {
    throw "APK was not created: $builtApk"
}

$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
Copy-Item -LiteralPath $builtApk -Destination $outputPath -Force

Write-Host $outputPath
