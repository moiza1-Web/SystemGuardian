# SystemGuardian/Modules/Duplicates.psm1
# Duplicate Finder – ULTRA FAST & MEMORY SAFE (Streaming SHA256)
# Version: 3.1.0 (now uses shared Core modules instead of local copies)

Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Formatter.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Config.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Utils.psm1") -Force

function Invoke-Duplicates {
    <#
    .SYNOPSIS
        Finds duplicate files using streaming SHA256 (no memory explosion)
    .DESCRIPTION
        Uses 8KB chunks for hashing, so 10GB files use only 8KB RAM.
        Skip files < 1MB to save time.
    #>

    # ----- Path Setup -----
    $paths = Initialize-ModulePaths -ModuleRoot $PSScriptRoot
    $script:ModuleDir = $paths.ModuleDir
    $script:ProjectRoot = $paths.ProjectRoot
    $script:OutputCSV = $paths.OutputCSV
    $script:ConfigPath = $paths.ConfigPath

    # Write-Log, Get-HumanReadableSize, and Write-ProgressEx now come from
    # Logger.psm1, Formatter.psm1, and Progress.psm1 (imported above).

    # ----- STREAMING HASH (Memory Safe) -----
    function Get-StreamingHash {
        param([string]$Path)
        try {
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $stream = [System.IO.File]::OpenRead($Path)
            $buffer = New-Object byte[] 8192  # 8KB buffer
            [long]$totalRead = 0
            while ($true) {
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -eq 0) { break }
                $sha256.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
                $totalRead += $bytesRead
                # Update progress every 100MB to show life
                if ($totalRead % 104857600 -lt 8192) {
                    Write-ProgressEx -Activity "Hashing" -Status "$Path ($(Get-HumanReadableSize -Bytes $totalRead))" -PercentComplete 50
                }
            }
            $sha256.TransformFinalBlock($null, 0, 0) | Out-Null
            $hashBytes = $sha256.Hash
            $hashString = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
            $stream.Dispose()
            $sha256.Dispose()
            return $hashString
        } catch {
            return $null
        }
    }

    # ----- QUICK HASH (Cheap pre-filter before full streaming hash) -----
    # OPTIMIZATION: Files that land in the same size-group are not
    # necessarily duplicates - many are just coincidentally the same
    # size (empty templates, fixed-size cache entries, etc). Hashing the
    # first 64KB of each candidate is far cheaper than a full streaming
    # SHA256 over a multi-GB file, and any group whose quick hashes
    # differ is provably not a duplicate - no full hash needed at all.
    # Files that DO share a quick hash still go through the full
    # streaming hash below for a definitive, byte-for-byte confirmation,
    # so final results are identical to hashing everything in full.
    function Get-QuickHash {
        param([string]$Path, [long]$SampleBytes = 65536)
        try {
            $stream = [System.IO.File]::OpenRead($Path)
            $toRead = [Math]::Min($SampleBytes, $stream.Length)
            $buffer = New-Object byte[] $toRead
            $readSoFar = 0
            while ($readSoFar -lt $toRead) {
                $bytesRead = $stream.Read($buffer, $readSoFar, $toRead - $readSoFar)
                if ($bytesRead -eq 0) { break }
                $readSoFar += $bytesRead
            }
            $stream.Dispose()
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $hashBytes = $sha256.ComputeHash($buffer, 0, $readSoFar)
            $sha256.Dispose()
            return [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        } catch {
            return $null
        }
    }

    # ----- Load Config (ExcludeFolders + DuplicateMinFileMB) -----
    # Uses the shared Config.psm1 instead of two separate manual
    # Get-Content/ConvertFrom-Json reads. NOTE ON BEHAVIOR: the old code
    # used PowerShell truthiness (`if ($config.ExcludeFolders) {...}`),
    # so an explicit empty array `[]` in config.json was treated as
    # "missing" and replaced with the default exclude list. Get-ConfigValue
    # only falls back on an actually missing/null key, so an explicit `[]`
    # is now honored (no folders excluded) instead of being overridden.
    # Flagging this as the one intentional behavior difference, same as
    # the equivalent change already made in Storage.psm1.
    $appConfig = Import-AppConfig -ConfigPath $script:ConfigPath
    $defaultExcludeFolders = @("C:\Windows", "C:\ProgramData\Microsoft\Windows\WinSxS", "C:\System Volume Information")
    $ExcludeFolders = Get-ConfigValue -Config $appConfig -Path "ExcludeFolders" -Default $defaultExcludeFolders
    $dupMinMB = [int](Get-ConfigValue -Config $appConfig -Path "DuplicateAnalysis.DuplicateMinFileMB" -Default 1)

    Write-Log "Starting ULTRA FAST Duplicate Analysis (Streaming SHA256)" "Info"

    # ----- Get Drives (Skip excluded) -----
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.Size -gt 0 }
    $scanPaths = @()
    foreach ($d in $drives) {
        $path = $d.DeviceID
        $shouldSkip = $false
        foreach ($ex in $ExcludeFolders) {
            if ($path -eq $ex -or $path -like "$ex\*") {
                $shouldSkip = $true
                break
            }
        }
        if (-not $shouldSkip) {
            $scanPaths += $path
        }
    }
    $scanPaths += $env:USERPROFILE
    $scanPaths = $scanPaths | Where-Object { Test-Path $_ } | Select-Object -Unique

    Write-Log "Scanning paths: $($scanPaths -join ', ')" "Info"

    # (dupMinMB and ExcludeFolders now loaded once above via Config.psm1)
    $minSize = $dupMinMB * 1MB
    Write-ProgressEx -Activity "Duplicate Finder" -Status "Scanning files (skipping <${dupMinMB}MB)..." -PercentComplete 5

    # OPTIMIZATION: "$allFiles += obj" in a loop is the classic PowerShell
    # perf trap - a plain array is immutable, so every += rebuilds the
    # whole array (O(n) per append -> O(n^2) overall). With the 100k-200k
    # files this scan can realistically hit, that difference is huge.
    # A Generic List appends in O(1) and behaves the same everywhere else
    # (Group-Object, Sort-Object, etc. all accept it the same as an array).
    $allFilesList = [System.Collections.Generic.List[object]]::new()
    $fileCount = 0

    foreach ($path in $scanPaths) {
        Write-Log "  Scanning: $path" "Info"
        try {
            $files = Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.Length -gt $minSize }
            foreach ($f in $files) {
                $allFilesList.Add([PSCustomObject]@{
                    Path = $f.FullName
                    Name = $f.Name
                    Size = $f.Length
                    SizeHuman = Get-HumanReadableSize -Bytes $f.Length
                    Modified = $f.LastWriteTime
                })
                $fileCount++
                if ($fileCount % 5000 -eq 0) {
                    Write-ProgressEx -Activity "Duplicate Finder" -Status "Scanned $fileCount files..." -PercentComplete 10
                }
            }
        } catch {
            Write-Log "  Error scanning $path : $($_.Exception.Message)" "Warning"
        }
    }
    $allFiles = $allFilesList

    Write-Log "Collected $fileCount files (>1MB)" "Success"

    if ($fileCount -eq 0) {
        Write-Log "No files found" "Warning"
        return $false
    }

    # ----- Step 2: Group by Size (Only groups with duplicates) -----
    Write-ProgressEx -Activity "Duplicate Finder" -Status "Grouping by size..." -PercentComplete 30

    $sizeGroups = $allFiles | Group-Object -Property Size | Where-Object { $_.Count -gt 1 }

    if ($sizeGroups.Count -eq 0) {
        Write-Log "No duplicate sizes found" "Info"
        return $true
    }

    Write-Log "Found $($sizeGroups.Count) sizes with duplicates" "Info"

    # Free memory from allFiles (keep only groups)
    $allFiles = $null
    [System.GC]::Collect()

    # ----- Step 3: Hashing using STREAMING (Memory Safe) -----
    Write-ProgressEx -Activity "Duplicate Finder" -Status "Computing SHA256 hashes (streaming)..." -PercentComplete 50

    $duplicateGroupsList = [System.Collections.Generic.List[object]]::new()
    $totalSizeGroups = $sizeGroups.Count
    $groupIndex = 0
    $totalHashed = 0

    foreach ($group in $sizeGroups) {
        $groupIndex++
        $percent = 50 + (($groupIndex / $totalSizeGroups) * 40)
        Write-ProgressEx -Activity "Duplicate Finder" -Status "Hashing group $groupIndex of $totalSizeGroups..." -PercentComplete $percent

        $files = $group.Group

        # OPTIMIZATION: quick-hash pre-filter. Files here only share a
        # SIZE so far - most same-size files are NOT actual duplicates.
        # Bucket them by a cheap 64KB sample hash first; only buckets
        # with more than one file are even candidates for being real
        # duplicates, so only those need the expensive full SHA256 below.
        $quickBuckets = @{}
        foreach ($file in $files) {
            $quickHash = Get-QuickHash -Path $file.Path
            if ($quickHash) {
                if (-not $quickBuckets.ContainsKey($quickHash)) {
                    $quickBuckets[$quickHash] = [System.Collections.Generic.List[object]]::new()
                }
                $quickBuckets[$quickHash].Add($file)
            }
        }

        $hashMap = @{}
        foreach ($bucketKey in $quickBuckets.Keys) {
            $candidates = $quickBuckets[$bucketKey]
            if ($candidates.Count -lt 2) { continue }  # unique quick hash -> not a duplicate, skip full hash entirely

            foreach ($file in $candidates) {
                Write-ProgressEx -Activity "Duplicate Finder" -Status "Hashing: $($file.Name) ($($file.SizeHuman))" -PercentComplete 55
                $hashValue = Get-StreamingHash -Path $file.Path
                if ($hashValue) {
                    if (-not $hashMap.ContainsKey($hashValue)) {
                        $hashMap[$hashValue] = [System.Collections.Generic.List[object]]::new()
                    }
                    $hashMap[$hashValue].Add($file)
                    $totalHashed++
                }
            }
        }

        # Collect groups with duplicates
        foreach ($key in $hashMap.Keys) {
            if ($hashMap[$key].Count -gt 1) {
                $groupSize = ($hashMap[$key] | Measure-Object -Property Size -Sum).Sum
                $duplicateGroupsList.Add([PSCustomObject]@{
                    Hash = $key
                    FileCount = $hashMap[$key].Count
                    TotalSize = $groupSize
                    TotalSizeHuman = Get-HumanReadableSize -Bytes $groupSize
                    Files = $hashMap[$key]
                })
            }
        }
    }
    $duplicateGroups = $duplicateGroupsList

    Write-ProgressEx -Activity "Duplicate Finder" -Status "Processing complete" -PercentComplete 90

    # ----- Step 4: Sort and Calculate Recovery -----
    $duplicateGroups = $duplicateGroups | Sort-Object -Property TotalSize -Descending

    $totalDuplicateFiles = ($duplicateGroups | Measure-Object -Property FileCount -Sum).Sum
    $totalDuplicateSize = ($duplicateGroups | Measure-Object -Property TotalSize -Sum).Sum
    $recoverableSpace = 0
    foreach ($group in $duplicateGroups) {
        $avgSize = $group.TotalSize / $group.FileCount
        $recoverableSpace += ($group.FileCount - 1) * $avgSize
    }

    Write-Log "Found $($duplicateGroups.Count) duplicate groups" "Success"
    Write-Log "Total duplicate files: $totalDuplicateFiles" "Info"
    Write-Log "Total duplicate size: $(Get-HumanReadableSize -Bytes $totalDuplicateSize)" "Info"
    Write-Log "Potential recoverable space: $(Get-HumanReadableSize -Bytes $recoverableSpace)" "Warning"

    # ----- Step 5: Save Results -----
    Write-ProgressEx -Activity "Duplicate Finder" -Status "Saving results" -PercentComplete 95

    # Flatten for CSV
    $flattenedList = [System.Collections.Generic.List[object]]::new()
    $groupCounter = 1
    foreach ($group in $duplicateGroups) {
        $fileCounter = 1
        foreach ($file in $group.Files) {
            $flattenedList.Add([PSCustomObject]@{
                GroupID = $groupCounter
                FileNumber = $fileCounter
                TotalInGroup = $group.FileCount
                GroupTotalSize = $group.TotalSize
                GroupTotalSizeHuman = $group.TotalSizeHuman
                FilePath = $file.Path
                FileName = $file.Name
                FileSize = $file.Size
                FileSizeHuman = $file.SizeHuman
                Modified = $file.Modified
                Hash = $group.Hash
            })
            $fileCounter++
        }
        $groupCounter++
    }
    $flattened = $flattenedList

    if ($flattened.Count -gt 0) {
        $csvPath = Join-Path $script:OutputCSV "Duplicates.csv"
        $flattened | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Log "Saved Duplicates.csv ($($flattened.Count) rows)" "Success"
    }

    # Summary
    $summary = [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalFilesScanned = $fileCount
        DuplicateGroups = $duplicateGroups.Count
        TotalDuplicateFiles = $totalDuplicateFiles
        TotalDuplicateSize = $totalDuplicateSize
        TotalDuplicateSizeHuman = Get-HumanReadableSize -Bytes $totalDuplicateSize
        RecoverableSpace = $recoverableSpace
        RecoverableSpaceHuman = Get-HumanReadableSize -Bytes $recoverableSpace
    }

    $summary | Export-Csv -Path (Join-Path $script:OutputCSV "DuplicateSummary.csv") -NoTypeInformation
    $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "DuplicateSummary.json")

    Write-ProgressEx -Activity "Duplicate Finder" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "Duplicate Finder" -Completed

    # ----- Display Summary -----
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "DUPLICATE ANALYSIS COMPLETE" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Total Files Scanned (>1MB): $fileCount" -ForegroundColor White
    Write-Host "Duplicate Groups Found: $($duplicateGroups.Count)" -ForegroundColor White
    Write-Host "Total Duplicate Files: $totalDuplicateFiles" -ForegroundColor Gray
    Write-Host "Total Duplicate Size: $(Get-HumanReadableSize -Bytes $totalDuplicateSize)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "POTENTIAL RECOVERABLE SPACE: $(Get-HumanReadableSize -Bytes $recoverableSpace)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Top 5 Duplicate Groups:" -ForegroundColor White
    $topGroups = $duplicateGroups | Select-Object -First 5
    $counter = 1
    foreach ($g in $topGroups) {
        Write-Host "  $counter. $($g.FileCount) files, $($g.TotalSizeHuman)" -ForegroundColor Gray
        $counter++
    }
    Write-Host ""
    Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-Duplicates

