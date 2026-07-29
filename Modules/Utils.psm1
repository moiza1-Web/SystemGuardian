# SystemGuardian/Modules/Utils.psm1
# Core Utils Module – Shared utility functions
# Version: 1.0.2

function Initialize-ModulePaths {
    param(
        [string]$PSScriptRoot = $null   # Kept for compatibility with test script; ignored
    )
    # Auto-detect module location
    $moduleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $script:ModuleDir = $moduleDir
    $script:ProjectRoot = Split-Path -Parent $moduleDir
    $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"
    $script:OutputReports = Join-Path $script:ProjectRoot "Output\Reports"
    $script:OutputHTML = Join-Path $script:ProjectRoot "Output\HTML"
    $script:ConfigPath = Join-Path $script:ProjectRoot "Config\config.json"

    # Ensure directories exist
    @($script:OutputCSV, $script:OutputReports, $script:OutputHTML) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }

    return $true
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
