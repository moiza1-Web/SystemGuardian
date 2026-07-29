# SystemGuardian/Core/Logger.psm1
# Shared logging used across every analysis module.
# Extracted from the console-only copies previously embedded in every
# Modules/*.psm1 file, and unified with the fuller console+file version
# that previously only existed in Run.ps1.
# Version: 1.0.0

# Module-scoped state, set via Initialize-Logger. If a caller never
# initializes, these stay $null/$false and Write-Log behaves exactly
# like the old per-module console-only copies did.
$script:LogFilePath = $null
$script:LoggingEnabled = $false

<#
.SYNOPSIS
    Configures file logging for this module instance.
.DESCRIPTION
    Call once per session (Run.ps1 does this at startup). If never
    called, Write-Log still works and writes to the console only -
    identical to the behavior every individual module had before this
    refactor.
.PARAMETER LogPath
    Full path to the log file.
.PARAMETER Enabled
    Whether file logging is turned on (typically read from config.json).
#>
function Initialize-Logger {
    param(
        [string]$LogPath,
        [bool]$Enabled = $false
    )
    $script:LogFilePath = $LogPath
    $script:LoggingEnabled = $Enabled
}

<#
.SYNOPSIS
    Writes a timestamped, color-coded log entry to the console, and to
    the log file too if Initialize-Logger has enabled it.
.PARAMETER Message
    The message to log.
.PARAMETER Level
    One of Info, Warning, Error, Success (default: Info).
#>
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "Error"   { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color

    if ($script:LoggingEnabled -and $script:LogFilePath) {
        try {
            $logDir = Split-Path $script:LogFilePath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $script:LogFilePath -Value $logEntry -ErrorAction SilentlyContinue
        } catch { }
    }
}

Export-ModuleMember -Function Initialize-Logger, Write-Log
