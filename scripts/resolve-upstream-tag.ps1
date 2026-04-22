param(
    [string]$RequestedTag = "",
    [string]$SourceMode = "tag",
    [string]$RequestedRef = "",
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

$normalizedSourceMode = $SourceMode.Trim().ToLowerInvariant()
if ($normalizedSourceMode -notin @("tag", "master", "ref")) {
    throw "Unsupported SourceMode '$SourceMode'. Expected 'tag', 'master', or 'ref'."
}

$upstreamTag = if ([string]::IsNullOrWhiteSpace($RequestedTag)) {
    Get-LatestStableTag -Remote $UpstreamRemote
} else {
    $RequestedTag.Trim()
}

$normalizedVersion = Get-NormalizedVersion -Tag $upstreamTag
$resolvedTarget = ""
$checkoutRef = ""

if ($normalizedSourceMode -eq "master") {
    $checkoutRef = "refs/heads/master"
    $resolvedTarget = "master"
} elseif ($normalizedSourceMode -eq "tag") {
    $checkoutRef = "refs/tags/$upstreamTag"
    $resolvedTarget = $upstreamTag
} else {
    if ([string]::IsNullOrWhiteSpace($RequestedRef)) {
        throw "RequestedRef is required when SourceMode is 'ref'."
    }
    $checkoutRef = $RequestedRef.Trim()
    $resolvedTarget = $checkoutRef
}

if ([string]::IsNullOrWhiteSpace($checkoutRef)) {
    throw "Failed to resolve an upstream ref for SourceMode '$SourceMode'."
}

Write-OutputValue -Name "source_mode" -Value $normalizedSourceMode
Write-OutputValue -Name "upstream_tag" -Value $upstreamTag
Write-OutputValue -Name "normalized_upstream_version" -Value $normalizedVersion
Write-OutputValue -Name "checkout_ref" -Value $checkoutRef
Write-OutputValue -Name "resolved_target" -Value $resolvedTarget