# # SystemGuardian/Modules/Duplicates.psm1
# # Duplicate Finder – ULTRA FAST & MEMORY SAFE (Streaming SHA256)
# # Version: 3.0.0

# function Invoke-Duplicates {
#     <#
#     .SYNOPSIS
#         Finds duplicate files using streaming SHA256 (no memory explosion)
#     .DESCRIPTION
#         Uses 8KB chunks for hashing, so 10GB files use only 8KB RAM.
#         Skip files < 1MB to save time.
#     #>

#     # ----- Path Setup -----
#     $script:ModuleDir = $PSScriptRoot
#     $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
#     $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"

#     if (-not (Test-Path $script:OutputCSV)) {
#         New-Item -Path $script:OutputCSV -ItemType Directory -Force | Out-Null
#     }

#     # ----- Logging -----
#     function Write-Log {
#         param(
#             [string]$Message,
#             [string]$Level = "Info"
#         )
#         $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
#         $logEntry = "[$timestamp] [$Level] $Message"
#         $color = switch ($Level) {
#             "Error"   { "Red" }
#             "Warning" { "Yellow" }
#             "Success" { "Green" }
#             default   { "White" }
#         }
#         Write-Host $logEntry -ForegroundColor $color
#     }

#     function Get-HumanReadableSize {
#         param([long]$Bytes)
#         if ($Bytes -lt 0) { return "0 B" }
#         if ($Bytes -eq 0) { return "0 B" }
#         $sizes = @("B", "KB", "MB", "GB", "TB", "PB")
#         $index = 0
#         $size = [double]$Bytes
#         while ($size -ge 1024 -and $index -lt $sizes.Length - 1) {
#             $size /= 1024
#             $index++
#         }
#         return "{0:N2} {1}" -f $size, $sizes[$index]
#     }

