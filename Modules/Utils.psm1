# SystemGuardian/Modules/Utils.psm1
# Core Utils Module – Shared utility functions
# Version: 1.0.2

function Initialize-ModulePaths {
    <#
    .SYNOPSIS
        Computes standard project paths and ensures output directories exist.
    .DESCRIPTION
        Returns a hashtable of paths. NOTE: this used to set $script: variables
        directly, but since this function lives in Utils.psm1, that only ever
        set variables in Utils.psm1's own module scope - not the calling
        module's scope - so it silently did nothing useful for callers. Fixed
        by returning a hashtable; each caller assigns the values into its own
        $script: variables (see Storage.psm1 etc. for the calling pattern).
    .PARAMETER ModuleRoot
        Pass the calling module's $PSScriptRoot so paths resolve correctly
        regardless of which module calls this function.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleRoot
    )

    $moduleDir = $ModuleRoot
    $projectRoot = Split-Path -Parent $moduleDir

    $paths = @{
        ModuleDir     = $moduleDir
        ProjectRoot   = $projectRoot
        OutputCSV     = Join-Path $projectRoot "Output\CSV"
        OutputReports = Join-Path $projectRoot "Output\Reports"
        OutputHTML    = Join-Path $projectRoot "Output\HTML"
        ConfigPath    = Join-Path $projectRoot "Config\config.json"
    }

    # Ensure directories exist
    @($paths.OutputCSV, $paths.OutputReports, $paths.OutputHTML) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    return $paths
}

function Read-CsvSafely {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            return Import-Csv -Path $Path
        } catch {
            return $null
        }
    }
    return $null
}

Export-ModuleMember -Function Initialize-ModulePaths, Read-CsvSafely