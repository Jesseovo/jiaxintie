param([string]$AppPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $AppPath) {
    $version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
    $AppPath = Join-Path $projectRoot ('dist\' + $version + '\夹心贴.exe')
}
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$benchmarkPath = Join-Path $PSScriptRoot 'PaintBenchmark.exe'
& $compilerPath /nologo /utf8output /codepage:65001 /target:exe /platform:x64 /optimize+ ('/out:' + $benchmarkPath) /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll (Join-Path $PSScriptRoot 'PaintBenchmark.cs')
if ($LASTEXITCODE -ne 0) { throw 'Benchmark compilation failed.' }
& $benchmarkPath $AppPath
if ($LASTEXITCODE -ne 0) { throw 'Benchmark failed.' }
