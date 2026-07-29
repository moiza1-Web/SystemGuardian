# SystemGuardian/Modules/ReviewAnalyzer.psm1
# Smart Review Analyzer – Fixed special characters
# Version: 1.1.0 (now uses shared Core modules instead of local copies)

Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force

function Invoke-ReviewAnalyzer {
    <#
    .SYNOPSIS
        Analyzes system data and flags items for review
    .DESCRIPTION
        Reads data from Storage, Duplicates, Applications, and Browser modules
        and generates actionable recommendations
    #>

    # ----- Path Setup -----
    $script:ModuleDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
    $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"
    $script:OutputReports = Join-Path $script:ProjectRoot "Output\Reports"

    if (-not (Test-Path $script:OutputCSV)) {
        New-Item -Path $script:OutputCSV -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $script:OutputReports)) {
        New-Item -Path $script:OutputReports -ItemType Directory -Force | Out-Null
    }

    # Write-Log and Write-ProgressEx now come from Logger.psm1 and
    # Progress.psm1 (imported above). The old local Get-HumanReadableSize
    # was dead code here (defined but never called in this file), so it's
    # simply removed rather than imported from Formatter.psm1.

    Write-Log "Starting Smart Review Analysis" "Info"

    $recommendations = @()

    # ----- 1. Check Large Files (>500MB) -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing large files..." -PercentComplete 10

    $largeFilesCsv = Join-Path $script:OutputCSV "LargeFiles.csv"
    if (Test-Path $largeFilesCsv) {
        $largeFiles = Import-Csv -Path $largeFilesCsv
        foreach ($file in $largeFiles) {
            $sizeMB = [math]::Round($file.Size / 1MB, 0)
            if ($sizeMB -gt 2048) {
                $recommendations += [PSCustomObject]@{
                    Category = "Large File"
                    Item = $file.Name
                    Location = $file.Directory
                    Size = $file.Size
                    SizeHuman = $file.SizeHuman
                    Reason = "HUGE file ($($file.SizeHuman)) - likely an ISO, VM, or video file. Review if needed."
                    Type = "Review Recommended"
                    Priority = "High"
                }
            } elseif ($sizeMB -gt 500) {
                $recommendations += [PSCustomObject]@{
                    Category = "Large File"
                    Item = $file.Name
                    Location = $file.Directory
                    Size = $file.Size
                    SizeHuman = $file.SizeHuman
                    Reason = "Large file ($($file.SizeHuman)) - may be unnecessary. Review recommended."
                    Type = "Review Recommended"
                    Priority = "Medium"
                }
            }
        }
        Write-Log "  Found $($recommendations.Count) large file recommendations" "Success"
    }

    # ----- 2. Check Large Archives -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing archives..." -PercentComplete 20

    $archivesCsv = Join-Path $script:OutputCSV "LargeArchives.csv"
    if (Test-Path $archivesCsv) {
        $archives = Import-Csv -Path $archivesCsv
        foreach ($archive in $archives) {
            $sizeMB = [math]::Round($archive.Size / 1MB, 0)
            if ($sizeMB -gt 1024) {
                $recommendations += [PSCustomObject]@{
                    Category = "Large Archive"
                    Item = $archive.Name
                    Location = $archive.Path
                    Size = $archive.Size
                    SizeHuman = $archive.SizeHuman
                    Reason = "Large archive ($($archive.SizeHuman)) - may be an old backup or downloaded file. Review."
                    Type = "Review Recommended"
                    Priority = "Medium"
                }
            } elseif ($sizeMB -gt 500) {
                $recommendations += [PSCustomObject]@{
                    Category = "Large Archive"
                    Item = $archive.Name
                    Location = $archive.Path
                    Size = $archive.Size
                    SizeHuman = $archive.SizeHuman
                    Reason = "Archive file ($($archive.SizeHuman)) - review if still needed."
                    Type = "Review Recommended"
                    Priority = "Low"
                }
            }
        }
        Write-Log "  Found $($archives.Count) archive recommendations" "Success"
    }

    # ----- 3. Check Large ISOs -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing ISOs..." -PercentComplete 30

    $isosCsv = Join-Path $script:OutputCSV "LargeISOs.csv"
    if (Test-Path $isosCsv) {
        $isos = Import-Csv -Path $isosCsv
        foreach ($iso in $isos) {
            $recommendations += [PSCustomObject]@{
                Category = "ISO Image"
                Item = $iso.Name
                Location = $iso.Path
                Size = $iso.Size
                SizeHuman = $iso.SizeHuman
                Reason = "ISO image ($($iso.SizeHuman)) - installation media or backup. Can be deleted if no longer needed."
                Type = "Review Recommended"
                Priority = "High"
            }
        }
        Write-Log "  Found $($isos.Count) ISO recommendations" "Success"
    }

    # ----- 4. Check Old Files (>365 days) -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing old files..." -PercentComplete 40

    $oldFilesCsv = Join-Path $script:OutputCSV "OldFiles.csv"
    if (Test-Path $oldFilesCsv) {
        $oldFiles = Import-Csv -Path $oldFilesCsv
        foreach ($file in $oldFiles) {
            $sizeMB = [math]::Round($file.Size / 1MB, 0)
            if ($sizeMB -gt 500) {
                $recommendations += [PSCustomObject]@{
                    Category = "Old Large File"
                    Item = $file.Name
                    Location = $file.Path
                    Size = $file.Size
                    SizeHuman = $file.SizeHuman
                    Reason = "Old file ($($file.DaysOld) days) - $($file.SizeHuman). Not accessed in over a year. Archive or delete."
                    Type = "Review Recommended"
                    Priority = "Medium"
                }
            } elseif ($sizeMB -gt 100) {
                $recommendations += [PSCustomObject]@{
                    Category = "Old File"
                    Item = $file.Name
                    Location = $file.Path
                    Size = $file.Size
                    SizeHuman = $file.SizeHuman
                    Reason = "Old file ($($file.DaysOld) days) - over 1 year old. May no longer be needed."
                    Type = "Review Recommended"
                    Priority = "Low"
                }
            }
        }
        Write-Log "  Found $($oldFiles.Count) old file recommendations" "Success"
    }

    # ----- 5. Check Browser Cache -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing browser cache..." -PercentComplete 50

    $browserCacheCsv = Join-Path $script:OutputCSV "BrowserCache.csv"
    if (Test-Path $browserCacheCsv) {
        $browserCaches = Import-Csv -Path $browserCacheCsv
        foreach ($cache in $browserCaches) {
            $sizeMB = [math]::Round($cache.TotalSize / 1MB, 0)
            if ($sizeMB -gt 1000) {
                $recommendations += [PSCustomObject]@{
                    Category = "Browser Cache"
                    Item = "$($cache.Browser) - $($cache.Profile)"
                    Location = $cache.Path
                    Size = $cache.TotalSize
                    SizeHuman = $cache.TotalSizeHuman
                    Reason = "Browser cache ($($cache.TotalSizeHuman)) - clearing can free up significant space."
                    Type = "Review Recommended"
                    Priority = "High"
                }
            } elseif ($sizeMB -gt 500) {
                $recommendations += [PSCustomObject]@{
                    Category = "Browser Cache"
                    Item = "$($cache.Browser) - $($cache.Profile)"
                    Location = $cache.Path
                    Size = $cache.TotalSize
                    SizeHuman = $cache.TotalSizeHuman
                    Reason = "Browser cache ($($cache.TotalSizeHuman)) - consider clearing if space is needed."
                    Type = "Review Recommended"
                    Priority = "Medium"
                }
            }
        }
        Write-Log "  Found $($browserCaches.Count) browser cache recommendations" "Success"
    }

    # ----- 6. Check Temp Files -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing temp files..." -PercentComplete 60

    $tempCsv = Join-Path $script:OutputCSV "TempFiles.csv"
    if (Test-Path $tempCsv) {
        $tempFiles = Import-Csv -Path $tempCsv
        foreach ($file in $tempFiles) {
            $sizeMB = [math]::Round($file.Size / 1MB, 0)
            if ($sizeMB -gt 100) {
                $recommendations += [PSCustomObject]@{
                    Category = "Temp File"
                    Item = $file.Name
                    Location = $file.Path
                    Size = $file.Size
                    SizeHuman = $file.SizeHuman
                    Reason = "Temp file ($($file.SizeHuman)) - $($file.Age) days old. Likely safe to delete."
                    Type = "Review Recommended"
                    Priority = "Medium"
                }
            } elseif ($sizeMB -gt 50) {
                $recommendations += [PSCustomObject]@{
                    Category = "Temp File"
                    Item = $file.Name
                    Location = $file.Path
                    Size = $file.Size
                    SizeHuman = $file.SizeHuman
                    Reason = "Temp file ($($file.SizeHuman)) - can be safely deleted."
                    Type = "Review Recommended"
                    Priority = "Low"
                }
            }
        }
        Write-Log "  Found $($tempFiles.Count) temp file recommendations" "Success"
    }

    # ----- 7. Check Duplicate Files -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing duplicates..." -PercentComplete 70

    $duplicatesCsv = Join-Path $script:OutputCSV "Duplicates.csv"
    if (Test-Path $duplicatesCsv) {
        $duplicates = Import-Csv -Path $duplicatesCsv
        $duplicateGroups = $duplicates | Group-Object -Property GroupID
        foreach ($group in $duplicateGroups) {
            $firstFile = $group.Group | Select-Object -First 1
            $totalSize = $firstFile.GroupTotalSize
            $fileCount = $firstFile.TotalInGroup
            if ($totalSize -gt 1073741824) { # >1GB
                $recommendations += [PSCustomObject]@{
                    Category = "Duplicate Files"
                    Item = "$fileCount copies of $($firstFile.FileName)"
                    Location = "Various locations"
                    Size = $totalSize
                    SizeHuman = $firstFile.GroupTotalSizeHuman
                    Reason = "Duplicate files ($($firstFile.GroupTotalSizeHuman)) - $fileCount copies. Keep one, delete the rest."
                    Type = "Review Recommended"
                    Priority = "High"
                }
            } elseif ($totalSize -gt 104857600) { # >100MB
                $recommendations += [PSCustomObject]@{
                    Category = "Duplicate Files"
                    Item = "$fileCount copies of $($firstFile.FileName)"
                    Location = "Various locations"
                    Size = $totalSize
                    SizeHuman = $firstFile.GroupTotalSizeHuman
                    Reason = "Duplicate files ($($firstFile.GroupTotalSizeHuman)) - review duplicates."
                    Type = "Review Recommended"
                    Priority = "Medium"
                }
            }
        }
        Write-Log "  Found $($duplicateGroups.Count) duplicate group recommendations" "Success"
    }

    # ----- 8. Check Large Folders (node_modules, venv, etc.) -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing large folders..." -PercentComplete 80

    $foldersCsv = Join-Path $script:OutputCSV "LargeFolders.csv"
    if (Test-Path $foldersCsv) {
        $folders = Import-Csv -Path $foldersCsv
        foreach ($folder in $folders) {
            $nameLower = $folder.Name.ToLower()
            $sizeMB = [math]::Round($folder.Size / 1MB, 0)
            $reason = ""
            $priority = ""

            if ($nameLower -match "node_modules") {
                $reason = "node_modules folder ($($folder.SizeHuman)) - likely from a Node.js project. Can be safely deleted if project is complete."
                $priority = "High"
            } elseif ($nameLower -match "venv|env|virtualenv" -or $folder.Path -match "venv|env") {
                $reason = "Python virtual environment ($($folder.SizeHuman)) - can be recreated if needed. May be safe to delete."
                $priority = "Medium"
            } elseif ($nameLower -match "cache|temp|tmp") {
                $reason = "Cache folder ($($folder.SizeHuman)) - temporary files that can likely be deleted."
                $priority = "Medium"
            } elseif ($nameLower -match "downloads") {
                $reason = "Downloads folder ($($folder.SizeHuman)) - review contents and clean up old files."
                $priority = "Medium"
            } elseif ($sizeMB -gt 10240) { # >10GB
                $reason = "Large folder ($($folder.SizeHuman)) - review contents. May contain unnecessary files."
                $priority = "Medium"
            } else {
                continue
            }

            $recommendations += [PSCustomObject]@{
                Category = "Large Folder"
                Item = $folder.Name
                Location = $folder.Path
                Size = $folder.Size
                SizeHuman = $folder.SizeHuman
                Reason = $reason
                Type = "Review Recommended"
                Priority = $priority
            }
        }
        Write-Log "  Found $($folders.Count) folder recommendations" "Success"
    }

    # ----- 9. Check Recycle Bin -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing recycle bin..." -PercentComplete 90

    $summaryJson = Join-Path $script:OutputCSV "StorageSummary.json"
    if (Test-Path $summaryJson) {
        try {
            $summary = Get-Content -Path $summaryJson -Raw | ConvertFrom-Json
            if ($summary.RecycleBinSize -and $summary.RecycleBinSize -ne "0 B") {
                $recommendations += [PSCustomObject]@{
                    Category = "Recycle Bin"
                    Item = "Recycle Bin"
                    Location = "System"
                    Size = 0
                    SizeHuman = $summary.RecycleBinSize
                    Reason = "Recycle Bin contains $($summary.RecycleBinItems) items ($($summary.RecycleBinSize)). Empty to recover space."
                    Type = "Review Recommended"
                    Priority = "Medium"
                }
            }
        } catch { }
        Write-Log "  Added recycle bin recommendation" "Success"
    }

    # ----- 10. Check Empty Folders -----
    Write-ProgressEx -Activity "Review Analyzer" -Status "Analyzing empty folders..." -PercentComplete 95

    $emptyFoldersCsv = Join-Path $script:OutputCSV "EmptyFolders.csv"
    if (Test-Path $emptyFoldersCsv) {
        $emptyFolders = Import-Csv -Path $emptyFoldersCsv
        $emptyCount = $emptyFolders.Count
        if ($emptyCount -gt 100) {
            $recommendations += [PSCustomObject]@{
                Category = "Empty Folders"
                Item = "$emptyCount empty folders"
                Location = "Various locations"
                Size = 0
                SizeHuman = "0 B"
                Reason = "$emptyCount empty folders found. While they don't use space, they create clutter. Review and delete if desired."
                Type = "Review Recommended"
                Priority = "Low"
            }
        }
        Write-Log "  Added empty folder recommendation" "Success"
    }

    # ----- Sort by priority -----
    $priorityOrder = @{"High" = 1; "Medium" = 2; "Low" = 3}
    $recommendations = $recommendations | Sort-Object { $priorityOrder[$_.Priority] }

    Write-ProgressEx -Activity "Review Analyzer" -Status "Saving results" -PercentComplete 98

    # ----- Save Recommendations -----
    if ($recommendations.Count -gt 0) {
        $csvPath = Join-Path $script:OutputCSV "ReviewRecommended.csv"
        $recommendations | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Log "Saved ReviewRecommended.csv ($($recommendations.Count) records)" "Success"

        $recommendations | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $script:OutputCSV "ReviewRecommended.json")
    } else {
        Write-Log "No recommendations found" "Info"
    }

    # Save summary
    $summary = [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalRecommendations = $recommendations.Count
        HighPriority = ($recommendations | Where-Object { $_.Priority -eq "High" }).Count
        MediumPriority = ($recommendations | Where-Object { $_.Priority -eq "Medium" }).Count
        LowPriority = ($recommendations | Where-Object { $_.Priority -eq "Low" }).Count
        Categories = ($recommendations | Group-Object Category | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ", "
    }

    $summary | Export-Csv -Path (Join-Path $script:OutputCSV "ReviewSummary.csv") -NoTypeInformation
    $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "ReviewSummary.json")

    Write-ProgressEx -Activity "Review Analyzer" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "Review Analyzer" -Completed

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "SMART REVIEW ANALYSIS COMPLETE" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Total Recommendations: $($recommendations.Count)" -ForegroundColor White
    Write-Host "  High Priority: $($summary.HighPriority)" -ForegroundColor Red
    Write-Host "  Medium Priority: $($summary.MediumPriority)" -ForegroundColor Yellow
    Write-Host "  Low Priority: $($summary.LowPriority)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Top 5 Recommendations:" -ForegroundColor White
    $topRecs = $recommendations | Select-Object -First 5
    $counter = 1
    foreach ($rec in $topRecs) {
        $priorityColor = if ($rec.Priority -eq "High") { "Red" } elseif ($rec.Priority -eq "Medium") { "Yellow" } else { "Green" }
        Write-Host "  $counter. [$($rec.Priority)] $($rec.Item) - $($rec.SizeHuman)" -ForegroundColor $priorityColor
        Write-Host "     $($rec.Reason)" -ForegroundColor Gray
        $counter++
    }
    Write-Host ""
    Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-ReviewAnalyzer