#     function Write-ProgressEx {
#         param(
#             [string]$Activity,
#             [string]$Status,
#             [int]$PercentComplete = -1
#         )
#         if ($PercentComplete -ge 0) {
#             Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
#         } else {
#             Write-Progress -Activity $Activity -Status $Status
#         }
#     }

#     # ----- STREAMING HASH (Memory Safe) -----
#     function Get-StreamingHash {
#         param([string]$Path)
#         try {
#             $sha256 = [System.Security.Cryptography.SHA256]::Create()
#             $stream = [System.IO.File]::OpenRead($Path)
#             $buffer = New-Object byte[] 8192  # 8KB buffer
#             [long]$totalRead = 0
#             while ($true) {
#                 $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
#                 if ($bytesRead -eq 0) { break }
#                 $sha256.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
#                 $totalRead += $bytesRead
#                 # Update progress every 100MB to show life
#                 if ($totalRead % 104857600 -lt 8192) {
#                     Write-ProgressEx -Activity "Hashing" -Status "$Path ($(Get-HumanReadableSize -Bytes $totalRead))" -PercentComplete 50
#                 }
#             }
#             $sha256.TransformFinalBlock($null, 0, 0) | Out-Null
#             $hashBytes = $sha256.Hash
#             $hashString = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
#             $stream.Dispose()
#             $sha256.Dispose()
#             return $hashString
#         } catch {
#             return $null
#         }
#     }

