# SystemGuardian/Modules/Applications.psm1
# Applications & Startup Inventory – Installed software, versions, publishers, startup entries
# Version: 1.1.0 (now uses shared Core modules instead of local copies)

Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Formatter.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force

function Invoke-Applications {
    <#
    .SYNOPSIS
        Collects installed applications and startup programs
    .DESCRIPTION
        Scans registry and startup folders for installed software, versions, publishers, install dates, and startup entries
    #>

    # ----- Path Setup -----
    $script:ModuleDir = $PSScriptRoot
    $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
    $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"

    if (-not (Test-Path $script:OutputCSV)) {
        New-Item -Path $script:OutputCSV -ItemType Directory -Force | Out-Null
    }

    # Write-Log, Get-HumanReadableSize, and Write-ProgressEx now come from
    # Logger.psm1, Formatter.psm1, and Progress.psm1 (imported above).

    # ----- Helper: Get Registry Value Safely -----
    # OPTIMIZATION: The original checked "$Key.GetValueNames() -contains
    # $ValueName" before every GetValue() call. GetValueNames() re-reads
    # and enumerates ALL value names under that key from scratch - and
    # this helper is called ~6 times per installed-app key (DisplayName,
    # DisplayVersion, Publisher, InstallDate, EstimatedSize,
    # UninstallString), so that's 6 full re-enumerations of the same key
    # per app. It's also unnecessary: RegistryKey.GetValue() already
    # returns $null for a value that doesn't exist, so we can call it
    # directly and get identical behavior for a fraction of the cost.
    function Get-RegistryValue {
        param(
            [Microsoft.Win32.RegistryKey]$Key,
            [string]$ValueName
        )
        try {
            if ($Key) {
                return $Key.GetValue($ValueName)
            }
        }
        catch { }
        return $null
    }

    Write-Log "Starting Application & Startup Inventory" "Info"

    # ----- 1. Collect Installed Apps from Registry -----
    Write-ProgressEx -Activity "App Inventory" -Status "Scanning registry for installed apps (64-bit)" -PercentComplete 10

    # OPTIMIZATION: Generic List instead of array += (systems can easily
    # have 200-400+ installed-app registry entries once all three
    # Uninstall hives are counted).
    $allAppsList = [System.Collections.Generic.List[object]]::new()
    $appCount = 0

    # Registry paths for installed applications
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) { continue }
        Write-Log "  Scanning: $path" "Info"
        try {
            $keys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            $keyCount = 0
            foreach ($key in $keys) {
                $keyCount++
                $displayName = Get-RegistryValue -Key $key -ValueName "DisplayName"
                if (-not $displayName) { continue }

                $displayVersion = Get-RegistryValue -Key $key -ValueName "DisplayVersion"
                $publisher = Get-RegistryValue -Key $key -ValueName "Publisher"
                $installDate = Get-RegistryValue -Key $key -ValueName "InstallDate"
                $estimatedSize = Get-RegistryValue -Key $key -ValueName "EstimatedSize"
                $sizeHuman = if ($estimatedSize) { Get-HumanReadableSize -Bytes ($estimatedSize * 1024) } else { "N/A" }
                $uninstallString = Get-RegistryValue -Key $key -ValueName "UninstallString"

                $allAppsList.Add([PSCustomObject]@{
                        Category        = "Installed Application"
                        Name            = $displayName
                        Version         = if ($displayVersion) { $displayVersion } else { "N/A" }
                        Publisher       = if ($publisher) { $publisher } else { "N/A" }
                        InstallDate     = if ($installDate) { $installDate } else { "N/A" }
                        EstimatedSize   = if ($estimatedSize) { $estimatedSize } else { 0 }
                        SizeHuman       = $sizeHuman
                        UninstallString = if ($uninstallString) { $uninstallString.Substring(0, [Math]::Min(100, $uninstallString.Length)) } else { "N/A" }
                        Source          = $path
                    })
                $appCount++

                if ($keyCount % 100 -eq 0) {
                    Write-ProgressEx -Activity "App Inventory" -Status "Scanned $appCount apps..." -PercentComplete 20
                }
            }
        }
        catch {
            Write-Log "  Error scanning $path : $($_.Exception.Message)" "Warning"
        }
    }

    $allApps = $allAppsList
    Write-Log "  Found $appCount installed applications" "Success"

    # ----- 2. Collect Startup Programs -----
    Write-ProgressEx -Activity "App Inventory" -Status "Scanning startup programs" -PercentComplete 50

    $startupEntriesList = [System.Collections.Generic.List[object]]::new()
    $startupCount = 0

    # Registry startup locations
    $startupRegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )

    foreach ($path in $startupRegistryPaths) {
        if (-not (Test-Path $path)) { continue }
        Write-Log "  Scanning startup registry: $path" "Info"
        try {
            $keys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                $name = $key.PSChildName
                $value = $key.GetValue("")
                $startupEntriesList.Add([PSCustomObject]@{
                        Category = "Startup Entry"
                        Name     = $name
                        Command  = if ($value) { $value.Substring(0, [Math]::Min(150, $value.Length)) } else { "N/A" }
                        Type     = "Registry"
                        Location = $path
                    })
                $startupCount++
            }
        }
        catch {
            Write-Log "  Error scanning startup registry $path : $($_.Exception.Message)" "Warning"
        }
    }

    # Startup folders
    $startupFolders = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    )

    foreach ($folder in $startupFolders) {
        if (-not (Test-Path $folder)) { continue }
        Write-Log "  Scanning startup folder: $folder" "Info"
        try {
            $items = Get-ChildItem -Path $folder -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $startupEntriesList.Add([PSCustomObject]@{
                        Category = "Startup Entry"
                        Name     = $item.Name
                        Command  = if ($item.FullName) { $item.FullName.Substring(0, [Math]::Min(150, $item.FullName.Length)) } else { "N/A" }
                        Type     = "Folder"
                        Location = $folder
                    })
                $startupCount++
            }
        }
        catch {
            Write-Log "  Error scanning startup folder $folder : $($_.Exception.Message)" "Warning"
        }
    }

    $startupEntries = $startupEntriesList
    Write-Log "  Found $startupCount startup entries" "Success"

    # ----- 3. Combine and Save Results -----
    Write-ProgressEx -Activity "App Inventory" -Status "Saving results" -PercentComplete 80

    # OPTIMIZATION: Generic List with AddRange/Add instead of "+=" in a
    # loop for combining apps and startup entries.
    $allEntriesList = [System.Collections.Generic.List[object]]::new()
    $allEntriesList.AddRange($allApps)
    foreach ($entry in $startupEntries) {
        $allEntriesList.Add([PSCustomObject]@{
                Category        = $entry.Category
                Name            = $entry.Name
                Version         = "N/A"
                Publisher       = "N/A"
                InstallDate     = "N/A"
                EstimatedSize   = 0
                SizeHuman       = "N/A"
                UninstallString = "N/A"
                Source          = $entry.Location
            })
    }
    $allEntries = $allEntriesList

    $csvPath = Join-Path $script:OutputCSV "InstalledApps.csv"
    $allEntries | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Log "Saved InstalledApps.csv ($($allEntries.Count) records)" "Success"

    # OPTIMIZATION: sort $allApps by size ONCE and reuse it for both the
    # summary's "largest app" fields and the "Top 5" console display
    # below, instead of re-sorting the same collection three times
    # (LargestApp, LargestAppSize, and the Top-5 list each re-sorted
    # independently in the original code).
    $appsBySizeDesc = $allApps | Sort-Object EstimatedSize -Descending
    $largestApp = $appsBySizeDesc | Select-Object -First 1

    # ----- 4. Save Summary -----
    $summary = [PSCustomObject]@{
        Timestamp           = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalInstalledApps  = $appCount
        TotalStartupEntries = $startupCount
        TotalEntries        = $allEntries.Count
        LargestApp          = if ($largestApp) { $largestApp.Name } else { "N/A" }
        LargestAppSize      = if ($largestApp) { $largestApp.SizeHuman } else { "N/A" }
    }

    $summary | Export-Csv -Path (Join-Path $script:OutputCSV "AppSummary.csv") -NoTypeInformation
    $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "AppSummary.json")

    Write-ProgressEx -Activity "App Inventory" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "App Inventory" -Completed

    # ----- Display Summary -----
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "APPLICATION INVENTORY COMPLETE" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Installed Applications: $appCount" -ForegroundColor White
    Write-Host "Startup Entries: $startupCount" -ForegroundColor White
    Write-Host ""
    Write-Host "Top 5 Largest Apps:" -ForegroundColor White
    $topApps = $appsBySizeDesc | Select-Object -First 5
    $counter = 1
    foreach ($app in $topApps) {
        Write-Host "  $counter. $($app.Name) - $($app.SizeHuman)" -ForegroundColor Gray
        $counter++
    }
    Write-Host ""
    Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-Applications







