# SystemGuardian/Modules/Reports.psm1
# Report Generator – Creates professional HTML report from all CSV data
# Version: 1.1.0 (now uses shared Core modules instead of local copies)

Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Utils.psm1") -Force

function Invoke-Reports {
    <#
    .SYNOPSIS
        Generates a comprehensive HTML report from all analysis data
    .DESCRIPTION
        Reads all CSV files from Output/CSV and creates a professional HTML dashboard
        with dark theme, charts, tables, and statistics
    #>

    # ----- Path Setup -----
    # Compute ProjectRoot/OutputCSV first (without creating anything) so we
    # can preserve the original behavior: bail out with a warning if the CSV
    # output from earlier modules doesn't exist yet, rather than silently
    # creating an empty folder and proceeding.
    $script:ModuleDir = $PSScriptRoot
    $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
    $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"

    if (-not (Test-Path $script:OutputCSV)) {
        Write-Warning "No CSV data found. Run Storage and other modules first."
        return $false
    }

    $paths = Initialize-ModulePaths -ModuleRoot $PSScriptRoot
    $script:OutputReports = $paths.OutputReports

    # Write-Log and Write-ProgressEx now come from Logger.psm1 and
    # Progress.psm1 (imported above). The old local Get-HumanReadableSize
    # was dead code here (defined but never called in this file), so it's
    # simply removed rather than imported from Formatter.psm1.

    Write-Log "Starting Report Generation" "Info"

    # ----- Helper: Read CSV safely -----
    # Read-CsvSafely now comes from Utils.psm1 (imported above).

    Write-ProgressEx -Activity "Report Generation" -Status "Loading data..." -PercentComplete 10

    # ----- Load all data -----
    $driveUsage = Read-CsvSafely (Join-Path $script:OutputCSV "DriveUsage.csv")
    $largeFiles = Read-CsvSafely (Join-Path $script:OutputCSV "LargeFiles.csv")
    $largeFolders = Read-CsvSafely (Join-Path $script:OutputCSV "LargeFolders.csv")
    $emptyFolders = Read-CsvSafely (Join-Path $script:OutputCSV "EmptyFolders.csv")
    $oldFiles = Read-CsvSafely (Join-Path $script:OutputCSV "OldFiles.csv")
    $largeArchives = Read-CsvSafely (Join-Path $script:OutputCSV "LargeArchives.csv")
    $largeISOs = Read-CsvSafely (Join-Path $script:OutputCSV "LargeISOs.csv")
    $tempFiles = Read-CsvSafely (Join-Path $script:OutputCSV "TempFiles.csv")
    $browserCache = Read-CsvSafely (Join-Path $script:OutputCSV "BrowserCache.csv")
    $duplicates = Read-CsvSafely (Join-Path $script:OutputCSV "Duplicates.csv")
    $systemInfo = Read-CsvSafely (Join-Path $script:OutputCSV "SystemInfo.csv")
    $installedApps = Read-CsvSafely (Join-Path $script:OutputCSV "InstalledApps.csv")
    $recommendations = Read-CsvSafely (Join-Path $script:OutputCSV "ReviewRecommended.csv")
    $storageSummary = Read-CsvSafely (Join-Path $script:OutputCSV "StorageSummary.csv")

    Write-ProgressEx -Activity "Report Generation" -Status "Building HTML..." -PercentComplete 30

    # ----- Build Summary Statistics -----
    $totalDriveSpace = 0
    $totalFreeSpace = 0
    if ($driveUsage) {
        foreach ($d in $driveUsage) {
            $totalDriveSpace += [long]$d.TotalSize
            $totalFreeSpace += [long]$d.FreeSpace
        }
    }
    $totalUsedSpace = $totalDriveSpace - $totalFreeSpace
    $overallUsagePercent = if ($totalDriveSpace -gt 0) { [math]::Round(($totalUsedSpace / $totalDriveSpace) * 100, 1) } else { 0 }

    $totalLargeFiles = if ($largeFiles) { $largeFiles.Count } else { 0 }
    $totalLargeFolders = if ($largeFolders) { $largeFolders.Count } else { 0 }
    $totalDuplicates = if ($duplicates) { ($duplicates | Group-Object GroupID).Count } else { 0 }
    $totalRecommendations = if ($recommendations) { $recommendations.Count } else { 0 }

    Write-ProgressEx -Activity "Report Generation" -Status "Generating report..." -PercentComplete 50

    # ----- Generate HTML Content -----
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $filename = "SystemReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $reportPath = Join-Path $script:OutputReports $filename

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Guardian Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 {
            font-size: 28px;
            font-weight: 600;
            color: #f0f6fc;
            border-bottom: 2px solid #30363d;
            padding-bottom: 15px;
            margin-bottom: 25px;
        }
        h1 small {
            font-size: 14px;
            font-weight: 400;
            color: #8b949e;
            margin-left: 15px;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 25px;
        }
        .card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 8px;
            padding: 18px 20px;
            transition: 0.2s;
        }
        .card:hover { border-color: #58a6ff; }
        .card .label { font-size: 12px; text-transform: uppercase; color: #8b949e; letter-spacing: 0.5px; }
        .card .value { font-size: 26px; font-weight: 600; color: #f0f6fc; margin-top: 4px; }
        .card .sub { font-size: 13px; color: #8b949e; margin-top: 2px; }
        .card.danger .value { color: #f85149; }
        .card.warning .value { color: #d29922; }
        .card.success .value { color: #3fb950; }
        .card.info .value { color: #58a6ff; }
        .section {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 25px;
            overflow-x: auto;
        }
        .section h2 {
            font-size: 18px;
            font-weight: 600;
            color: #f0f6fc;
            margin-bottom: 15px;
        }
        .section h2 span {
            font-size: 13px;
            font-weight: 400;
            color: #8b949e;
            margin-left: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }
        table th {
            text-align: left;
            padding: 10px 12px;
            background: #0d1117;
            color: #8b949e;
            font-weight: 600;
            border-bottom: 2px solid #30363d;
            position: sticky;
            top: 0;
        }
        table td {
            padding: 8px 12px;
            border-bottom: 1px solid #21262d;
            vertical-align: middle;
        }
        table tr:hover td { background: #1c2128; }
        table .highlight { color: #f0883e; font-weight: 500; }
        .badge {
            display: inline-block;
            font-size: 11px;
            padding: 2px 10px;
            border-radius: 20px;
            font-weight: 500;
        }
        .badge.high { background: #da3633; color: #fff; }
        .badge.medium { background: #d29922; color: #fff; }
        .badge.low { background: #238636; color: #fff; }
        .badge.info { background: #1f6feb; color: #fff; }
        .progress-bar {
            width: 100%;
            height: 8px;
            background: #21262d;
            border-radius: 4px;
            overflow: hidden;
            margin-top: 4px;
        }
        .progress-bar .fill {
            height: 100%;
            border-radius: 4px;
            background: #58a6ff;
            transition: width 0.5s;
        }
        .progress-bar .fill.danger { background: #f85149; }
        .progress-bar .fill.warning { background: #d29922; }
        .progress-bar .fill.success { background: #3fb950; }
        .flex { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
        .mt-2 { margin-top: 12px; }
        .text-center { text-align: center; }
        .text-muted { color: #8b949e; font-size: 13px; }
        .text-right { text-align: right; }
        .status-ok { color: #3fb950; }
        .status-warn { color: #d29922; }
        .status-danger { color: #f85149; }
        @media (max-width: 768px) {
            .grid { grid-template-columns: 1fr 1fr; }
            table { font-size: 12px; }
            table th, table td { padding: 6px 8px; }
            .card .value { font-size: 20px; }
        }
        @media (max-width: 480px) {
            .grid { grid-template-columns: 1fr; }
        }
        .footer {
            text-align: center;
            padding: 20px 0 10px;
            color: #8b949e;
            font-size: 13px;
            border-top: 1px solid #30363d;
            margin-top: 10px;
        }
        .footer a { color: #58a6ff; text-decoration: none; }
        .footer a:hover { text-decoration: underline; }
    </style>
</head>
<body>
<div class="container">

    <h1>🛡️ System Guardian <small>System Analysis Report</small></h1>
    <p style="color: #8b949e; margin-bottom: 20px;">Generated: $timestamp</p>

    <!-- Summary Cards -->
    <div class="grid">
        <div class="card">
            <div class="label">Total Drives</div>
            <div class="value">$($driveUsage.Count)</div>
            <div class="sub">$([math]::Round($totalDriveSpace / 1GB, 1)) GB total</div>
        </div>
        <div class="card danger">
            <div class="label">Used Space</div>
            <div class="value">$([math]::Round($totalUsedSpace / 1GB, 1)) GB</div>
            <div class="sub">$overallUsagePercent% used</div>
            <div class="progress-bar"><div class="fill danger" style="width: $overallUsagePercent%;"></div></div>
        </div>
        <div class="card success">
            <div class="label">Free Space</div>
            <div class="value">$([math]::Round($totalFreeSpace / 1GB, 1)) GB</div>
            <div class="sub">Available for use</div>
        </div>
        <div class="card info">
            <div class="label">Large Files</div>
            <div class="value">$totalLargeFiles</div>
            <div class="sub">> 500 MB each</div>
        </div>
        <div class="card warning">
            <div class="label">Duplicates</div>
            <div class="value">$totalDuplicates</div>
            <div class="sub">Groups detected</div>
        </div>
        <div class="card danger">
            <div class="label">Recommendations</div>
            <div class="value">$totalRecommendations</div>
            <div class="sub">Actionable insights</div>
        </div>
    </div>

    <!-- Drive Usage -->
    <div class="section">
        <h2>💾 Drive Usage <span>Overview</span></h2>
        <table>
            <thead><tr><th>Drive</th><th>Label</th><th>Total</th><th>Used</th><th>Free</th><th>Usage</th></tr></thead>
            <tbody>
"@

    if ($driveUsage) {
        foreach ($d in $driveUsage) {
            $percent = [math]::Round([double]$d.PercentUsed, 1)
            $statusClass = if ($percent -gt 90) { "danger" } elseif ($percent -gt 70) { "warning" } else { "success" }
            $htmlContent += @"
                <tr>
                    <td><strong>$($d.Drive)</strong></td>
                    <td>$($d.Label)</td>
                    <td>$($d.TotalSizeHuman)</td>
                    <td>$($d.UsedSpaceHuman)</td>
                    <td>$($d.FreeSpaceHuman)</td>
                    <td>
                        <span class="status-$statusClass">$percent%</span>
                        <div class="progress-bar"><div class="fill $statusClass" style="width: $percent%;"></div></div>
                    </td>
                </tr>
"@
        }
    } else {
        $htmlContent += '<tr><td colspan="6" class="text-muted text-center">No drive data available</td></tr>'
    }

    $htmlContent += @"
            </tbody>
        </table>
    </div>

    <!-- Recommendations -->
    <div class="section">
        <h2>💡 Recommendations <span>Actionable insights</span></h2>
"@

    if ($recommendations -and $recommendations.Count -gt 0) {
        $htmlContent += @'
        <table>
            <thead><tr><th>Priority</th><th>Category</th><th>Item</th><th>Size</th><th>Reason</th></tr></thead>
            <tbody>
'@
        foreach ($r in $recommendations) {
            $badge = if ($r.Priority -eq "High") { 'high' } elseif ($r.Priority -eq "Medium") { 'medium' } else { 'low' }
            $htmlContent += @"
                <tr>
                    <td><span class="badge $badge">$($r.Priority)</span></td>
                    <td>$($r.Category)</td>
                    <td><strong>$($r.Item)</strong></td>
                    <td>$($r.SizeHuman)</td>
                    <td style="font-size:12px;color:#8b949e;">$($r.Reason)</td>
                </tr>
"@
        }
        $htmlContent += '</tbody></table>'
    } else {
        $htmlContent += '<p class="text-muted">No recommendations available. Run ReviewAnalyzer first.</p>'
    }

    $htmlContent += @"
    </div>

    <!-- Large Files -->
    <div class="section">
        <h2>📄 Largest Files <span>Top 20</span></h2>
"@

    if ($largeFiles -and $largeFiles.Count -gt 0) {
        $htmlContent += '<table><thead><tr><th>#</th><th>Name</th><th>Size</th><th>Location</th></tr></thead><tbody>'
        $counter = 1
        $topFiles = $largeFiles | Select-Object -First 20
        foreach ($f in $topFiles) {
            $htmlContent += @"
                <tr>
                    <td>$counter</td>
                    <td>$($f.Name)</td>
                    <td><span class="highlight">$($f.SizeHuman)</span></td>
                    <td style="font-size:12px;color:#8b949e;">$($f.Directory)</td>
                </tr>
"@
            $counter++
        }
        $htmlContent += '</tbody></table>'
    } else {
        $htmlContent += '<p class="text-muted">No large files found.</p>'
    }

    $htmlContent += @"
    </div>

    <!-- Large Folders -->
    <div class="section">
        <h2>📁 Largest Folders <span>Top 15</span></h2>
"@

    if ($largeFolders -and $largeFolders.Count -gt 0) {
        $htmlContent += '<table><thead><tr><th>#</th><th>Name</th><th>Size</th><th>Items</th></tr></thead><tbody>'
        $counter = 1
        $topFolders = $largeFolders | Select-Object -First 15
        foreach ($f in $topFolders) {
            $htmlContent += @"
                <tr>
                    <td>$counter</td>
                    <td>$($f.Name)</td>
                    <td><span class="highlight">$($f.SizeHuman)</span></td>
                    <td>$($f.Items)</td>
                </tr>
"@
            $counter++
        }
        $htmlContent += '</tbody></table>'
    } else {
        $htmlContent += '<p class="text-muted">No large folders found.</p>'
    }

    $htmlContent += @"
    </div>

    <!-- Duplicates -->
    <div class="section">
        <h2>🔁 Duplicate Files <span>Groups</span></h2>
"@

    if ($duplicates -and $duplicates.Count -gt 0) {
        $groups = $duplicates | Group-Object GroupID
        $htmlContent += '<table><thead><tr><th>Group</th><th>Files</th><th>Total Size</th><th>Sample File</th></tr></thead><tbody>'
        $counter = 1
        foreach ($g in $groups) {
            $first = $g.Group | Select-Object -First 1
            $htmlContent += @"
                <tr>
                    <td>$counter</td>
                    <td>$($first.TotalInGroup)</td>
                    <td><span class="highlight">$($first.GroupTotalSizeHuman)</span></td>
                    <td style="font-size:12px;color:#8b949e;">$($first.FileName)</td>
                </tr>
"@
            $counter++
            if ($counter -gt 20) { break }
        }
        $htmlContent += '</tbody></table>'
    } else {
        $htmlContent += '<p class="text-muted">No duplicate files found. Run Duplicates module first.</p>'
    }

    $htmlContent += @"
    </div>

    <!-- Browser Cache -->
    <div class="section">
        <h2>🌐 Browser Cache <span>By browser</span></h2>
"@

    if ($browserCache -and $browserCache.Count -gt 0) {
        $htmlContent += '<table><thead><tr><th>Browser</th><th>Profile</th><th>Cache Size</th></tr></thead><tbody>'
        foreach ($b in $browserCache) {
            $htmlContent += @"
                <tr>
                    <td><strong>$($b.Browser)</strong></td>
                    <td>$($b.Profile)</td>
                    <td>$($b.TotalCacheSizeHuman)</td>
                </tr>
"@
        }
        $htmlContent += '</tbody></table>'
    } else {
        $htmlContent += '<p class="text-muted">No browser cache data available.</p>'
    }

    $htmlContent += @"
    </div>

    <!-- System Info -->
    <div class="section">
        <h2>🖥️ System Information <span>Hardware & OS</span></h2>
"@

    if ($systemInfo -and $systemInfo.Count -gt 0) {
        $htmlContent += '<table><thead><tr><th>Category</th><th>Property</th><th>Value</th></tr></thead><tbody>'
        foreach ($s in $systemInfo) {
            $htmlContent += @"
                <tr>
                    <td>$($s.Category)</td>
                    <td>$($s.Property)</td>
                    <td>$($s.Value)</td>
                </tr>
"@
        }
        $htmlContent += '</tbody></table>'
    } else {
        $htmlContent += '<p class="text-muted">No system information available. Run SystemInfo module first.</p>'
    }

    $htmlContent += @"
    </div>

    <!-- Footer -->
    <div class="footer">
        <p>System Guardian v1.0 &bull; Generated on $timestamp &bull; <a href="#" onclick="window.print()">Print</a> &bull; <a href="#" onclick="window.close()">Close</a></p>
        <p style="font-size:12px;">Read-only &bull; Privacy-first &bull; No data modification</p>
    </div>

</div>
</body>
</html>
"@

    Write-ProgressEx -Activity "Report Generation" -Status "Saving report..." -PercentComplete 90

    # ----- Save HTML report -----
    $htmlContent | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Saved $filename" "Success"

    # ----- Also generate a CSV summary report -----
    $summaryReport = Join-Path $script:OutputCSV "ReportSummary.csv"
    $summaryData = [PSCustomObject]@{
        Timestamp = $timestamp
        TotalDrives = if ($driveUsage) { $driveUsage.Count } else { 0 }
        TotalLargeFiles = $totalLargeFiles
        TotalLargeFolders = $totalLargeFolders
        TotalDuplicates = $totalDuplicates
        TotalRecommendations = $totalRecommendations
        TotalDriveSpaceGB = [math]::Round($totalDriveSpace / 1GB, 1)
        TotalFreeSpaceGB = [math]::Round($totalFreeSpace / 1GB, 1)
        OverallUsagePercent = $overallUsagePercent
    }
    $summaryData | Export-Csv -Path $summaryReport -NoTypeInformation

    Write-ProgressEx -Activity "Report Generation" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "Report Generation" -Completed

    # ----- Display Summary -----
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "REPORT GENERATION COMPLETE" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📄 HTML Report: $filename" -ForegroundColor White
    Write-Host "📁 Location: $script:OutputReports" -ForegroundColor White
    Write-Host ""
    Write-Host "📊 Summary:" -ForegroundColor White
    Write-Host "  Drives: $($driveUsage.Count) | Large Files: $totalLargeFiles" -ForegroundColor Gray
    Write-Host "  Duplicate Groups: $totalDuplicates | Recommendations: $totalRecommendations" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Open report: Start-Process '$reportPath'" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-Reports