#     # ----- QUICK HASH (Cheap pre-filter before full streaming hash) -----
#     # OPTIMIZATION: Files that land in the same size-group are not
#     # necessarily duplicates - many are just coincidentally the same
#     # size (empty templates, fixed-size cache entries, etc). Hashing the
#     # first 64KB of each candidate is far cheaper than a full streaming
#     # SHA256 over a multi-GB file, and any group whose quick hashes
#     # differ is provably not a duplicate - no full hash needed at all.
#     # Files that DO share a quick hash still go through the full
#     # streaming hash below for a definitive, byte-for-byte confirmation,
#     # so final results are identical to hashing everything in full.
#     function Get-QuickHash {
#         param([string]$Path, [long]$SampleBytes = 65536)
#         try {
#             $stream = [System.IO.File]::OpenRead($Path)
#             $toRead = [Math]::Min($SampleBytes, $stream.Length)
#             $buffer = New-Object byte[] $toRead
#             $readSoFar = 0
#             while ($readSoFar -lt $toRead) {
#                 $bytesRead = $stream.Read($buffer, $readSoFar, $toRead - $readSoFar)
#                 if ($bytesRead -eq 0) { break }
#                 $readSoFar += $bytesRead
#             }
#             $stream.Dispose()
#             $sha256 = [System.Security.Cryptography.SHA256]::Create()
#             $hashBytes = $sha256.ComputeHash($buffer, 0, $readSoFar)
#             $sha256.Dispose()
#             return [System.BitConverter]::ToString($hashBytes) -replace '-', ''
#         } catch {
#             return $null
#         }
#     }

