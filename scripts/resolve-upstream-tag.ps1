param(
    [string]$RequestedTag = "",
    [string]$UpstreamRemote = "https://github.com/rikkahub/rikkahub.git",
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

function Get-NormalizedVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    $normalized = $Tag.Trim()
    $normalized = $normalized -replace '^[vV]', ''
    return $normalized
}

function Get-LatestStableTag {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Remote
    )

    $lines = & git ls-remote --tags --refs $Remote 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list tags from '$Remote'.`n$($lines -join "`n")"
    }

    $candidates = foreach ($line in $lines) {
        if ($line -notmatch 'refs/tags/(.+)$') {
            continue
        }

        $tag = $Matches[1].Trim()
        if ($tag -notmatch '^[vV]?(\d+)\.(\d+)\.(\d+)$') {
            continue
        }

        [pscustomobject]@{
            Tag = $tag
            Major = [int]$Matches[1]
            Minor = [int]$Matches[2]
            Patch = [int]$Matches[3]
        }
    }

    $latest = $candidates |
        Sort-Object Major, Minor, Patch |
        Select-Object -Last 1

    if ($null -eq $latest) {
        throw "No stable semantic version tags were found in '$Remote'."
    }

    return $latest.Tag
}

$upstreamTag = if ([string]::IsNullOrWhiteSpace($RequestedTag)) {
    Get-LatestStableTag -Remote $UpstreamRemote
} else {
    $RequestedTag.Trim()
}

$normalizedVersion = Get-NormalizedVersion -Tag $upstreamTag

Write-OutputValue -Name "upstream_tag" -Value $upstreamTag
Write-OutputValue -Name "normalized_upstream_version" -Value $normalizedVersion
Write-OutputValue -Name "release_tag" -Value "patched-$normalizedVersion"
Write-OutputValue -Name "artifact_name" -Value "rikkahub-patched-$normalizedVersion"
