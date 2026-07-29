# SystemGuardian/Modules/Browser.psm1
# Browser Analysis – Chrome, Edge, Firefox, Brave
# Cache size, Extensions, Profiles, Download folders
# Version: 1.1.0 (now uses shared Core modules instead of local copies)

Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Formatter.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force

function Invoke-Browser {
    <#
    .SYNOPSIS
        Analyzes browser data from Chrome, Edge, Firefox, and Brave
    .DESCRIPTION
        Collects extension names, cache sizes, profile information, and download folder locations
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

    # ----- Shared Per-Profile Analysis -----
    # OPTIMIZATION: The original had this exact cache/code-cache/extension
    # logic copy-pasted four times (Chrome, Edge, Firefox, Brave) with
    # only folder names differing. Consolidating into one helper doesn't
    # change behavior, but means a future fix only needs to happen once,
    # and each browser's block below is now just "find profiles, call
    # this function" instead of ~35 duplicated lines.
    function Get-BrowserProfileStats {
        param(
            [string]$Browser,
            [System.IO.DirectoryInfo]$Profile,
            [string]$CacheFolderName = "Cache",
            [string]$CodeCacheFolderName = $null,   # $null = browser has no separate code cache (Firefox)
            [string]$ExtensionsFolderName = "Extensions"
        )

        $profilePath = $Profile.FullName

        $cachePath = Join-Path $profilePath $CacheFolderName
        $cacheSize = 0
        if (Test-Path $cachePath) {
            $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        }

        $codeCacheSize = 0
        if ($CodeCacheFolderName) {
            $codeCachePath = Join-Path $profilePath $CodeCacheFolderName
            if (Test-Path $codeCachePath) {
                $codeCacheSize = (Get-ChildItem -Path $codeCachePath -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
            }
        }

        $extensionPath = Join-Path $profilePath $ExtensionsFolderName
        $extensions = @()
        if (Test-Path $extensionPath) {
            $extensions = Get-ChildItem -Path $extensionPath -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name }
        }

        $downloadsPath = "$env:USERPROFILE\Downloads"

        return [PSCustomObject]@{
            Browser             = $Browser
            Profile             = $Profile.Name
            CacheSize           = $cacheSize
            CacheSizeHuman      = Get-HumanReadableSize -Bytes $cacheSize
            CodeCacheSize       = $codeCacheSize
            CodeCacheSizeHuman  = Get-HumanReadableSize -Bytes $codeCacheSize
            TotalCacheSize      = $cacheSize + $codeCacheSize
            TotalCacheSizeHuman = Get-HumanReadableSize -Bytes ($cacheSize + $codeCacheSize)
            ExtensionCount      = $extensions.Count
            Extensions          = ($extensions -join ", ")
            DownloadsPath       = $downloadsPath
        }
    }

    Write-Log "Starting Browser Analysis" "Info"

    # OPTIMIZATION: Generic List instead of array += for the same reason
    # as the other modules in this pass.
    $browserResultsList = [System.Collections.Generic.List[object]]::new()
    $totalBrowsers = 0

    # ----- 1. Google Chrome -----
    Write-ProgressEx -Activity "Browser Analysis" -Status "Analyzing Chrome..." -PercentComplete 10

    $chromeBase = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path $chromeBase) {
        Write-Log "  Analyzing Chrome..." "Info"

        # Get all profiles
        $chromeProfiles = Get-ChildItem -Path $chromeBase -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Default|Profile" }

        foreach ($profile in $chromeProfiles) {
            $browserResultsList.Add((Get-BrowserProfileStats -Browser "Chrome" -Profile $profile -CacheFolderName "Cache" -CodeCacheFolderName "Code Cache" -ExtensionsFolderName "Extensions"))
            $totalBrowsers++
        }
    }

    # ----- 2. Microsoft Edge -----
    Write-ProgressEx -Activity "Browser Analysis" -Status "Analyzing Edge..." -PercentComplete 30

    $edgeBase = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path $edgeBase) {
        Write-Log "  Analyzing Edge..." "Info"

        $edgeProfiles = Get-ChildItem -Path $edgeBase -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Default|Profile" }

        foreach ($profile in $edgeProfiles) {
            $browserResultsList.Add((Get-BrowserProfileStats -Browser "Edge" -Profile $profile -CacheFolderName "Cache" -CodeCacheFolderName "Code Cache" -ExtensionsFolderName "Extensions"))
            $totalBrowsers++
        }
    }

    # ----- 3. Mozilla Firefox -----
    Write-ProgressEx -Activity "Browser Analysis" -Status "Analyzing Firefox..." -PercentComplete 60

    $firefoxBase = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxBase) {
        Write-Log "  Analyzing Firefox..." "Info"

        $firefoxProfiles = Get-ChildItem -Path $firefoxBase -Directory -ErrorAction SilentlyContinue

        foreach ($profile in $firefoxProfiles) {
            $browserResultsList.Add((Get-BrowserProfileStats -Browser "Firefox" -Profile $profile -CacheFolderName "cache2" -CodeCacheFolderName $null -ExtensionsFolderName "extensions"))
            $totalBrowsers++
        }
    }

    # ----- 4. Brave Browser -----
    Write-ProgressEx -Activity "Browser Analysis" -Status "Analyzing Brave..." -PercentComplete 80

    $braveBase = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    if (Test-Path $braveBase) {
        Write-Log "  Analyzing Brave..." "Info"

        $braveProfiles = Get-ChildItem -Path $braveBase -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Default|Profile" }

        foreach ($profile in $braveProfiles) {
            $browserResultsList.Add((Get-BrowserProfileStats -Browser "Brave" -Profile $profile -CacheFolderName "Cache" -CodeCacheFolderName "Code Cache" -ExtensionsFolderName "Extensions"))
            $totalBrowsers++
        }
    }

    $browserResults = $browserResultsList
    Write-Log "  Analyzed $totalBrowsers browser profiles" "Success"

    # ----- Save Results -----
    Write-ProgressEx -Activity "Browser Analysis" -Status "Saving results" -PercentComplete 90

    if ($browserResults.Count -gt 0) {
        $csvPath = Join-Path $script:OutputCSV "BrowserReport.csv"
        $browserResults | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Log "Saved BrowserReport.csv ($($browserResults.Count) records)" "Success"
    }
    else {
        Write-Log "No browser data found" "Warning"
    }

    # Save summary
    # OPTIMIZATION: TotalExtensions is computed once here and reused in
    # the console display below, instead of running the same
    # Measure-Object over $browserResults twice.
    $totalCache = ($browserResults | Measure-Object -Property TotalCacheSize -Sum).Sum
    $totalExtensions = ($browserResults | Measure-Object -Property ExtensionCount -Sum).Sum
    $maxCache = if ($browserResults) { $browserResults | Sort-Object TotalCacheSize -Descending | Select-Object -First 1 } else { $null }

    $summary = [PSCustomObject]@{
        Timestamp            = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalBrowserProfiles = $browserResults.Count
        TotalCacheSize       = $totalCache
        TotalCacheSizeHuman  = Get-HumanReadableSize -Bytes $totalCache
        LargestCacheBrowser  = if ($maxCache) { $maxCache.Browser } else { "N/A" }
        LargestCacheProfile  = if ($maxCache) { $maxCache.Profile } else { "N/A" }
        LargestCacheSize     = if ($maxCache) { $maxCache.TotalCacheSizeHuman } else { "N/A" }
        TotalExtensions      = $totalExtensions
    }

    $summary | Export-Csv -Path (Join-Path $script:OutputCSV "BrowserSummary.csv") -NoTypeInformation
    $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "BrowserSummary.json")

    Write-ProgressEx -Activity "Browser Analysis" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "Browser Analysis" -Completed

    # ----- Display Summary -----
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "BROWSER ANALYSIS COMPLETE" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Total Browser Profiles Analyzed: $totalBrowsers" -ForegroundColor White
    Write-Host "Total Browser Cache Size: $(Get-HumanReadableSize -Bytes $totalCache)" -ForegroundColor White
    Write-Host "Total Extensions Found: $totalExtensions" -ForegroundColor White
    Write-Host ""
    Write-Host "Browser Cache Breakdown:" -ForegroundColor White
    foreach ($b in $browserResults) {
        Write-Host "  $($b.Browser) - $($b.Profile): $($b.TotalCacheSizeHuman)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-Browser