#     # ----- Load Exclude Folders from Config -----
#     function Get-ExcludeFolders {
#         $configPath = Join-Path $script:ProjectRoot "Config\config.json"
#         if (Test-Path $configPath) {
#             try {
#                 $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
#                 if ($config.ExcludeFolders) {
#                     return @($config.ExcludeFolders)
#                 }
#             } catch { }
#         }
#         return @("C:\Windows", "C:\ProgramData\Microsoft\Windows\WinSxS", "C:\System Volume Information")
#     }

#     $ExcludeFolders = Get-ExcludeFolders

#     Write-Log "Starting ULTRA FAST Duplicate Analysis (Streaming SHA256)" "Info"

#     # ----- Get Drives (Skip excluded) -----
#     $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.Size -gt 0 }
#     $scanPaths = @()
#     foreach ($d in $drives) {
#         $path = $d.DeviceID
#         $shouldSkip = $false
#         foreach ($ex in $ExcludeFolders) {
#             if ($path -eq $ex -or $path -like "$ex\*") {
#                 $shouldSkip = $true
#                 break
#             }
#         }
#         if (-not $shouldSkip) {
#             $scanPaths += $path
#         }
#     }
#     $scanPaths += $env:USERPROFILE
#     $scanPaths = $scanPaths | Where-Object { Test-Path $_ } | Select-Object -Unique

