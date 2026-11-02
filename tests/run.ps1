$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot
$projectRoot = Split-Path $testRoot -Parent
$appPath = Join-Path $projectRoot 'dist\1.0.2\夹心贴.exe'
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
Copy-Item -LiteralPath $appPath -Destination (Join-Path $testRoot '夹心贴.exe') -Force
try {
    & $compilerPath /nologo /utf8output /target:exe /platform:x64 ('/out:' + (Join-Path $testRoot 'CoreRegression.exe')) ('/reference:' + $appPath) /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Core.dll (Join-Path $testRoot 'CoreRegression.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Regression test compilation failed.' }
    & (Join-Path $testRoot 'CoreRegression.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Regression tests failed.' }
} finally {
    Remove-Item -LiteralPath (Join-Path $testRoot '夹心贴.exe'),(Join-Path $testRoot 'CoreRegression.exe') -Force -ErrorAction SilentlyContinue
}