# # SystemGuardian/Modules/Applications.psm1
# # Applications & Startup Inventory – Installed software, versions, publishers, startup entries
# # Version: 1.0.0

# function Invoke-Applications {
#     <#
#     .SYNOPSIS
#         Collects installed applications and startup programs
#     .DESCRIPTION
#         Scans registry and startup folders for installed software, versions, publishers, install dates, and startup entries
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

#     # ----- Helper: Get Registry Value Safely -----
#     # OPTIMIZATION: The original checked "$Key.GetValueNames() -contains
#     # $ValueName" before every GetValue() call. GetValueNames() re-reads
#     # and enumerates ALL value names under that key from scratch - and
#     # this helper is called ~6 times per installed-app key (DisplayName,
#     # DisplayVersion, Publisher, InstallDate, EstimatedSize,
#     # UninstallString), so that's 6 full re-enumerations of the same key
#     # per app. It's also unnecessary: RegistryKey.GetValue() already
#     # returns $null for a value that doesn't exist, so we can call it
#     # directly and get identical behavior for a fraction of the cost.
#     function Get-RegistryValue {
#         param(
#             [Microsoft.Win32.RegistryKey]$Key,
#             [string]$ValueName
#         )
#         try {
#             if ($Key) {
#                 return $Key.GetValue($ValueName)
#             }
#         } catch { }
#         return $null
#     }

