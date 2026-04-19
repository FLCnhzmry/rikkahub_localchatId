param(
    [string]$BaseRef = "",
    [string]$OutputDir = "patches",
    [string[]]$IncludePaths = @()
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$outputPath = Join-Path $repoRoot $OutputDir

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required"
}

Push-Location $repoRoot
try {
    $insideWorkTree = (git rev-parse --is-inside-work-tree).Trim()
    if ($LASTEXITCODE -ne 0 -or $insideWorkTree -ne "true") {
        throw "The current directory is not a git repository."
    }

    if ([string]::IsNullOrWhiteSpace($BaseRef)) {
        $BaseRef = (git describe --tags --abbrev=0).Trim()
    }

    $resolvedBase = (git rev-parse --verify $BaseRef 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolvedBase)) {
        throw "Base ref '$BaseRef' could not be resolved."
    }

    if (Test-Path $outputPath) {
        Get-ChildItem $outputPath -Filter *.patch -File -ErrorAction SilentlyContinue | Remove-Item -Force
    } else {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    $formatPatchArgs = @(
        "format-patch",
        "--output-directory", $outputPath,
        "$BaseRef..HEAD"
    )
    if ($IncludePaths.Count -gt 0) {
        $formatPatchArgs += "--"
        $formatPatchArgs += $IncludePaths
    }

    git @formatPatchArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git format-patch failed."
    }

    $patchCount = @(Get-ChildItem $outputPath -Filter *.patch -File).Count
    Write-Host "Exported $patchCount patch(es) to $outputPath"
} finally {
    Pop-Location
}