#     Write-Log "Scanning paths: $($scanPaths -join ', ')" "Info"

#     # ----- Step 1: Collect Files (Skip files below threshold to save time) -----
#     # Minimum size read from config.json (DuplicateMinFileMB); fallback = 1 MB.
#     $dupMinMB = 1
#     $configPath = Join-Path $script:ProjectRoot "Config\config.json"
#     if (Test-Path $configPath) {
#         try {
#             $cfgRaw = Get-Content -Path $configPath -Raw | ConvertFrom-Json
#             if ($cfgRaw.DuplicateAnalysis -and $cfgRaw.DuplicateAnalysis.DuplicateMinFileMB) {
#                 $dupMinMB = [int]$cfgRaw.DuplicateAnalysis.DuplicateMinFileMB
#             }
#         } catch { }
#     }
#     $minSize = $dupMinMB * 1MB
#     Write-ProgressEx -Activity "Duplicate Finder" -Status "Scanning files (skipping <${dupMinMB}MB)..." -PercentComplete 5

#     # OPTIMIZATION: "$allFiles += obj" in a loop is the classic PowerShell
#     # perf trap - a plain array is immutable, so every += rebuilds the
#     # whole array (O(n) per append -> O(n^2) overall). With the 100k-200k
#     # files this scan can realistically hit, that difference is huge.
#     # A Generic List appends in O(1) and behaves the same everywhere else
#     # (Group-Object, Sort-Object, etc. all accept it the same as an array).
#     $allFilesList = [System.Collections.Generic.List[object]]::new()
#     $fileCount = 0

#     foreach ($path in $scanPaths) {
#         Write-Log "  Scanning: $path" "Info"
#         try {
#             $files = Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue |
#                      Where-Object { $_.Length -gt $minSize }
#             foreach ($f in $files) {
#                 $allFilesList.Add([PSCustomObject]@{
#                     Path = $f.FullName
#                     Name = $f.Name
#                     Size = $f.Length
#                     SizeHuman = Get-HumanReadableSize -Bytes $f.Length
#                     Modified = $f.LastWriteTime
#                 })
#                 $fileCount++
#                 if ($fileCount % 5000 -eq 0) {
#                     Write-ProgressEx -Activity "Duplicate Finder" -Status "Scanned $fileCount files..." -PercentComplete 10
#                 }
#             }
#         } catch {
#             Write-Log "  Error scanning $path : $($_.Exception.Message)" "Warning"
#         }
#     }
#     $allFiles = $allFilesList

#     Write-Log "Collected $fileCount files (>1MB)" "Success"

#     if ($fileCount -eq 0) {
#         Write-Log "No files found" "Warning"
#         return $false
#     }

#     # ----- Step 2: Group by Size (Only groups with duplicates) -----
#     Write-ProgressEx -Activity "Duplicate Finder" -Status "Grouping by size..." -PercentComplete 30

#     $sizeGroups = $allFiles | Group-Object -Property Size | Where-Object { $_.Count -gt 1 }

#     if ($sizeGroups.Count -eq 0) {
#         Write-Log "No duplicate sizes found" "Info"
#         return $true
#     }

