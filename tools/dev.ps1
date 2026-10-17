param(
    [ValidateSet('run', 'check', 'build', 'smoke', 'generate', 'prepare')]
    [string]$Task = 'run',
    [string]$FlutterRoot = $env:FLUTTER_ROOT
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$appDirectory = Join-Path $repoRoot 'app'
$hostDirectory = Join-Path $repoRoot 'native\host'
$hostBinary = Join-Path $repoRoot 'build\host\rainlink-host.exe'
$updaterBinary = Join-Path $repoRoot 'build\host\rainlink-updater.exe'
$launcherBinary = Join-Path $repoRoot 'build\host\rainlink.exe'

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE" }
}

if ($Task -in 'run', 'build', 'smoke', 'prepare') {
    Invoke-Checked 'python' @((Join-Path $repoRoot 'tools\setup_core.py'))
    Invoke-Checked 'python' @((Join-Path $repoRoot 'tools\setup_runtime_licenses.py'))
    $licenseAssetsDirectory = Join-Path $repoRoot 'app\assets\licenses'
    New-Item -ItemType Directory -Path $licenseAssetsDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'build\host\sing-box-LICENSE.txt') -Destination (Join-Path $licenseAssetsDirectory 'sing-box-LICENSE.txt')
}

if ($Task -in 'run', 'build', 'smoke', 'check', 'prepare') {
    Push-Location $hostDirectory
    try {
        if ($Task -eq 'check') {
            $goFiles = Get-ChildItem -LiteralPath $hostDirectory -Filter '*.go' -Recurse
            $unformatted = & gofmt -l @($goFiles.FullName)
            if ($LASTEXITCODE -ne 0 -or $unformatted) { throw "Run gofmt: $unformatted" }
            Invoke-Checked 'go' @('vet', './...')
            Invoke-Checked 'go' @('test', './...')
        } else {
            New-Item -ItemType Directory -Path (Split-Path $hostBinary) -Force | Out-Null
            Invoke-Checked 'go' @('build', '-trimpath', '-o', $hostBinary, './cmd/rainlink-host')
            Invoke-Checked 'go' @('build', '-trimpath', '-ldflags=-H=windowsgui', '-o', $updaterBinary, './cmd/rainlink-updater')
            Invoke-Checked 'go' @('build', '-trimpath', '-ldflags=-H=windowsgui', '-o', $launcherBinary, './cmd/rainlink-launcher')
        }
    } finally { Pop-Location }
}

if ($Task -eq 'prepare') { return }

if ($FlutterRoot) {
    $flutterCommand = Join-Path $FlutterRoot 'bin\flutter.bat'
} else {
    $flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
}
$dartCommand = Join-Path (Split-Path $flutterCommand) 'dart.bat'

Push-Location $appDirectory
try {
    $flutterFlags = @('--no-version-check', '--suppress-analytics')
    Invoke-Checked $flutterCommand ($flutterFlags + @('pub', 'get', '--enforce-lockfile'))
    Invoke-Checked $dartCommand @('run', 'tool/generate_build_info.dart')
    switch ($Task) {
        'generate' {
            Invoke-Checked $dartCommand @('run', 'build_runner', 'build', '--delete-conflicting-outputs')
        }
        'check' {
            Invoke-Checked 'python' @((Join-Path $repoRoot 'tools\test_package_windows.py'))
            Invoke-Checked $dartCommand @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test', 'tool')
            Invoke-Checked $flutterCommand ($flutterFlags + @('analyze', '--no-pub'))
            Invoke-Checked $flutterCommand ($flutterFlags + @('test', '--no-pub'))
        }
        'run' {
            Invoke-Checked $flutterCommand ($flutterFlags + @('run', '-d', 'windows', "--dart-define=RAINLINK_HOST_PATH=$hostBinary"))
        }
        'smoke' {
            Invoke-Checked $flutterCommand ($flutterFlags + @('test', 'integration_test/desktop_smoke_test.dart', '-d', 'windows', "--dart-define=RAINLINK_HOST_PATH=$hostBinary"))
        }
        'build' {
            Invoke-Checked $flutterCommand ($flutterFlags + @('build', 'windows', '--release'))
            $releaseDirectory = Join-Path $appDirectory 'build\windows\x64\runner\Release'
            # Debug builds share Flutter's ephemeral engine directory. Refuse a
            # mixed bundle if another build replaced it during release assembly.
            $flutterSdkDirectory = Split-Path (Split-Path $flutterCommand)
            $expectedReleaseEngine = Join-Path $flutterSdkDirectory 'bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll'
            if (-not (Test-Path -LiteralPath $expectedReleaseEngine)) {
                throw 'Cannot verify the release engine. Set -FlutterRoot to the Flutter SDK directory.'
            }
            $actualReleaseEngine = Join-Path $releaseDirectory 'flutter_windows.dll'
            if ((Get-FileHash -LiteralPath $actualReleaseEngine).Hash -ne (Get-FileHash -LiteralPath $expectedReleaseEngine).Hash) {
                throw 'Release bundle contains an unexpected Flutter engine. Stop other Flutter builds and rebuild sequentially.'
            }
            Copy-Item -LiteralPath $hostBinary -Destination (Join-Path $releaseDirectory 'rainlink-host.exe')
            Copy-Item -LiteralPath $updaterBinary -Destination (Join-Path $releaseDirectory 'rainlink-updater.exe')
            Invoke-Checked 'python' @((Join-Path $repoRoot 'tools\embed_launcher_resources.py'), '--launcher', $launcherBinary, '--ui', (Join-Path $releaseDirectory 'rainlink-ui.exe'))
            Copy-Item -LiteralPath $launcherBinary -Destination (Join-Path $releaseDirectory 'rainlink.exe')
            Copy-Item -LiteralPath (Join-Path $repoRoot 'build\host\sing-box.exe') -Destination $releaseDirectory
            Copy-Item -LiteralPath (Join-Path $repoRoot 'build\host\sing-box-LICENSE.txt') -Destination $releaseDirectory
            Copy-Item -LiteralPath (Join-Path $repoRoot 'build\host\sing-box-source.zip') -Destination $releaseDirectory
            Copy-Item -LiteralPath (Join-Path $repoRoot 'build\host\wintun-LICENSE.txt') -Destination $releaseDirectory
            Copy-Item -LiteralPath (Join-Path $repoRoot 'build\host\go-winio-LICENSE.txt') -Destination $releaseDirectory
            Invoke-Checked 'python' @((Join-Path $repoRoot 'tools\package_windows.py'), '--manifest-only', '--flutter-root', $flutterSdkDirectory)
            Invoke-Checked 'python' @((Join-Path $repoRoot 'tools\verify_launcher_resources.py'))
            Write-Output "RainLink bundle: $releaseDirectory"
        }
    }
} finally { Pop-Location }