#     Write-Log "Starting Application & Startup Inventory" "Info"

#     # ----- 1. Collect Installed Apps from Registry -----
#     Write-ProgressEx -Activity "App Inventory" -Status "Scanning registry for installed apps (64-bit)" -PercentComplete 10

#     # OPTIMIZATION: Generic List instead of array += (systems can easily
#     # have 200-400+ installed-app registry entries once all three
#     # Uninstall hives are counted).
#     $allAppsList = [System.Collections.Generic.List[object]]::new()
#     $appCount = 0

#     # Registry paths for installed applications
#     $registryPaths = @(
#         "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
#         "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
#         "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
#     )

#     foreach ($path in $registryPaths) {
#         if (-not (Test-Path $path)) { continue }
#         Write-Log "  Scanning: $path" "Info"
#         try {
#             $keys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
#             $keyCount = 0
#             foreach ($key in $keys) {
#                 $keyCount++
#                 $displayName = Get-RegistryValue -Key $key -ValueName "DisplayName"
#                 if (-not $displayName) { continue }

#                 $displayVersion = Get-RegistryValue -Key $key -ValueName "DisplayVersion"
#                 $publisher = Get-RegistryValue -Key $key -ValueName "Publisher"
#                 $installDate = Get-RegistryValue -Key $key -ValueName "InstallDate"
#                 $estimatedSize = Get-RegistryValue -Key $key -ValueName "EstimatedSize"
#                 $sizeHuman = if ($estimatedSize) { Get-HumanReadableSize -Bytes ($estimatedSize * 1024) } else { "N/A" }
#                 $uninstallString = Get-RegistryValue -Key $key -ValueName "UninstallString"

#                 $allAppsList.Add([PSCustomObject]@{
#                     Category        = "Installed Application"
#                     Name            = $displayName
#                     Version         = if ($displayVersion) { $displayVersion } else { "N/A" }
#                     Publisher       = if ($publisher) { $publisher } else { "N/A" }
#                     InstallDate     = if ($installDate) { $installDate } else { "N/A" }
#                     EstimatedSize   = if ($estimatedSize) { $estimatedSize } else { 0 }
#                     SizeHuman       = $sizeHuman
#                     UninstallString = if ($uninstallString) { $uninstallString.Substring(0, [Math]::Min(100, $uninstallString.Length)) } else { "N/A" }
#                     Source          = $path
#                 })
#                 $appCount++

#                 if ($keyCount % 100 -eq 0) {
#                     Write-ProgressEx -Activity "App Inventory" -Status "Scanned $appCount apps..." -PercentComplete 20
#                 }
#             }
#         } catch {
#             Write-Log "  Error scanning $path : $($_.Exception.Message)" "Warning"
#         }
#     }

#     $allApps = $allAppsList
#     Write-Log "  Found $appCount installed applications" "Success"

#     # ----- 2. Collect Startup Programs -----
#     Write-ProgressEx -Activity "App Inventory" -Status "Scanning startup programs" -PercentComplete 50

#     $startupEntriesList = [System.Collections.Generic.List[object]]::new()
#     $startupCount = 0

#     # Registry startup locations
#     $startupRegistryPaths = @(
#         "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
#         "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
#         "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
#     )