#     Write-Log "Found $($sizeGroups.Count) sizes with duplicates" "Info"

#     # Free memory from allFiles (keep only groups)
#     $allFiles = $null
#     [System.GC]::Collect()

#     # ----- Step 3: Hashing using STREAMING (Memory Safe) -----
#     Write-ProgressEx -Activity "Duplicate Finder" -Status "Computing SHA256 hashes (streaming)..." -PercentComplete 50

#     $duplicateGroupsList = [System.Collections.Generic.List[object]]::new()
#     $totalSizeGroups = $sizeGroups.Count
#     $groupIndex = 0
#     $totalHashed = 0

#     foreach ($group in $sizeGroups) {
#         $groupIndex++
#         $percent = 50 + (($groupIndex / $totalSizeGroups) * 40)
#         Write-ProgressEx -Activity "Duplicate Finder" -Status "Hashing group $groupIndex of $totalSizeGroups..." -PercentComplete $percent

#         $files = $group.Group

#         # OPTIMIZATION: quick-hash pre-filter. Files here only share a
#         # SIZE so far - most same-size files are NOT actual duplicates.
#         # Bucket them by a cheap 64KB sample hash first; only buckets
#         # with more than one file are even candidates for being real
#         # duplicates, so only those need the expensive full SHA256 below.
#         $quickBuckets = @{}
#         foreach ($file in $files) {
#             $quickHash = Get-QuickHash -Path $file.Path
#             if ($quickHash) {
#                 if (-not $quickBuckets.ContainsKey($quickHash)) {
#                     $quickBuckets[$quickHash] = [System.Collections.Generic.List[object]]::new()
#                 }
#                 $quickBuckets[$quickHash].Add($file)
#             }
#         }

#         $hashMap = @{}
#         foreach ($bucketKey in $quickBuckets.Keys) {
#             $candidates = $quickBuckets[$bucketKey]
#             if ($candidates.Count -lt 2) { continue }  # unique quick hash -> not a duplicate, skip full hash entirely

#             foreach ($file in $candidates) {
#                 Write-ProgressEx -Activity "Duplicate Finder" -Status "Hashing: $($file.Name) ($($file.SizeHuman))" -PercentComplete 55
#                 $hashValue = Get-StreamingHash -Path $file.Path
#                 if ($hashValue) {
#                     if (-not $hashMap.ContainsKey($hashValue)) {
#                         $hashMap[$hashValue] = [System.Collections.Generic.List[object]]::new()
#                     }
#                     $hashMap[$hashValue].Add($file)
#                     $totalHashed++
#                 }
#             }
#         }

#         # Collect groups with duplicates
#         foreach ($key in $hashMap.Keys) {
#             if ($hashMap[$key].Count -gt 1) {
#                 $groupSize = ($hashMap[$key] | Measure-Object -Property Size -Sum).Sum
#                 $duplicateGroupsList.Add([PSCustomObject]@{
#                     Hash = $key
#                     FileCount = $hashMap[$key].Count
#                     TotalSize = $groupSize
#                     TotalSizeHuman = Get-HumanReadableSize -Bytes $groupSize
#                     Files = $hashMap[$key]
#                 })
#             }
#         }
#     }
#     $duplicateGroups = $duplicateGroupsList

#     Write-ProgressEx -Activity "Duplicate Finder" -Status "Processing complete" -PercentComplete 90

#     # ----- Step 4: Sort and Calculate Recovery -----
#     $duplicateGroups = $duplicateGroups | Sort-Object -Property TotalSize -Descending

#     $totalDuplicateFiles = ($duplicateGroups | Measure-Object -Property FileCount -Sum).Sum
#     $totalDuplicateSize = ($duplicateGroups | Measure-Object -Property TotalSize -Sum).Sum
#     $recoverableSpace = 0
#     foreach ($group in $duplicateGroups) {
#         $avgSize = $group.TotalSize / $group.FileCount
#         $recoverableSpace += ($group.FileCount - 1) * $avgSize
#     }

