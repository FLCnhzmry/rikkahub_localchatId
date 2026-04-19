param(
    [string]$ProjectDir = ".release-worktree",
    [string]$LogDir = ".release-logs",
    [string]$GradleTask = "assembleRelease"
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

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$projectPath = Join-Path $repoRoot $ProjectDir
$logPath = Join-Path $repoRoot $LogDir
$buildLog = Join-Path $logPath "build.log"
$summaryLog = Join-Path $logPath "build-summary.txt"

if (-not (Test-Path $projectPath)) {
    throw "Project directory '$projectPath' does not exist."
}

$gradlew = if ($IsWindows) {
    Join-Path $projectPath "gradlew.bat"
} else {
    Join-Path $projectPath "gradlew"
}

if (-not (Test-Path $gradlew)) {
    throw "Gradle wrapper not found at '$gradlew'."
}

Push-Location $projectPath
try {
    if (-not $IsWindows) {
        chmod +x $gradlew
    }

    $output = & $gradlew $GradleTask 2>&1
    Write-TextFile -Path $buildLog -Content @(
        "$gradlew $GradleTask",
        ""
    ) + $output

    if ($LASTEXITCODE -ne 0) {
        Write-TextFile -Path $summaryLog -Content @(
            "Build failed while running '$GradleTask'.",
            "See build.log for the full output."
        )
        exit 1
    }

    Write-TextFile -Path $summaryLog -Content @(
        "Build completed successfully with '$GradleTask'."
    )
} finally {
    Pop-Location
}
