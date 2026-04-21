param(
    [string]$ProjectDir = ".release-worktree",
    [string]$GradleFile = "app/build.gradle.kts",
    [string]$ExpectedVersionName = "",
    [string]$GitHubOutputPath = ""
)

$ErrorActionPreference = "Stop"

function Write-OutputValue {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($GitHubOutputPath)) {
        Write-Output "$Name=$Value"
        return
    }

    "$Name=$Value" | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$projectPath = Join-Path $repoRoot $ProjectDir
$gradlePath = Join-Path $projectPath $GradleFile

if (-not (Test-Path $gradlePath)) {
    throw "Gradle file '$gradlePath' does not exist."
}

$content = Get-Content -LiteralPath $gradlePath -Raw

$versionNameMatch = [regex]::Match($content, 'versionName\s*=\s*"([^"]+)"')
if (-not $versionNameMatch.Success) {
    throw "Could not find versionName in '$gradlePath'."
}

$versionCodeMatch = [regex]::Match($content, 'versionCode\s*=\s*(\d+)')
if (-not $versionCodeMatch.Success) {
    throw "Could not find versionCode in '$gradlePath'."
}

$versionName = $versionNameMatch.Groups[1].Value
$versionCode = $versionCodeMatch.Groups[1].Value

if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionName) -and $versionName -ne $ExpectedVersionName) {
    throw "Patched worktree versionName '$versionName' does not match expected upstream version '$ExpectedVersionName'."
}

Write-OutputValue -Name "app_version_name" -Value $versionName
Write-OutputValue -Name "app_version_code" -Value $versionCode
