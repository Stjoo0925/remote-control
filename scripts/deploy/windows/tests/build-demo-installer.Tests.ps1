$scriptPath = Join-Path $PSScriptRoot '..\build-demo-installer.ps1'

Describe 'build-demo-installer.ps1' {
    BeforeEach {
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("remote-control-demo-installer-" + [guid]::NewGuid().ToString('N'))
        $frontendDist = Join-Path $testRoot 'frontend\dist'
        $outputRoot = Join-Path $testRoot 'release'

        New-Item -ItemType Directory -Force -Path $frontendDist | Out-Null
        Set-Content -LiteralPath (Join-Path $frontendDist 'index.html') -Value '<html><body>demo</body></html>' -Encoding utf8

        $script:TestRoot = $testRoot
        $script:FrontendDist = $frontendDist
        $script:OutputRoot = $outputRoot
    }

    AfterEach {
        if ($script:TestRoot -and (Test-Path -LiteralPath $script:TestRoot)) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force
        }
    }

    It 'creates the staging package without building an installer when StageOnly is set' {
        & $scriptPath -OutputRoot $script:OutputRoot -FrontendDist $script:FrontendDist -StageOnly | Out-Null

        $stagingRoot = Join-Path $script:OutputRoot 'staging'

        (Test-Path -LiteralPath (Join-Path $stagingRoot 'frontend\index.html')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $stagingRoot 'config\demo-config.json')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $stagingRoot 'scripts\launch-demo.bat')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $stagingRoot 'README.txt')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $stagingRoot 'package-manifest.json')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $script:OutputRoot 'RemoteControlDemoInstaller.exe')) | Should Be $false
    }

    It 'builds a standalone installer executable' {
        & $scriptPath -OutputRoot $script:OutputRoot -FrontendDist $script:FrontendDist | Out-Null

        (Test-Path -LiteralPath (Join-Path $script:OutputRoot 'RemoteControlDemoInstaller.exe')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $script:OutputRoot 'RemoteControlDemoInstaller.dll')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $script:OutputRoot 'RemoteControlDemoInstaller.deps.json')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $script:OutputRoot 'RemoteControlDemoInstaller.runtimeconfig.json')) | Should Be $true
    }
}
