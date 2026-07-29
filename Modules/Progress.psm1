# SystemGuardian/Core/Progress.psm1
# Shared progress-reporting wrapper used across every analysis module.
# Extracted from the identical copies previously embedded in every
# Modules/*.psm1 file.
# Version: 1.0.0

<#
.SYNOPSIS
    Thin wrapper around Write-Progress with an optional percent complete.
.DESCRIPTION
    Behavior is unchanged from the per-module copies this replaces: if
    PercentComplete is -1 (the default), Write-Progress is called
    without a percentage (indeterminate); otherwise the percentage is
    passed through as-is.
.PARAMETER Activity
    The activity name shown in the progress bar.
.PARAMETER Status
    The current status text shown in the progress bar.
.PARAMETER PercentComplete
    0-100, or -1 (default) to omit the percentage.
.EXAMPLE
    Write-ProgressEx -Activity "Storage Analysis" -Status "Scanning..." -PercentComplete 25
#>
function Write-ProgressEx {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1
    )
    if ($PercentComplete -ge 0) {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    } else {
        Write-Progress -Activity $Activity -Status $Status
    }
}

Export-ModuleMember -Function Write-ProgressEx
