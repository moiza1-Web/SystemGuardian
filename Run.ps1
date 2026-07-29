# SystemGuardian/Run.ps1
# Main entry point with Config & Logging support
# Version: 1.0.0

param(
    [switch]$Help,
    [switch]$All,
    [switch]$Storage,
    [switch]$Duplicates,
    [switch]$SystemInfo,
    [switch]$Applications,
    [switch]$Browser,
    [switch]$ReviewAnalyzer,
    [switch]$Reports,
    [switch]$Dashboard,
    [switch]$OpenReport
)
# NOTE: -Security and -KaliScanner were removed. There is no Modules\Security.psm1
# or Modules\KaliScanner.psm1 in this repo, so those switches previously did
# nothing but log "module file not found." Add them back once those modules
# actually exist (see ROADMAP.md).

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------
# Global Variables
# -------------------------------
$script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:ScriptRoot "Config\config.json"
$script:LogPath = Join-Path $script:ScriptRoot "Logs\toolkit.log"
$script:ModulesPath = Join-Path $script:ScriptRoot "Modules"
$script:OutputPath = Join-Path $script:ScriptRoot "Output"

# -------------------------------
# Load Configuration
# -------------------------------
function Load-Configuration {
    if (-not (Test-Path $script:ConfigPath)) {
        Write-Warning "Config file not found at $script:ConfigPath. Using defaults."
        return $null
    }
    try {
        $config = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
        Write-Host "Config loaded successfully." -ForegroundColor Green
        return $config
    }
    catch {
        Write-Warning "Failed to load config: $($_.Exception.Message). Using defaults."
        return $null
    }
}

$script:Config = Load-Configuration

# -------------------------------
# Logging Functions
# -------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    # Console output (colored)
    $color = switch ($Level) {
        "Error"   { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        default   { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
    # Write to log file if logging enabled
    if ($script:Config -and $script:Config.logging.enabled -eq $true) {
        $logDir = Split-Path $script:LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
    }
}

# -------------------------------
# Other Functions (Banner, Help, etc.)
# -------------------------------
function Show-Banner {
    Clear-Host
    Write-Log "════════════════════════════════════════════════════════════" "Info"
    Write-Log "          SYSTEM GUARDIAN TOOLKIT v1.0.0                  " "Info"
    Write-Log "          Windows System Analysis Toolkit                  " "Info"
    Write-Log "════════════════════════════════════════════════════════════" "Info"
    Write-Log "Read-Only Mode: All operations are read-only" "Info"
    Write-Log "No modifications will be made to your system" "Info"
    Write-Host ""
}

function Show-Help {
    Show-Banner
    Write-Host "USAGE:" -ForegroundColor Cyan
    Write-Host "  .\Run.ps1 [Options]" -ForegroundColor White
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Cyan
    Write-Host "  -Help               Show this help" -ForegroundColor White
    Write-Host "  -All                Run all modules" -ForegroundColor White
    Write-Host "  -Storage            Run storage analysis" -ForegroundColor White
    Write-Host "  -Duplicates         Run duplicate file scan" -ForegroundColor White
    Write-Host "  -SystemInfo         Run system information collection" -ForegroundColor White
    Write-Host "  -Applications       Run installed application inventory" -ForegroundColor White
    Write-Host "  -Browser            Run browser analysis" -ForegroundColor White
    Write-Host "  -ReviewAnalyzer     Generate Smart Review recommendations" -ForegroundColor White
    Write-Host "  -Reports            Generate all reports" -ForegroundColor White
    Write-Host "  -Dashboard          Generate dashboard" -ForegroundColor White
    Write-Host "  -OpenReport         Open latest report" -ForegroundColor White
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Cyan
    Write-Host "  .\Run.ps1 -All                              # Run everything" -ForegroundColor White
    Write-Host "  .\Run.ps1 -Storage -Duplicates             # Run specific modules" -ForegroundColor White
    Write-Host "  .\Run.ps1 -Storage -Reports -OpenReport    # Run, report, open" -ForegroundColor White
}

function Initialize-Environment {
    Write-Log "Initializing environment..." "Info"
    # Create output directories
    $dirs = @(
        $script:OutputPath,
        (Join-Path $script:OutputPath "CSV"),
        (Join-Path $script:OutputPath "Reports"),
        (Join-Path $script:OutputPath "HTML"),
        (Join-Path $script:ScriptRoot "Logs")
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -Path $d -ItemType Directory -Force | Out-Null
            Write-Log "  Created directory: $d" "Success"
        }
    }
    # Validate PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.1 or higher required" "Error"
        exit 1
    }
    Write-Log "  PowerShell Version: $($PSVersionTable.PSVersion)" "Info"
    Write-Log "  OS: $([Environment]::OSVersion.VersionString)" "Info"
    Write-Log "Environment initialized." "Success"
}

