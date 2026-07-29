# SystemGuardian/Core/Formatter.psm1
# Shared formatting helpers used across every analysis module.
# Extracted from the identical copies previously embedded in
# Storage.psm1, Duplicates.psm1, SystemInfo.psm1, Applications.psm1,
# Browser.psm1, ReviewAnalyzer.psm1, Reports.psm1, and Dashboard.psm1.
# Version: 1.0.0

<#
.SYNOPSIS
    Converts a byte count into a human-readable string (B, KB, MB, GB, TB, PB).
.DESCRIPTION
    Behavior is unchanged from the per-module copies this replaces:
    negative or zero byte counts return "0 B", and values are formatted
    to two decimal places with the largest whole unit that keeps the
    number under 1024.
.PARAMETER Bytes
    The byte count to format.
.EXAMPLE
    Get-HumanReadableSize -Bytes 1548576
#>
function Get-HumanReadableSize {
    param([long]$Bytes)

    if ($Bytes -lt 0) { return "0 B" }
    if ($Bytes -eq 0) { return "0 B" }

    $sizes = @("B", "KB", "MB", "GB", "TB", "PB")
    $index = 0
    $size = [double]$Bytes
    while ($size -ge 1024 -and $index -lt $sizes.Length - 1) {
        $size /= 1024
        $index++
    }
    return "{0:N2} {1}" -f $size, $sizes[$index]
}

Export-ModuleMember -Function Get-HumanReadableSize
