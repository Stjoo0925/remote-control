$repoRoot = Join-Path $PSScriptRoot '..\..\..'

Describe 'release artifact prerequisites' {
    It 'provides docker build definitions for the server stack' {
        (Test-Path -LiteralPath (Join-Path $repoRoot 'frontend\Dockerfile')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'backend\app\__init__.py')) | Should Be $true
    }

    It 'renders docker compose config with the example environment' {
        Push-Location $repoRoot
        try {
            $env:ENV_FILE = '.env.example'
            & docker compose --env-file '.env.example' config | Out-Null
            $LASTEXITCODE | Should Be 0
        } finally {
            Remove-Item Env:ENV_FILE -ErrorAction SilentlyContinue
            Pop-Location
        }
    }

    It 'includes the Android Gradle wrapper and build files required for APK generation' {
        (Test-Path -LiteralPath (Join-Path $repoRoot 'agent\android\settings.gradle.kts')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'agent\android\build.gradle.kts')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'agent\android\app\build.gradle.kts')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'agent\android\gradlew.bat')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'agent\android\gradlew')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'agent\android\gradle\wrapper\gradle-wrapper.jar')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'agent\android\gradle\wrapper\gradle-wrapper.properties')) | Should Be $true
    }

    It 'includes a celery entrypoint module for the backend worker' {
        (Test-Path -LiteralPath (Join-Path $repoRoot 'backend\app\notifications\__init__.py')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $repoRoot 'backend\app\notifications\tasks.py')) | Should Be $true
    }
}
