# SystemGuardian/Modules/Storage.psm1
# Storage Analyzer â€“ Reads thresholds from config.json
# Version: 2.1.0 (now uses shared Core modules instead of local copies)

# Core shared modules. -Force ensures we get the latest version even if
# another module already imported an older instance in this session.
Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Formatter.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Config.psm1") -Force

function Invoke-Storage {
    <#
    .SYNOPSIS
        Performs comprehensive storage analysis using thresholds from config.json
    #>

    # ----- Path Setup -----
    $script:ModuleDir = $PSScriptRoot
    $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
    $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"
    $script:ConfigPath = Join-Path $script:ProjectRoot "Config\config.json"

    if (-not (Test-Path $script:OutputCSV)) {
        New-Item -Path $script:OutputCSV -ItemType Directory -Force | Out-Null
    }


    # ----- Load Configuration with Fallbacks -----
    function Get-StorageConfig {
        $defaults = @{
            StorageHeavyFileMB = 500
            HugeFileMB = 2048
            LargeFolderMB = 1024
            HugeFolderMB = 20480
            OldFileDays = 365
            OldFileMinSizeMB = 100
            ArchiveMinSizeMB = 500
            IsoMinSizeMB = 1024
            BrowserCacheAlertMB = 500
            TempFileMinSizeMB = 50
            ExcludeFolders = @("C:\Windows", "C:\ProgramData\Microsoft\Windows\WinSxS")
        }

        # Uses the shared Config.psm1 (Import-AppConfig / Get-ConfigValue)
        # instead of re-implementing JSON loading + default-merging locally.
        # NOTE ON BEHAVIOR: the old inline code used PowerShell truthiness
        # (`if ($config.X.Y) {...} else {default}`), which meant an explicit
        # `0` or an empty array in config.json was treated as "missing" and
        # silently replaced with the default. Get-ConfigValue only falls
        # back on an actual missing/null key, so an explicit `0` or `[]` in
        # config.json is now honored instead of being overridden. This only
        # matters if someone deliberately sets a threshold to 0 or empties
        # ExcludeFolders - flagging this here since it's the one intentional
        # behavior difference from the original implementation.
        $config = Import-AppConfig -ConfigPath $script:ConfigPath
        if ($null -eq $config) {
            Write-Log "Config not found. Using default thresholds." "Warning"
            return $defaults
        }

        $merged = $defaults.Clone()
        $merged.StorageHeavyFileMB  = Get-ConfigValue -Config $config -Path "StorageAnalysis.StorageHeavyFileMB"  -Default $defaults.StorageHeavyFileMB
        $merged.HugeFileMB          = Get-ConfigValue -Config $config -Path "StorageAnalysis.HugeFileMB"          -Default $defaults.HugeFileMB
        $merged.LargeFolderMB       = Get-ConfigValue -Config $config -Path "StorageAnalysis.LargeFolderMB"       -Default $defaults.LargeFolderMB
        $merged.HugeFolderMB        = Get-ConfigValue -Config $config -Path "StorageAnalysis.HugeFolderMB"        -Default $defaults.HugeFolderMB
        $merged.OldFileDays         = Get-ConfigValue -Config $config -Path "StorageAnalysis.OldFileDays"         -Default $defaults.OldFileDays
        $merged.OldFileMinSizeMB    = Get-ConfigValue -Config $config -Path "StorageAnalysis.OldFileMinSizeMB"    -Default $defaults.OldFileMinSizeMB
        $merged.ArchiveMinSizeMB    = Get-ConfigValue -Config $config -Path "StorageAnalysis.ArchiveMinSizeMB"    -Default $defaults.ArchiveMinSizeMB
        $merged.IsoMinSizeMB        = Get-ConfigValue -Config $config -Path "StorageAnalysis.IsoMinSizeMB"        -Default $defaults.IsoMinSizeMB
        $merged.BrowserCacheAlertMB = Get-ConfigValue -Config $config -Path "StorageAnalysis.BrowserCacheAlertMB" -Default $defaults.BrowserCacheAlertMB
        $merged.TempFileMinSizeMB   = Get-ConfigValue -Config $config -Path "StorageAnalysis.TempFileMinSizeMB"   -Default $defaults.TempFileMinSizeMB
        $merged.ExcludeFolders      = Get-ConfigValue -Config $config -Path "ExcludeFolders" -Default $defaults.ExcludeFolders

        return $merged
    }

    $cfg = Get-StorageConfig

    # Convert MB to Bytes for comparisons
    $HeavyFileThresholdBytes = $cfg.StorageHeavyFileMB * 1MB
    $HugeFileThresholdBytes = $cfg.HugeFileMB * 1MB
    $LargeFolderThresholdBytes = $cfg.LargeFolderMB * 1MB
    $HugeFolderThresholdBytes = $cfg.HugeFolderMB * 1MB
    $OldFileMinSizeBytes = $cfg.OldFileMinSizeMB * 1MB
    $ArchiveMinSizeBytes = $cfg.ArchiveMinSizeMB * 1MB
    $IsoMinSizeBytes = $cfg.IsoMinSizeMB * 1MB
    $TempMinSizeBytes = $cfg.TempFileMinSizeMB * 1MB
    $BrowserAlertBytes = $cfg.BrowserCacheAlertMB * 1MB
    $ExcludeFolders = $cfg.ExcludeFolders

    Write-Log "Storage Analysis Started" "Info"
    Write-Log "Thresholds: Heavy File=$($cfg.StorageHeavyFileMB)MB, Large Folder=$($cfg.LargeFolderMB)MB" "Info"

    # ----- 1. Drive Usage -----
    Write-ProgressEx -Activity "Storage Analysis" -Status "Analyzing drive usage" -PercentComplete 5
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.Size -gt 0 }
    $driveResults = @()
    foreach ($drive in $drives) {
        $driveResults += [PSCustomObject]@{
            Drive          = $drive.DeviceID
            Label          = $drive.VolumeName
            FileSystem     = $drive.FileSystem
            TotalSize      = $drive.Size
            TotalSizeHuman = Get-HumanReadableSize -Bytes $drive.Size
            FreeSpace      = $drive.FreeSpace
            FreeSpaceHuman = Get-HumanReadableSize -Bytes $drive.FreeSpace
            UsedSpace      = $drive.Size - $drive.FreeSpace
            UsedSpaceHuman = Get-HumanReadableSize -Bytes ($drive.Size - $drive.FreeSpace)
            PercentUsed    = [math]::Round((($drive.Size - $drive.FreeSpace) / $drive.Size) * 100, 2)
        }
    }
    Write-Log "Found $($driveResults.Count) drives" "Info"

    # Build scan paths (exclude system folders)
    $scanPaths = @()
    foreach ($d in $drives) { $scanPaths += $d.DeviceID }
    $scanPaths += @(
        $env:USERPROFILE,
        "$env:SYSTEMDRIVE\ProgramData",
        "$env:SYSTEMDRIVE\Program Files",
        "$env:SYSTEMDRIVE\Program Files (x86)"
    )
    $scanPaths = $scanPaths | Where-Object { 
        (Test-Path $_) -and 
        ($ExcludeFolders -notcontains $_) 
    } | Select-Object -Unique

    # ----- 2. Files Scan: Heavy/Huge Files, Old Files, Archives, ISOs -----
    # OPTIMIZATION: The original implementation ran FOUR separate recursive
    # Get-ChildItem scans per path (one each for heavy files, old files,
    # archives, and ISOs). Disk enumeration is the dominant cost of this
    # module, so re-walking the same directory tree four times is the
    # single biggest inefficiency here. This block walks each scan path
    # ONCE and classifies every file into all four buckets in the same
    # pass. Per-path sorting/Select-Object -First limits are kept
    # identical to the original code so the exported CSVs are unchanged.
    Write-ProgressEx -Activity "Storage Analysis" -Status "Scanning files (heavy/old/archives/ISOs)" -PercentComplete 15
    $archiveExts = @(".zip", ".rar", ".7z", ".tar", ".gz", ".bz2", ".xz", ".tgz", ".tbz2")
    $isoExts = @(".iso", ".img", ".nrg", ".bin")
    $oldCutoff = (Get-Date).AddDays(-$cfg.OldFileDays)

    $largeFilesList  = [System.Collections.Generic.List[object]]::new()
    $hugeFilesList   = [System.Collections.Generic.List[object]]::new()
    $oldFilesList    = [System.Collections.Generic.List[object]]::new()
    $archivesList    = [System.Collections.Generic.List[object]]::new()
    $isosList        = [System.Collections.Generic.List[object]]::new()

    foreach ($path in $scanPaths) {
        Write-Log "  Scanning files in: $path" "Info"
        try {
            # Single recursive enumeration, materialized once and reused
            # below instead of re-scanning the disk for every category.
            $allFiles = Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue

            # -- Heavy / Huge files (same filter+sort+top100 as before) --
            $pathHeavy = $allFiles | Where-Object { $_.Length -gt $HeavyFileThresholdBytes } |
                         Sort-Object Length -Descending | Select-Object -First 100
            foreach ($f in $pathHeavy) {
                $obj = [PSCustomObject]@{
                    Path      = $f.FullName
                    Name      = $f.Name
                    Size      = $f.Length
                    SizeHuman = Get-HumanReadableSize -Bytes $f.Length
                    Modified  = $f.LastWriteTime
                    Extension = $f.Extension
                    Directory = $f.DirectoryName
                }
                $largeFilesList.Add($obj)
                if ($f.Length -gt $HugeFileThresholdBytes) {
                    $hugeFilesList.Add($obj)
                }
            }

            # -- Old files (same filter+sort+top100 as before) --
            $pathOld = $allFiles | Where-Object { $_.LastWriteTime -lt $oldCutoff -and $_.Length -gt $OldFileMinSizeBytes } |
                       Sort-Object LastWriteTime | Select-Object -First 100
            foreach ($f in $pathOld) {
                $oldFilesList.Add([PSCustomObject]@{
                    Path      = $f.FullName
                    Name      = $f.Name
                    Size      = $f.Length
                    SizeHuman = Get-HumanReadableSize -Bytes $f.Length
                    Modified  = $f.LastWriteTime
                    DaysOld   = [math]::Round(((Get-Date) - $f.LastWriteTime).TotalDays, 0)
                    Extension = $f.Extension
                })
            }

            # -- Large archives (same filter+sort+top50 as before) --
            $pathArchives = $allFiles | Where-Object { $archiveExts -contains $_.Extension.ToLower() -and $_.Length -gt $ArchiveMinSizeBytes } |
                            Sort-Object Length -Descending | Select-Object -First 50
            foreach ($f in $pathArchives) {
                $archivesList.Add([PSCustomObject]@{
                    Path      = $f.FullName
                    Name      = $f.Name
                    Size      = $f.Length
                    SizeHuman = Get-HumanReadableSize -Bytes $f.Length
                    Modified  = $f.LastWriteTime
                    Extension = $f.Extension
                })
            }

            # -- Large ISOs (same filter+sort+top30 as before) --
            $pathIsos = $allFiles | Where-Object { $isoExts -contains $_.Extension.ToLower() -and $_.Length -gt $IsoMinSizeBytes } |
                        Sort-Object Length -Descending | Select-Object -First 30
            foreach ($f in $pathIsos) {
                $isosList.Add([PSCustomObject]@{
                    Path      = $f.FullName
                    Name      = $f.Name
                    Size      = $f.Length
                    SizeHuman = Get-HumanReadableSize -Bytes $f.Length
                    Modified  = $f.LastWriteTime
                    Extension = $f.Extension
                })
            }
        } catch {
            Write-Log "  Error scanning $path : $($_.Exception.Message)" "Warning"
        }
    }

    # Global trims match the original post-loop behavior exactly:
    # heavy files and old files were re-sorted and capped across all
    # paths; archives and ISOs were left as per-path-capped concatenations.
    $largeFiles    = $largeFilesList | Sort-Object Size -Descending | Select-Object -First 50
    $hugeFiles     = $hugeFilesList
    $oldFiles      = $oldFilesList | Sort-Object DaysOld -Descending | Select-Object -First 50
    $largeArchives = $archivesList
    $largeISOs     = $isosList

    Write-Log "  Found $($largeFiles.Count) heavy files (>$($cfg.StorageHeavyFileMB)MB)" "Success"
    if ($hugeFiles.Count -gt 0) {
        Write-Log "  Found $($hugeFiles.Count) HUGE files (>$($cfg.HugeFileMB)MB) - Review these!" "Warning"
    }
    Write-Log "  Found $($oldFiles.Count) old files (>$($cfg.OldFileDays) days, >$($cfg.OldFileMinSizeMB)MB)" "Success"
    Write-Log "  Found $($largeArchives.Count) large archives (>$($cfg.ArchiveMinSizeMB)MB)" "Success"
    Write-Log "  Found $($largeISOs.Count) large ISOs (>$($cfg.IsoMinSizeMB)MB)" "Success"

    # ----- 3. Largest Folders (Using LargeFolderThreshold) -----
    # OPTIMIZATION: The original code ran TWO separate recursive
    # Get-ChildItem calls per folder (one filtered to -File for the size
    # sum, one unfiltered for the item count). Both numbers are derived
    # here from a single recursive enumeration per folder instead.
    Write-ProgressEx -Activity "Storage Analysis" -Status "Finding large folders (>$($cfg.LargeFolderMB)MB)" -PercentComplete 35
    $largeFoldersList = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $scanPaths) {
        Write-Log "  Scanning folders in: $path" "Info"
        try {
            $folders = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue
            foreach ($folder in $folders) {
                try {
                    $allItems = Get-ChildItem -Path $folder.FullName -Recurse -ErrorAction SilentlyContinue
                    $size = ($allItems | Where-Object { -not $_.PSIsContainer } |
                             Measure-Object -Property Length -Sum).Sum
                    if ($size -gt $LargeFolderThresholdBytes) {
                        $largeFoldersList.Add([PSCustomObject]@{
                            Path      = $folder.FullName
                            Name      = $folder.Name
                            Size      = $size
                            SizeHuman = Get-HumanReadableSize -Bytes $size
                            Items     = $allItems.Count
                            Modified  = $folder.LastWriteTime
                        })
                    }
                } catch { }
            }
        } catch {
            Write-Log "  Error scanning folders in $path : $($_.Exception.Message)" "Warning"
        }
    }
    $largeFolders = $largeFoldersList | Sort-Object Size -Descending | Select-Object -First 30
    Write-Log "  Found $($largeFolders.Count) large folders (>$($cfg.LargeFolderMB)MB)" "Success"

    # ----- 4. Empty Folders -----
    # OPTIMIZATION: The original emptiness check called
    # "Get-ChildItem -Force" per candidate folder, which materializes
    # every child item just to test Count -eq 0. Using the .NET
    # enumerator directly lets us stop at the first entry found, which
    # is much cheaper for folders that contain many files.
    Write-ProgressEx -Activity "Storage Analysis" -Status "Finding empty folders" -PercentComplete 50
    $emptyFoldersList = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $scanPaths) {
        Write-Log "  Scanning empty folders in: $path" "Info"
        try {
            $folders = Get-ChildItem -Path $path -Directory -Recurse -ErrorAction SilentlyContinue |
                       Where-Object {
                           try {
                               $enum = [System.IO.Directory]::EnumerateFileSystemEntries($_.FullName).GetEnumerator()
                               -not $enum.MoveNext()
                           } catch { $false }
                       } |
                       Select-Object -First 200
            foreach ($f in $folders) {
                $emptyFoldersList.Add([PSCustomObject]@{
                    Path     = $f.FullName
                    Name     = $f.Name
                    Created  = $f.CreationTime
                    Modified = $f.LastWriteTime
                })
            }
        } catch {
            Write-Log "  Error scanning empty folders in $path : $($_.Exception.Message)" "Warning"
        }
    }
    $emptyFolders = $emptyFoldersList
    Write-Log "  Found $($emptyFolders.Count) empty folders" "Success"

    # ----- 8. Downloads Analysis -----
    Write-ProgressEx -Activity "Storage Analysis" -Status "Analyzing downloads" -PercentComplete 85
    $downloadPaths = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop\Downloads")
    $downloadResults = @()
    foreach ($dlPath in $downloadPaths) {
        if (-not (Test-Path $dlPath)) { continue }
        Write-Log "  Analyzing downloads in: $dlPath" "Info"
        try {
            # OPTIMIZATION: one recursive scan instead of three (total size,
            # file count, and old-file lookup all reuse the same listing).
            $allDLFiles = Get-ChildItem -Path $dlPath -Recurse -File -ErrorAction SilentlyContinue
            $totalSize = ($allDLFiles | Measure-Object -Property Length -Sum).Sum
            $fileCount = $allDLFiles.Count
            $oldDL = $allDLFiles |
                     Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) -and $_.Length -gt 10485760 } |
                     Sort-Object Length -Descending |
                     Select-Object -First 20
            $downloadResults += [PSCustomObject]@{
                Path = $dlPath
                TotalSize = $totalSize
                TotalSizeHuman = Get-HumanReadableSize -Bytes $totalSize
                FileCount = $fileCount
                OldDownloadsCount = $oldDL.Count
                OldDownloadsSize = ($oldDL | Measure-Object -Property Length -Sum).Sum
                OldDownloadsSizeHuman = Get-HumanReadableSize -Bytes (($oldDL | Measure-Object -Property Length -Sum).Sum)
            }
        } catch {
            Write-Log "  Error analyzing downloads in $dlPath : $($_.Exception.Message)" "Warning"
        }
    }
    Write-Log "  Analyzed $($downloadResults.Count) download locations" "Success"

    # ----- 9. Temp Files (Using TempMinSize) -----
    Write-ProgressEx -Activity "Storage Analysis" -Status "Analyzing temp files" -PercentComplete 90
    $tempPaths = @("$env:TEMP", "$env:TMP", "C:\Windows\Temp")
    $tempFiles = @()
    foreach ($tp in $tempPaths) {
        if (-not (Test-Path $tp)) { continue }
        Write-Log "  Scanning temp files in: $tp" "Info"
        try {
            $files = Get-ChildItem -Path $tp -File -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.Length -gt $TempMinSizeBytes } |
                     Sort-Object Length -Descending |
                     Select-Object -First 50
            foreach ($f in $files) {
                $tempFiles += [PSCustomObject]@{
                    Path      = $f.FullName
                    Name      = $f.Name
                    Size      = $f.Length
                    SizeHuman = Get-HumanReadableSize -Bytes $f.Length
                    Modified  = $f.LastWriteTime
                    Age       = [math]::Round(((Get-Date) - $f.LastWriteTime).TotalDays, 1)
                }
            }
        } catch {
            Write-Log "  Error scanning temp files in $tp : $($_.Exception.Message)" "Warning"
        }
    }
    Write-Log "  Found $($tempFiles.Count) temp files (>$($cfg.TempFileMinSizeMB)MB)" "Success"

    # ----- 10. Browser Cache (Alert if > BrowserCacheAlertMB) -----
    Write-ProgressEx -Activity "Storage Analysis" -Status "Analyzing browser cache" -PercentComplete 95
    $browserPaths = @(
        @{Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Browser = "Chrome"},
        @{Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"; Browser = "Chrome"},
        @{Path = "$env:APPDATA\Mozilla\Firefox\Profiles\*\cache2"; Browser = "Firefox"},
        @{Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Browser = "Edge"},
        @{Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"; Browser = "Edge"}
    )
    $browserCache = @()
    foreach ($b in $browserPaths) {
        $resolved = Resolve-Path -Path $b.Path -ErrorAction SilentlyContinue
        foreach ($rp in $resolved) {
            Write-Log "  Scanning cache for $($b.Browser): $rp" "Info"
            try {
                $files = Get-ChildItem -Path $rp.Path -File -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Length -gt 0 } |
                         Sort-Object Length -Descending |
                         Select-Object -First 30
                $total = ($files | Measure-Object -Property Length -Sum).Sum
                if ($total -gt $BrowserAlertBytes) {
                    Write-Log "    $($b.Browser) cache is $($total/1MB) MB - Alert!" "Warning"
                }
                $browserCache += [PSCustomObject]@{
                    Browser = $b.Browser
                    Path = $rp.Path
                    TotalSize = $total
                    TotalSizeHuman = Get-HumanReadableSize -Bytes $total
                    FileCount = $files.Count
                }
            } catch {
                Write-Log "  Error scanning browser cache for $($b.Browser) : $($_.Exception.Message)" "Warning"
            }
        }
    }
    Write-Log "  Analyzed $($browserCache.Count) browser cache locations" "Success"

    # ----- 11. Recycle Bin -----
    Write-ProgressEx -Activity "Storage Analysis" -Status "Analyzing recycle bin" -PercentComplete 98
    try {
        $shell = New-Object -ComObject Shell.Application
        $rb = $shell.NameSpace(0x0a)
        if ($rb) {
            $items = $rb.Items()
            $totalSize = 0
            $itemCount = 0
            foreach ($item in $items) {
                $size = $item.Size
                if ($size -gt 0) {
                    $totalSize += $size
                    $itemCount++
                }
            }
            $recycleInfo = [PSCustomObject]@{
                ItemCount = $itemCount
                TotalSize = $totalSize
                TotalSizeHuman = Get-HumanReadableSize -Bytes $totalSize
            }
            Write-Log "  Recycle Bin: $itemCount items, $($recycleInfo.TotalSizeHuman)" "Success"
        }
    } catch {
        Write-Log "  Error analyzing Recycle Bin : $($_.Exception.Message)" "Warning"
        $recycleInfo = [PSCustomObject]@{ ItemCount = 0; TotalSize = 0; TotalSizeHuman = "0 B" }
    }

    # ----- Save CSV Files -----
    Write-ProgressEx -Activity "Storage Analysis" -Status "Saving results" -PercentComplete 99
    $exportMap = @{
        "LargeFiles" = $largeFiles
        "LargeFolders" = $largeFolders
        "DriveUsage" = $driveResults
        "EmptyFolders" = $emptyFolders
        "OldFiles" = $oldFiles
        "LargeArchives" = $largeArchives
        "LargeISOs" = $largeISOs
        "TempFiles" = $tempFiles
        "BrowserCache" = $browserCache
        "DownloadsAnalysis" = $downloadResults
    }
    foreach ($key in $exportMap.Keys) {
        if ($exportMap[$key].Count -gt 0) {
            $csvPath = Join-Path $script:OutputCSV "$key.csv"
            $exportMap[$key] | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Log "Saved $key.csv ($($exportMap[$key].Count) records)" "Success"
        }
    }

    # Summary JSON
    $summary = [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalDrives = $driveResults.Count
        TotalLargeFiles = $largeFiles.Count
        TotalLargeFolders = $largeFolders.Count
        TotalEmptyFolders = $emptyFolders.Count
        TotalOldFiles = $oldFiles.Count
        TotalLargeArchives = $largeArchives.Count
        TotalLargeISOs = $largeISOs.Count
        TotalTempFiles = $tempFiles.Count
        RecycleBinItems = $recycleInfo.ItemCount
        RecycleBinSize = $recycleInfo.TotalSizeHuman
        LargestFile = if ($largeFiles.Count -gt 0) { $largeFiles[0].Name } else { "N/A" }
        LargestFileSize = if ($largeFiles.Count -gt 0) { $largeFiles[0].SizeHuman } else { "N/A" }
        LargestFolder = if ($largeFolders.Count -gt 0) { $largeFolders[0].Name } else { "N/A" }
        LargestFolderSize = if ($largeFolders.Count -gt 0) { $largeFolders[0].SizeHuman } else { "N/A" }
    }
    $summary | Export-Csv -Path (Join-Path $script:OutputCSV "StorageSummary.csv") -NoTypeInformation
    $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "StorageSummary.json")

    Write-ProgressEx -Activity "Storage Analysis" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "Storage Analysis" -Completed

    # Display Final Summary
    Write-Host ""
    Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan
    Write-Host "STORAGE ANALYSIS COMPLETE" -ForegroundColor Yellow
    Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Drive Usage:" -ForegroundColor White
    foreach ($d in $driveResults) {
        Write-Host "  $($d.Drive) $($d.TotalSizeHuman) total, $($d.FreeSpaceHuman) free ($($d.PercentUsed)% used)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Key Findings:" -ForegroundColor White
    Write-Host "  Heavy Files (>$($cfg.StorageHeavyFileMB)MB): $($largeFiles.Count)" -ForegroundColor Gray
    Write-Host "  Large Folders (>$($cfg.LargeFolderMB)MB): $($largeFolders.Count)" -ForegroundColor Gray
    Write-Host "  Empty Folders: $($emptyFolders.Count)" -ForegroundColor Gray
    Write-Host "  Old Files (>$($cfg.OldFileDays) days): $($oldFiles.Count)" -ForegroundColor Gray
    Write-Host "  Large Archives (>$($cfg.ArchiveMinSizeMB)MB): $($largeArchives.Count)" -ForegroundColor Gray
    Write-Host "  Large ISOs (>$($cfg.IsoMinSizeMB)MB): $($largeISOs.Count)" -ForegroundColor Gray
    Write-Host "  Temp Files (>$($cfg.TempFileMinSizeMB)MB): $($tempFiles.Count)" -ForegroundColor Gray
    Write-Host "  Recycle Bin: $($recycleInfo.ItemCount) items ($($recycleInfo.TotalSizeHuman))" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
    Write-Host "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-Storage

