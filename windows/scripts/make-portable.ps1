$ErrorActionPreference = "Stop"

$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$release = Join-Path $project "release"
$source = Join-Path $release "win-unpacked"
$stage = Join-Path $release "portable-stage"
$application = Join-Path $stage "Recast"
$artifact = Join-Path $release "Recast-1.0.0-Windows-x64-Portable.zip"
$blockedWrapper = Join-Path $release "Recast-1.0.0-Windows-x64-Portable.exe"

function Remove-StagingDirectory([string] $target) {
    if (-not (Test-Path -LiteralPath $target)) { return }
    $resolvedTarget = (Resolve-Path -LiteralPath $target).Path
    if (-not $resolvedTarget.StartsWith($release + [IO.Path]::DirectorySeparatorChar)) {
        throw "Refusing to clean an unexpected staging path: $resolvedTarget"
    }

    $empty = Join-Path $release "portable-empty"
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    & robocopy.exe $empty $resolvedTarget /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Unable to clean the portable staging directory (robocopy exit $LASTEXITCODE)." }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
    Remove-Item -LiteralPath $empty -Recurse -Force
}

if (-not (Test-Path -LiteralPath (Join-Path $source "Recast.exe"))) {
    throw "The packaged Windows application is missing."
}

Remove-StagingDirectory $stage

New-Item -ItemType Directory -Path $application | Out-Null
& robocopy.exe $source $application /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Unable to stage the portable application (robocopy exit $LASTEXITCODE)." }
if (Test-Path -LiteralPath $artifact) {
    Remove-Item -LiteralPath $artifact -Force
}
Push-Location $stage
try {
    & tar.exe -a -cf $artifact "Recast"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create the portable ZIP (tar exit $LASTEXITCODE)." }
} finally {
    Pop-Location
}
Remove-StagingDirectory $stage
if (Test-Path -LiteralPath $blockedWrapper) {
    Remove-Item -LiteralPath $blockedWrapper -Force
}
Write-Output "Created $artifact"
