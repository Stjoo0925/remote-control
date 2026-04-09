param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\..\..\release\demo-package'),
    [string]$FrontendDist = (Join-Path $PSScriptRoot '..\..\..\frontend\dist'),
    [string]$AgentReleasePath = '',
    [string]$ServerUrl = 'https://remote.corp.local',
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-AbsolutePath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Ensure-Directory([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Copy-FolderContents([string]$Source, [string]$Destination) {
    Ensure-Directory $Destination
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Write-Utf8NoBomFile([string]$Path, [string]$Content) {
    Set-Content -LiteralPath $Path -Value $Content -Encoding utf8
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$outputRoot = Resolve-AbsolutePath $OutputRoot
$stagingRoot = Join-Path $outputRoot 'staging'
$frontendStage = Join-Path $stagingRoot 'frontend'
$configStage = Join-Path $stagingRoot 'config'
$scriptsStage = Join-Path $stagingRoot 'scripts'

if (-not (Test-Path -LiteralPath $FrontendDist)) {
    throw "Frontend dist not found: $FrontendDist"
}

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}

Ensure-Directory $frontendStage
Ensure-Directory $configStage
Ensure-Directory $scriptsStage

Copy-FolderContents -Source $FrontendDist -Destination $frontendStage

$serverConfig = @{
    server_url = $ServerUrl
    frontend_entry = "frontend\\index.html"
    agent_release_path = $AgentReleasePath
} | ConvertTo-Json -Depth 5

Set-Content -LiteralPath (Join-Path $configStage 'demo-config.json') -Value $serverConfig -Encoding utf8

$launchScript = @'
@echo off
setlocal
set "SERVER_URL={0}"
start "" "%SERVER_URL%"
endlocal
'@ -f $ServerUrl

Set-Content -LiteralPath (Join-Path $scriptsStage 'launch-demo.bat') -Value $launchScript -Encoding ascii

$readme = @"
Remote Control Demo Package

This package contains the browser demo assets for the remote-control frontend.
Server endpoint: $ServerUrl

If an agent release folder is provided, its payload should be staged separately in the same package tree.
"@

Set-Content -LiteralPath (Join-Path $stagingRoot 'README.txt') -Value $readme -Encoding utf8

$manifest = @{
    output_root = $outputRoot
    staging_root = $stagingRoot
    frontend_dist = $FrontendDist
    agent_release_path = $AgentReleasePath
    server_url = $ServerUrl
    staged_at = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 5

Set-Content -LiteralPath (Join-Path $stagingRoot 'package-manifest.json') -Value $manifest -Encoding utf8

if ($AgentReleasePath) {
    if (-not (Test-Path -LiteralPath $AgentReleasePath)) {
        throw "Agent release path not found: $AgentReleasePath"
    }
    $agentStage = Join-Path $stagingRoot 'agent'
    Copy-FolderContents -Source $AgentReleasePath -Destination $agentStage
}

if ($StageOnly) {
    Write-Host $stagingRoot
    return
}

$dotnet = (Get-Command dotnet -ErrorAction Stop).Source
$bootstrapperRoot = Join-Path $outputRoot '.bootstrapper'
$bootstrapperProject = Join-Path $bootstrapperRoot 'RemoteControlDemoInstaller.csproj'
$bootstrapperProgram = Join-Path $bootstrapperRoot 'Program.cs'
$payloadZip = Join-Path $bootstrapperRoot 'installer-payload.zip'
$publishRoot = Join-Path $bootstrapperRoot 'publish'
$exePath = Join-Path $outputRoot 'RemoteControlDemoInstaller.exe'

if (Test-Path -LiteralPath $bootstrapperRoot) {
    Remove-Item -LiteralPath $bootstrapperRoot -Recurse -Force
}

Ensure-Directory $bootstrapperRoot

[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingRoot,
    $payloadZip,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$projectContent = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AssemblyName>RemoteControlDemoInstaller</AssemblyName>
    <RootNamespace>RemoteControlDemoInstaller</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <EmbeddedResource Include="installer-payload.zip">
      <LogicalName>installer-payload.zip</LogicalName>
    </EmbeddedResource>
  </ItemGroup>
</Project>
"@

$programContent = @"
using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;

static string GetInstallRoot()
{
    var baseDirectory = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    return Path.Combine(baseDirectory, "RemoteControlDemo");
}

static void ExtractArchive(Stream archiveStream, string destinationRoot)
{
    using var archive = new ZipArchive(archiveStream, ZipArchiveMode.Read, leaveOpen: false);
    foreach (var entry in archive.Entries)
    {
        var targetPath = Path.Combine(destinationRoot, entry.FullName);
        if (string.IsNullOrEmpty(entry.Name))
        {
            Directory.CreateDirectory(targetPath);
            continue;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(targetPath)!);
        entry.ExtractToFile(targetPath, overwrite: true);
    }
}

var installRoot = GetInstallRoot();
if (Directory.Exists(installRoot))
{
    Directory.Delete(installRoot, recursive: true);
}

Directory.CreateDirectory(installRoot);

using var resourceStream = Assembly.GetExecutingAssembly().GetManifestResourceStream("installer-payload.zip")
    ?? throw new InvalidOperationException("Installer payload is missing.");

ExtractArchive(resourceStream, installRoot);

var launchScript = Path.Combine(installRoot, "scripts", "launch-demo.bat");
var processStartInfo = new ProcessStartInfo("cmd.exe", $"/c \"{launchScript}\"")
{
    UseShellExecute = false,
    CreateNoWindow = true,
};

Process.Start(processStartInfo);
Console.WriteLine(installRoot);
"@

Write-Utf8NoBomFile $bootstrapperProject $projectContent
Write-Utf8NoBomFile $bootstrapperProgram $programContent

Push-Location $bootstrapperRoot
try {
    $env:DOTNET_CLI_HOME = $bootstrapperRoot
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'

    & $dotnet publish $bootstrapperProject `
        -c Release `
        --ignore-failed-sources `
        -p:NuGetAudit=false `
        -o $publishRoot | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$publishedExe = Join-Path $publishRoot 'RemoteControlDemoInstaller.exe'
if (-not (Test-Path -LiteralPath $publishedExe)) {
    throw "Installer executable was not created: $publishedExe"
}

Copy-FolderContents -Source $publishRoot -Destination $outputRoot
Remove-Item -LiteralPath $bootstrapperRoot -Recurse -Force

Write-Host $exePath
