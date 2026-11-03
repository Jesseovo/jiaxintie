param([switch]$RequireInstaller)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$outputPath = Join-Path $projectRoot ('dist\' + $version)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$compileArguments = @('/nologo','/utf8output','/codepage:65001','/target:winexe','/platform:x64','/optimize+',
    ('/out:' + (Join-Path $outputPath '夹心贴.exe')),
    ('/win32icon:' + (Join-Path $projectRoot 'assets\app.ico')),
    ('/win32manifest:' + (Join-Path $projectRoot 'src\app.manifest')),
    ('/resource:' + (Join-Path $projectRoot 'assets\app.ico') + ',app.ico'),
    ('/resource:' + (Join-Path $projectRoot 'assets\logo.png') + ',logo.png'),
    '/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll','/reference:System.Runtime.Serialization.dll','/reference:System.Core.dll',
    (Join-Path $projectRoot 'src\Core.cs'), (Join-Path $projectRoot 'src\Rendering.cs'), (Join-Path $projectRoot 'src\App.cs'), (Join-Path $projectRoot 'src\AssemblyInfo.cs'))
& $compilerPath @compileArguments
if ($LASTEXITCODE -ne 0) { throw 'Application compilation failed.' }
if ([Reflection.AssemblyName]::GetAssemblyName((Join-Path $outputPath '夹心贴.exe')).Version.ToString() -ne ($version + '.0.0')) {
    throw 'VERSION and src/AssemblyInfo.cs do not match.'
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\usage.zh-CN.md') -Destination (Join-Path $outputPath '使用说明.md') -Force
$innoCompiler = Join-Path $projectRoot 'build-tools\InnoSetup\ISCC.exe'
if (-not (Test-Path -LiteralPath $innoCompiler)) {
    $installedCompiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    if (Test-Path -LiteralPath $installedCompiler) { $innoCompiler = $installedCompiler }
}
if (Test-Path -LiteralPath $innoCompiler) {
    & $innoCompiler ('/DAppVersion=' + $version) (Join-Path $projectRoot 'installer.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
} elseif ($RequireInstaller) {
    throw 'Inno Setup 6 was not found. Install Inno Setup 6 or place it in build-tools/InnoSetup.'
}
Get-ChildItem -LiteralPath $outputPath -File | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'build-hashes.json') -Encoding utf8
