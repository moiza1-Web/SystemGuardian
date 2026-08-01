# SystemGuardian/Setup.ps1
# One-time setup script: verifies prerequisites, creates required folders,
# validates configuration, and optionally creates a Desktop shortcut.
# Read-only tool - this script only creates empty folders/shortcuts, it never
# touches, deletes, or modifies anything outside the SystemGuardian folder.
#
# Usage:
#   .\Setup.ps1                    # Run full setup, prompts for shortcut
#   .\Setup.ps1 -NoShortcut        # Skip the desktop shortcut prompt
#   .\Setup.ps1 -Silent            # No prompts, no shortcut, just verify+create folders

param(
    [switch]$NoShortcut,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = $PSScriptRoot
$script:HasWarnings = $false

function Write-Step {
    param([string]$Message, [string]$Status = "Info")
    $prefix = switch ($Status) {
        "OK"      { "[  OK  ]" }
        "WARN"    { "[ WARN ]" }
        "FAIL"    { "[ FAIL ]" }
        default   { "[ .... ]" }
    }
    $color = switch ($Status) {
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "FAIL"  { "Red" }
        default { "White" }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  System Guardian - Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ----- 1. PowerShell version check -----
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -gt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -ge 1)) {
    Write-Step "PowerShell version: $psVersion" "OK"
} else {
    Write-Step "PowerShell version: $psVersion (5.1+ required)" "FAIL"
    $script:HasWarnings = $true
}

# ----- 2. Windows version check -----
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $caption = $os.Caption
    if ($caption -match "Windows 10|Windows 11") {
        Write-Step "Operating System: $caption" "OK"
    } else {
        Write-Step "Operating System: $caption (only tested on Windows 10/11)" "WARN"
        $script:HasWarnings = $true
    }
} catch {
    Write-Step "Could not detect OS version - continuing anyway" "WARN"
    $script:HasWarnings = $true
}

# ----- 3. Required folders -----
$requiredFolders = @(
    "Output\CSV",
    "Output\HTML",
    "Output\Reports",
    "Logs"
)

foreach ($folder in $requiredFolders) {
    $fullPath = Join-Path $script:ProjectRoot $folder
    if (Test-Path $fullPath) {
        Write-Step "Folder exists: $folder" "OK"
    } else {
        try {
            New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
            Write-Step "Created folder: $folder" "OK"
        } catch {
            Write-Step "Could not create folder: $folder - $($_.Exception.Message)" "FAIL"
            $script:HasWarnings = $true
        }
    }
}

# ----- 4. Config.json validation -----
$configPath = Join-Path $script:ProjectRoot "Config\config.json"
if (Test-Path $configPath) {
    try {
        $null = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        Write-Step "Config\config.json is present and valid JSON" "OK"
    } catch {
        Write-Step "Config\config.json exists but is not valid JSON: $($_.Exception.Message)" "FAIL"
        $script:HasWarnings = $true
    }
} else {
    Write-Step "Config\config.json not found - modules will fall back to built-in defaults" "WARN"
    $script:HasWarnings = $true
}

# ----- 5. Core modules present -----
$coreModules = @("Logger.psm1", "Formatter.psm1", "Progress.psm1", "Config.psm1", "Utils.psm1")
$missingCore = @()
foreach ($cm in $coreModules) {
    $cmPath = Join-Path $script:ProjectRoot "Modules\$cm"
    if (-not (Test-Path $cmPath)) {
        $missingCore += $cm
    }
}
if ($missingCore.Count -eq 0) {
    Write-Step "All 5 Core shared modules present" "OK"
} else {
    Write-Step "Missing Core modules: $($missingCore -join ', ')" "FAIL"
    $script:HasWarnings = $true
}

# ----- 6. Optional Desktop shortcut -----
if (-not $NoShortcut -and -not $Silent) {
    Write-Host ""
    $answer = Read-Host "Create a Desktop shortcut to run System Guardian? (y/N)"
    if ($answer -match "^[Yy]") {
        try {
            $desktopPath = [Environment]::GetFolderPath("Desktop")
            $shortcutPath = Join-Path $desktopPath "System Guardian.lnk"
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = "powershell.exe"
            $shortcut.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $script:ProjectRoot 'Run.ps1')`" -All"
            $shortcut.WorkingDirectory = $script:ProjectRoot
            $shortcut.Description = "System Guardian - Windows System Analysis Toolkit"
            $shortcut.Save()
            Write-Step "Desktop shortcut created: $shortcutPath" "OK"
        } catch {
            Write-Step "Could not create desktop shortcut: $($_.Exception.Message)" "WARN"
        }
    }
}

# ----- Summary -----
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($script:HasWarnings) {
    Write-Host "  Setup finished with warnings - review above" -ForegroundColor Yellow
} else {
    Write-Host "  Setup complete - System Guardian is ready" -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  .\Run.ps1 -All       Run a full scan" -ForegroundColor Gray
Write-Host "  .\Run.ps1 -Help      See all available options" -ForegroundColor Gray
Write-Host ""