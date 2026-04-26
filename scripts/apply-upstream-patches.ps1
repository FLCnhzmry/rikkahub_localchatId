param(
    [Parameter(Mandatory = $true)]
    [string]$UpstreamRef,
    [string]$SourceLabel = "",
    [string]$WorkDir = ".release-worktree",
    [string]$PatchDir = "patches",
    [string]$LogDir = ".release-logs",
    [string]$UpstreamRemote = "https://github.com/rikkahub/rikkahub.git",
    [switch]$CleanWorkDir
)

$ErrorActionPreference = "Stop"

function Write-TextFile {
    param(
        [string]$Path,
        [string[]]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    [System.IO.File]::WriteAllLines($Path, $Content)
}

function Invoke-GitLogged {
    param(
        [string]$Repository,
        [string[]]$Arguments,
        [string]$LogPath
    )

    $output = & git -C $Repository @Arguments 2>&1
    Write-TextFile -Path $LogPath -Content @(
        "git -C $Repository $($Arguments -join ' ')",
        ""
    ) + $output

    return @{
        ExitCode = $LASTEXITCODE
        Output = @($output)
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$patchPath = Join-Path $repoRoot $PatchDir
$logPath = Join-Path $repoRoot $LogDir
$workPath = Join-Path $repoRoot $WorkDir
$applyLog = Join-Path $logPath "apply.log"
$summaryLog = Join-Path $logPath "summary.txt"
$statusLog = Join-Path $logPath "git-status.txt"
$conflictLog = Join-Path $logPath "conflicts.txt"
$markerLog = Join-Path $logPath "conflict-markers.txt"
$metaFile = Join-Path $logPath "metadata.json"
$displaySource = if ([string]::IsNullOrWhiteSpace($SourceLabel)) { $UpstreamRef } else { $SourceLabel }

New-Item -ItemType Directory -Force -Path $logPath | Out-Null

if ($CleanWorkDir -and (Test-Path $workPath)) {
    Remove-Item -LiteralPath $workPath -Recurse -Force
}

if (Test-Path $workPath) {
    Remove-Item -LiteralPath $workPath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $workPath | Out-Null

Push-Location $workPath
try {
    git init | Out-Null
    git remote add upstream $UpstreamRemote
    git fetch --depth 1 upstream $UpstreamRef
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch upstream ref '$displaySource'."
    }

    $branchName = ($displaySource -replace '[^0-9A-Za-z._-]', '-')
    git checkout -b "release-$branchName" FETCH_HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to check out upstream ref '$displaySource'."
    }

    $upstreamCommit = (& git -C $workPath rev-parse HEAD 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstreamCommit)) {
        throw "Failed to resolve upstream commit SHA for '$displaySource'."
    }

    $upstreamCommitDate = (& git -C $workPath log -1 --format=%cI 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($upstreamCommitDate)) {
        throw "Failed to resolve upstream commit date for '$displaySource'."
    }

    $upstreamCommitSubject = (& git -C $workPath log -1 --format=%s 2>&1 | Select-Object -First 1).ToString().Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve upstream commit subject for '$displaySource'."
    }
} finally {
    Pop-Location
}

$patchFiles = @()
if (Test-Path $patchPath) {
    $patchFiles = Get-ChildItem $patchPath -Filter *.patch -File | Sort-Object Name
}

$metadata = [ordered]@{
    upstream_ref = $UpstreamRef
    source = $displaySource
    upstream_commit = $upstreamCommit
    upstream_commit_date = $upstreamCommitDate
    upstream_commit_subject = $upstreamCommitSubject
    worktree = $workPath
    patch_count = $patchFiles.Count
    status = "success"
}

if ($patchFiles.Count -eq 0) {
    Write-TextFile -Path $summaryLog -Content @(
        "No patch files were found in '$patchPath'.",
        "The worktree was prepared at upstream source '$displaySource' without applying any local patches."
    )
} else {
    $patchArgs = @(
        "-c", "user.name=github-actions[bot]",
        "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
        "-C", $workPath,
        "am",
        "--3way"
    ) + ($patchFiles | ForEach-Object { $_.FullName })

    $applyOutput = & git @patchArgs 2>&1
    Write-TextFile -Path $applyLog -Content @(
        "git $($patchArgs -join ' ')",
        ""
    ) + $applyOutput

    if ($LASTEXITCODE -ne 0) {
        $metadata.status = "patch_failed"

        $statusOutput = & git -C $workPath status --short 2>&1
        Write-TextFile -Path $statusLog -Content $statusOutput

        $conflictedFiles = @(& git -C $workPath diff --name-only --diff-filter=U 2>&1)
        Write-TextFile -Path $conflictLog -Content $conflictedFiles

        $markerOutput = @()
        if (Get-Command rg -ErrorAction SilentlyContinue) {
            $markerOutput = @(& rg -n "^(<<<<<<<|=======|>>>>>>>)" $workPath 2>&1)
        } else {
            $markerOutput = @("ripgrep not available; skipped conflict marker scan.")
        }
        Write-TextFile -Path $markerLog -Content $markerOutput

        Write-TextFile -Path $summaryLog -Content @(
            "Patch application failed for upstream source '$displaySource'.",
            "",
            "Conflicted files:"
        ) + $conflictedFiles + @(
            "",
            "See apply.log, git-status.txt, conflicts.txt, and conflict-markers.txt for details."
        )

        foreach ($relativePath in $conflictedFiles) {
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                continue
            }

            $sourcePath = Join-Path $workPath $relativePath
            if (-not (Test-Path $sourcePath)) {
                continue
            }

            $destinationPath = Join-Path (Join-Path $logPath "conflicted-files") $relativePath
            $destinationDir = Split-Path -Parent $destinationPath
            if ($destinationDir) {
                New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
            }
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }
    } else {
        Write-TextFile -Path $summaryLog -Content @(
            "Applied $($patchFiles.Count) patch(es) successfully to upstream source '$displaySource'.",
            "Prepared worktree: $workPath"
        )
    }
}

$metadata | ConvertTo-Json | Set-Content -LiteralPath $metaFile -Encoding utf8

if ($metadata.status -ne "success") {
    exit 1
}
