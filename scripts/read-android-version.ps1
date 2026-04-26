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

function Parse-SemanticVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $trimmed = $Version.Trim()
    $match = [regex]::Match($trimmed, '^[vV]?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$')
    if (-not $match.Success) {
        throw "Version '$Version' is not a supported semantic version."
    }

    return [pscustomobject]@{
        Major = [int]$match.Groups[1].Value
        Minor = [int]$match.Groups[2].Value
        Patch = [int]$match.Groups[3].Value
    }
}

function Compare-SemanticVersions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LeftVersion,
        [Parameter(Mandatory = $true)]
        [string]$RightVersion
    )

    $left = Parse-SemanticVersion -Version $LeftVersion
    $right = Parse-SemanticVersion -Version $RightVersion

    foreach ($property in @("Major", "Minor", "Patch")) {
        if ($left.$property -lt $right.$property) {
            return -1
        }

        if ($left.$property -gt $right.$property) {
            return 1
        }
    }

    return 0
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

if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionName)) {
    $comparison = Compare-SemanticVersions -LeftVersion $versionName -RightVersion $ExpectedVersionName
    if ($comparison -lt 0) {
        Write-Host "Patched worktree versionName '$versionName' is older than expected upstream version '$ExpectedVersionName'. Continuing with the resolved app version release check because upstream tags may lead the in-source versionName."
    } elseif ($comparison -gt 0) {
        Write-Host "Patched worktree versionName '$versionName' is newer than expected upstream version '$ExpectedVersionName'. Continuing with the resolved app version release check."
    }
}

Write-OutputValue -Name "app_version_name" -Value $versionName
Write-OutputValue -Name "app_version_code" -Value $versionCode
