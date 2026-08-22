$ErrorActionPreference = "Stop"

$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script = Join-Path $project "build\installer.nsi"
$cache = Join-Path $env:LOCALAPPDATA "electron-builder\Cache\nsis"
$compiler = Get-ChildItem -LiteralPath $cache -Recurse -Filter "makensis.exe" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq "Bin" } |
    Sort-Object FullName -Descending |
    Select-Object -First 1

if (-not $compiler) {
    $command = Get-Command "makensis.exe" -ErrorAction SilentlyContinue
    if ($command) {
        $compilerPath = $command.Source
    } else {
        throw "NSIS compiler not found. Install NSIS or populate Electron Builder's NSIS cache."
    }
} else {
    $compilerPath = $compiler.FullName
}

Push-Location $project
try {
    & $compilerPath /WX /V2 $script
    if ($LASTEXITCODE) {
        throw "NSIS compiler exited with $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
