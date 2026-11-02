param([ValidateSet('demo','real','settings','pin')][string]$Mode = 'demo',[switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot
$projectRoot = Split-Path $testRoot -Parent
$profilePath = Join-Path $testRoot 'ui-profile'
$shotsPath = Join-Path $testRoot 'ui-shots'
New-Item -ItemType Directory -Path $profilePath,$shotsPath -Force | Out-Null
$settings = @{
    SaveDirectory=$shotsPath; CacheLimit=3; CaptureKey=119; CopyKey=119; SaveKey=83;
    PinKey=120; TogglePinsKey=65656; AutoCopyKey=131191; CancelKey=27;
    UndoKey=131162; RedoKey=131161; ResetZoomKey=48
} | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $profilePath 'settings.json'), $settings, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $testRoot 'ui-mode.txt'), $Mode)
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compilerPath /nologo /utf8output /target:winexe /platform:x64 ('/out:' + (Join-Path $testRoot 'UiHarness.exe')) /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $testRoot 'UiHarness.cs')
if ($LASTEXITCODE -ne 0) { throw 'UI harness compilation failed.' }
if (-not $PrepareOnly) { Start-Process -FilePath (Join-Path $testRoot 'UiHarness.exe') -WindowStyle Hidden }