#     Write-Log "Found $($duplicateGroups.Count) duplicate groups" "Success"
#     Write-Log "Total duplicate files: $totalDuplicateFiles" "Info"
#     Write-Log "Total duplicate size: $(Get-HumanReadableSize -Bytes $totalDuplicateSize)" "Info"
#     Write-Log "Potential recoverable space: $(Get-HumanReadableSize -Bytes $recoverableSpace)" "Warning"

#     # ----- Step 5: Save Results -----
#     Write-ProgressEx -Activity "Duplicate Finder" -Status "Saving results" -PercentComplete 95

#     # Flatten for CSV
#     $flattenedList = [System.Collections.Generic.List[object]]::new()
#     $groupCounter = 1
#     foreach ($group in $duplicateGroups) {
#         $fileCounter = 1
#         foreach ($file in $group.Files) {
#             $flattenedList.Add([PSCustomObject]@{
#                 GroupID = $groupCounter
#                 FileNumber = $fileCounter
#                 TotalInGroup = $group.FileCount
#                 GroupTotalSize = $group.TotalSize
#                 GroupTotalSizeHuman = $group.TotalSizeHuman
#                 FilePath = $file.Path
#                 FileName = $file.Name
#                 FileSize = $file.Size
#                 FileSizeHuman = $file.SizeHuman
#                 Modified = $file.Modified
#                 Hash = $group.Hash
#             })
#             $fileCounter++
#         }
#         $groupCounter++
#     }
#     $flattened = $flattenedList

#     if ($flattened.Count -gt 0) {
#         $csvPath = Join-Path $script:OutputCSV "Duplicates.csv"
#         $flattened | Export-Csv -Path $csvPath -NoTypeInformation
#         Write-Log "Saved Duplicates.csv ($($flattened.Count) rows)" "Success"
#     }

#     # Summary
#     $summary = [PSCustomObject]@{
#         Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
#         TotalFilesScanned = $fileCount
#         DuplicateGroups = $duplicateGroups.Count
#         TotalDuplicateFiles = $totalDuplicateFiles
#         TotalDuplicateSize = $totalDuplicateSize
#         TotalDuplicateSizeHuman = Get-HumanReadableSize -Bytes $totalDuplicateSize
#         RecoverableSpace = $recoverableSpace
#         RecoverableSpaceHuman = Get-HumanReadableSize -Bytes $recoverableSpace
#     }

#     $summary | Export-Csv -Path (Join-Path $script:OutputCSV "DuplicateSummary.csv") -NoTypeInformation
#     $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "DuplicateSummary.json")

#     Write-ProgressEx -Activity "Duplicate Finder" -Status "Complete" -PercentComplete 100
#     Write-Progress -Activity "Duplicate Finder" -Completed

#     # ----- Display Summary -----
#     Write-Host ""
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host "DUPLICATE ANALYSIS COMPLETE" -ForegroundColor Yellow
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host ""
#     Write-Host "Total Files Scanned (>1MB): $fileCount" -ForegroundColor White
#     Write-Host "Duplicate Groups Found: $($duplicateGroups.Count)" -ForegroundColor White
#     Write-Host "Total Duplicate Files: $totalDuplicateFiles" -ForegroundColor Gray
#     Write-Host "Total Duplicate Size: $(Get-HumanReadableSize -Bytes $totalDuplicateSize)" -ForegroundColor Gray
#     Write-Host ""
#     Write-Host "POTENTIAL RECOVERABLE SPACE: $(Get-HumanReadableSize -Bytes $recoverableSpace)" -ForegroundColor Yellow
#     Write-Host ""
#     Write-Host "Top 5 Duplicate Groups:" -ForegroundColor White
#     $topGroups = $duplicateGroups | Select-Object -First 5
#     $counter = 1
#     foreach ($g in $topGroups) {
#         Write-Host "  $counter. $($g.FileCount) files, $($g.TotalSizeHuman)" -ForegroundColor Gray
#         $counter++
#     }
#     Write-Host ""
#     Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host ""

#     return $true
# }

# Export-ModuleMember -Function Invoke-Duplicates