#     foreach ($path in $startupRegistryPaths) {
#         if (-not (Test-Path $path)) { continue }
#         Write-Log "  Scanning startup registry: $path" "Info"
#         try {
#             $keys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
#             foreach ($key in $keys) {
#                 $name = $key.PSChildName
#                 $value = $key.GetValue("")
#                 $startupEntriesList.Add([PSCustomObject]@{
#                     Category    = "Startup Entry"
#                     Name        = $name
#                     Command     = if ($value) { $value.Substring(0, [Math]::Min(150, $value.Length)) } else { "N/A" }
#                     Type        = "Registry"
#                     Location    = $path
#                 })
#                 $startupCount++
#             }
#         } catch {
#             Write-Log "  Error scanning startup registry $path : $($_.Exception.Message)" "Warning"
#         }
#     }

#     # Startup folders
#     $startupFolders = @(
#         "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
#         "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"
#     )

#     foreach ($folder in $startupFolders) {
#         if (-not (Test-Path $folder)) { continue }
#         Write-Log "  Scanning startup folder: $folder" "Info"
#         try {
#             $items = Get-ChildItem -Path $folder -ErrorAction SilentlyContinue
#             foreach ($item in $items) {
#                 $startupEntriesList.Add([PSCustomObject]@{
#                     Category    = "Startup Entry"
#                     Name        = $item.Name
#                     Command     = if ($item.FullName) { $item.FullName.Substring(0, [Math]::Min(150, $item.FullName.Length)) } else { "N/A" }
#                     Type        = "Folder"
#                     Location    = $folder
#                 })
#                 $startupCount++
#             }
#         } catch {
#             Write-Log "  Error scanning startup folder $folder : $($_.Exception.Message)" "Warning"
#         }
#     }

#     $startupEntries = $startupEntriesList
#     Write-Log "  Found $startupCount startup entries" "Success"

#     # ----- 3. Combine and Save Results -----
#     Write-ProgressEx -Activity "App Inventory" -Status "Saving results" -PercentComplete 80

#     # OPTIMIZATION: Generic List with AddRange/Add instead of "+=" in a
#     # loop for combining apps and startup entries.
#     $allEntriesList = [System.Collections.Generic.List[object]]::new()
#     $allEntriesList.AddRange($allApps)
#     foreach ($entry in $startupEntries) {
#         $allEntriesList.Add([PSCustomObject]@{
#             Category        = $entry.Category
#             Name            = $entry.Name
#             Version         = "N/A"
#             Publisher       = "N/A"
#             InstallDate     = "N/A"
#             EstimatedSize   = 0
#             SizeHuman       = "N/A"
#             UninstallString = "N/A"
#             Source          = $entry.Location
#         })
#     }
#     $allEntries = $allEntriesList

#     $csvPath = Join-Path $script:OutputCSV "InstalledApps.csv"
#     $allEntries | Export-Csv -Path $csvPath -NoTypeInformation
#     Write-Log "Saved InstalledApps.csv ($($allEntries.Count) records)" "Success"

#     # OPTIMIZATION: sort $allApps by size ONCE and reuse it for both the
#     # summary's "largest app" fields and the "Top 5" console display
#     # below, instead of re-sorting the same collection three times
#     # (LargestApp, LargestAppSize, and the Top-5 list each re-sorted
#     # independently in the original code).
#     $appsBySizeDesc = $allApps | Sort-Object EstimatedSize -Descending
#     $largestApp = $appsBySizeDesc | Select-Object -First 1

#     # ----- 4. Save Summary -----
#     $summary = [PSCustomObject]@{
#         Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
#         TotalInstalledApps = $appCount
#         TotalStartupEntries = $startupCount
#         TotalEntries = $allEntries.Count
#         LargestApp = if ($largestApp) { $largestApp.Name } else { "N/A" }
#         LargestAppSize = if ($largestApp) { $largestApp.SizeHuman } else { "N/A" }
#     }

#     $summary | Export-Csv -Path (Join-Path $script:OutputCSV "AppSummary.csv") -NoTypeInformation
#     $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "AppSummary.json")

#     Write-ProgressEx -Activity "App Inventory" -Status "Complete" -PercentComplete 100
#     Write-Progress -Activity "App Inventory" -Completed

#     # ----- Display Summary -----
#     Write-Host ""
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host "APPLICATION INVENTORY COMPLETE" -ForegroundColor Yellow
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host ""
#     Write-Host "Installed Applications: $appCount" -ForegroundColor White
#     Write-Host "Startup Entries: $startupCount" -ForegroundColor White
#     Write-Host ""
#     Write-Host "Top 5 Largest Apps:" -ForegroundColor White
#     $topApps = $appsBySizeDesc | Select-Object -First 5
#     $counter = 1
#     foreach ($app in $topApps) {
#         Write-Host "  $counter. $($app.Name) - $($app.SizeHuman)" -ForegroundColor Gray
#         $counter++
#     }
#     Write-Host ""
#     Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host ""

#     return $true
# }

# Export-ModuleMember -Function Invoke-Applications
