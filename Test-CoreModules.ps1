# Test-CoreModules.ps1
# Tests all 5 core modules using Claude's design
# Version: 2.0 (Claude-compatible)

Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TESTING CORE MODULES (Claude Design)" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ----- 1. Test Logger -----
Write-Host "1. Testing Logger.psm1..." -ForegroundColor White
try {
    Import-Module ".\Modules\Logger.psm1" -Force -ErrorAction Stop
    Write-Host "   ✅ Logger module imported" -ForegroundColor Green

    Initialize-Logger -LogPath ".\Logs\test.log" -Enabled $true
    Write-Host "   ✅ Logger initialized" -ForegroundColor Green

    Write-Log -Message "Test log message" -Level "Info"
    Write-Log -Message "Test warning" -Level "Warning"
    Write-Log -Message "Test error" -Level "Error"
    Write-Log -Message "Test success" -Level "Success"
    Write-Host "   ✅ Write-Log works" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Logger test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# ----- 2. Test Formatter -----
Write-Host "2. Testing Formatter.psm1..." -ForegroundColor White
try {
    Import-Module ".\Modules\Formatter.psm1" -Force -ErrorAction Stop
    Write-Host "   ✅ Formatter module imported" -ForegroundColor Green

    $testSizes = @(0, 1024, 1048576, 1073741824, 1099511627776)
    foreach ($size in $testSizes) {
        $result = Get-HumanReadableSize -Bytes $size
        Write-Host "   $size bytes = $result" -ForegroundColor Gray
    }
    Write-Host "   ✅ Get-HumanReadableSize works" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Formatter test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# ----- 3. Test Progress -----
Write-Host "3. Testing Progress.psm1..." -ForegroundColor White
try {
    Import-Module ".\Modules\Progress.psm1" -Force -ErrorAction Stop
    Write-Host "   ✅ Progress module imported" -ForegroundColor Green

    Write-ProgressEx -Activity "Test Activity" -Status "Testing progress..." -PercentComplete 50
    Write-Host "   ✅ Write-ProgressEx works" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Progress test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# ----- 4. Test Config -----
Write-Host "4. Testing Config.psm1..." -ForegroundColor White
try {
    Import-Module ".\Modules\Config.psm1" -Force -ErrorAction Stop
    Write-Host "   ✅ Config module imported" -ForegroundColor Green

    $config = Import-AppConfig -ConfigPath ".\Config\config.json"
    if ($config) {
        Write-Host "   ✅ Config loaded successfully" -ForegroundColor Green
        Write-Host "   Version: $($config.version)" -ForegroundColor Gray

        # Test Get-ConfigValue with dot-path
        $val = Get-ConfigValue -Config $config -Path "StorageAnalysis.StorageHeavyFileMB" -Default 500
        Write-Host "   ✅ Get-ConfigValue works: StorageHeavyFileMB = $val" -ForegroundColor Green

        $val2 = Get-ConfigValue -Config $config -Path "logging.level" -Default "Info"
        Write-Host "   ✅ Get-ConfigValue works: logging.level = $val2" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Config file not found (using defaults)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Config test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# ----- 5. Test Utils (Claude's Design) -----
Write-Host "5. Testing Utils.psm1..." -ForegroundColor White
try {
    Import-Module ".\Modules\Utils.psm1" -Force -ErrorAction Stop
    Write-Host "   ✅ Utils module imported" -ForegroundColor Green

    # Use Claude's design: pass THIS script's root, not Utils.psm1's root
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $paths = Initialize-ModulePaths -ModuleRoot $scriptRoot

    if ($paths) {
        Write-Host "   ✅ Initialize-ModulePaths works" -ForegroundColor Green
        Write-Host "   ProjectRoot: $($paths.ProjectRoot)" -ForegroundColor Gray
        Write-Host "   OutputCSV: $($paths.OutputCSV)" -ForegroundColor Gray
    }

    # Test Read-CsvSafely
    $testCsv = ".\Output\CSV\DriveUsage.csv"
    if (Test-Path $testCsv) {
        $data = Read-CsvSafely -Path $testCsv
        if ($data) {
            Write-Host "   ✅ Read-CsvSafely works: found $($data.Count) records" -ForegroundColor Green
        }
    } else {
        Write-Host "   ⚠️ No CSV found to test Read-CsvSafely (run Storage module first)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Utils test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST COMPLETE" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Check Logs\test.log for log file output" -ForegroundColor White