function Import-ModuleSafely {
    param([string]$ModuleName)
    $moduleFile = "$ModuleName.psm1"
    $modulePath = Join-Path $script:ModulesPath $moduleFile
    if (-not (Test-Path $modulePath)) {
        Write-Log "Module file not found: $modulePath" "Error"
        return $false
    }
    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Log "  Imported module: $ModuleName" "Success"
        return $true
    }
    catch {
        Write-Log "Failed to import $ModuleName : $($_.Exception.Message)" "Error"
        return $false
    }
}

function Run-Module {
    param([string]$ModuleName)
    Write-Log "════════════════════════════════════════════════════════════" "Info"
    Write-Log "Running Module: $ModuleName" "Info"
    Write-Log "════════════════════════════════════════════════════════════" "Info"
    if (-not (Import-ModuleSafely $ModuleName)) { return }
    $functionName = "Invoke-$ModuleName"
    if (Get-Command $functionName -ErrorAction SilentlyContinue) {
        try {
            & $functionName
            Write-Log "Module $ModuleName completed successfully" "Success"
        }
        catch {
            Write-Log "Error executing $functionName : $($_.Exception.Message)" "Error"
            Write-Log "Stack trace: $($_.ScriptStackTrace)" "Error"
        }
    }
    else {
        Write-Log "Function $functionName not found" "Error"
    }
    Write-Host ""
}

function Open-Report {
    $reportDir = Join-Path $script:OutputPath "Reports"
    if (-not (Test-Path $reportDir)) {
        Write-Log "Reports directory not found" "Error"
        return
    }
    $reports = Get-ChildItem -Path $reportDir -Filter "SystemReport_*.html" | Sort-Object LastWriteTime -Descending
    if ($reports.Count -eq 0) {
        Write-Log "No reports found" "Warning"
        return
    }
    $latest = $reports[0]
    Write-Log "Opening report: $($latest.Name)" "Info"
    try {
        Start-Process $latest.FullName
        Write-Log "Report opened" "Success"
    }
    catch {
        Write-Log "Failed to open report: $($_.Exception.Message)" "Error"
    }
}

# -------------------------------
# Main Execution
# -------------------------------
try {
    Show-Banner
    if ($Help) {
        Show-Help
        exit 0
    }
    Initialize-Environment
    Write-Log "Session started" "Info"

    $hasModules = $All -or $Storage -or $Duplicates -or $SystemInfo -or $Applications -or $Browser -or $ReviewAnalyzer -or $Reports -or $Dashboard
    if (-not $hasModules) {
        Write-Log "No modules specified. Use -Help for usage." "Warning"
        exit 1
    }

    # Define module order (logical). ReviewAnalyzer must run AFTER Storage/Duplicates
    # since it reads their CSV output, and BEFORE Reports/Dashboard since those
    # consume ReviewRecommended.csv.
    $moduleOrder = @("Storage","Duplicates","SystemInfo","Applications","Browser","ReviewAnalyzer","Reports","Dashboard")
    # Map parameters to module names
    $paramMap = @{
        "Storage" = $Storage
        "Duplicates" = $Duplicates
        "SystemInfo" = $SystemInfo
        "Applications" = $Applications
        "Browser" = $Browser
        "ReviewAnalyzer" = $ReviewAnalyzer
        "Reports" = $Reports
        "Dashboard" = $Dashboard
    }

    if ($All) {
        Write-Log "Running ALL modules" "Info"
        foreach ($m in $moduleOrder) {
            if ($m -ne "Reports" -and $m -ne "Dashboard") {
                Run-Module $m
            }
        }
        # $All already implies these should run; the old "-or $All" checks here
        # were redundant since we're already inside the "if ($All)" branch.
        Run-Module "Reports"
        Run-Module "Dashboard"
    }
    else {
        foreach ($m in $moduleOrder) {
            if ($paramMap[$m] -eq $true) {
                Run-Module $m
            }
        }
    }

    if ($OpenReport) { Open-Report }

    Write-Log "════════════════════════════════════════════════════════════" "Info"
    Write-Log "System Guardian execution complete" "Success"
    Write-Log "════════════════════════════════════════════════════════════" "Info"
    Write-Log "Output directory: $script:OutputPath" "Info"
    Write-Log "Log file: $script:LogPath" "Info"
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "Error"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "Error"
    exit 1
}