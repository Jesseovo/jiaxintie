param([switch]$SkipScreenCapture)
$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot
$projectRoot = Split-Path $testRoot -Parent
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
$appPath = Join-Path $projectRoot ('dist\' + $version + '\夹心贴.exe')
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
Copy-Item -LiteralPath $appPath -Destination (Join-Path $testRoot '夹心贴.exe') -Force
try {
    & $compilerPath /nologo /utf8output /codepage:65001 /target:exe /platform:x64 ('/out:' + (Join-Path $testRoot 'CoreRegression.exe')) ('/reference:' + $appPath) /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Core.dll (Join-Path $testRoot 'CoreRegression.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Regression test compilation failed.' }
    $testArguments = @()
    if ($SkipScreenCapture) { $testArguments += '--skip-screen-capture' }
    & (Join-Path $testRoot 'CoreRegression.exe') @testArguments
    if ($LASTEXITCODE -ne 0) { throw 'Regression tests failed.' }
} finally {
    Remove-Item -LiteralPath (Join-Path $testRoot '夹心贴.exe'),(Join-Path $testRoot 'CoreRegression.exe') -Force -ErrorAction SilentlyContinue
}
