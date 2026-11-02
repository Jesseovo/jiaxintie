$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$outputPath = Join-Path $projectRoot 'dist\1.0.2'
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$compileArguments = @('/nologo','/utf8output','/target:winexe','/platform:x64','/optimize+',
    ('/out:' + (Join-Path $outputPath '夹心贴.exe')),
    ('/win32icon:' + (Join-Path $projectRoot 'assets\app.ico')),
    ('/win32manifest:' + (Join-Path $projectRoot 'src\app.manifest')),
    ('/resource:' + (Join-Path $projectRoot 'assets\app.ico') + ',app.ico'),
    ('/resource:' + (Join-Path $projectRoot 'assets\logo.png') + ',logo.png'),
    '/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll','/reference:System.Runtime.Serialization.dll','/reference:System.Core.dll',
    (Join-Path $projectRoot 'src\Core.cs'), (Join-Path $projectRoot 'src\Rendering.cs'), (Join-Path $projectRoot 'src\App.cs'), (Join-Path $projectRoot 'src\AssemblyInfo.cs'))
& $compilerPath @compileArguments
if ($LASTEXITCODE -ne 0) { throw 'Application compilation failed.' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $outputPath '使用说明.md') -Force
$innoCompiler = Join-Path $projectRoot 'build-tools\InnoSetup\ISCC.exe'
if (Test-Path -LiteralPath $innoCompiler) {
    & $innoCompiler (Join-Path $projectRoot 'installer.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
}
Get-ChildItem -LiteralPath $outputPath -File | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'build-hashes.json') -Encoding utf8
