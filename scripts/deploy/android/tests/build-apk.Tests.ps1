$scriptPath = Join-Path $PSScriptRoot '..\build-apk.ps1'

Describe 'build-apk.ps1' {
    It 'fails clearly when flutter is not installed' {
        { & $scriptPath } | Should Throw 'flutter'
    }
}
