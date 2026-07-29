# SystemGuardian/Modules/SystemInfo.psm1
# System Information Collector – Final Safe Version
# Version: 1.1.0 (now uses shared Core modules instead of local copies)

# Core shared modules. -Force ensures we get the latest version even if
# another module already imported an older instance in this session.
Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force

function Invoke-SystemInfo {
    <#
    .SYNOPSIS
        Collects detailed system hardware and OS information
    #>

    # ----- Robust Path Setup -----
    $script:ModuleDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
    $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"

    if (-not (Test-Path $script:OutputCSV)) {
        New-Item -Path $script:OutputCSV -ItemType Directory -Force | Out-Null
    }

    # Write-Log and Write-ProgressEx now come from Logger.psm1 and
    # Progress.psm1 (imported above) instead of being redefined locally here.

    Write-Log "Starting System Information Collection" "Info"

    # ----- 1. OS & Computer -----
    Write-ProgressEx -Activity "System Info" -Status "Collecting OS information" -PercentComplete 5
    # OPTIMIZATION: Legacy WMI query is deprecated in favor of Get-CimInstance
    # (faster, no legacy DCOM overhead for local queries). This single
    # Win32_OperatingSystem query is also reused later for the RAM
    # section and the uptime section instead of querying it two more
    # times, which the original code did.
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem

    # OPTIMIZATION: $results collects ~40+ rows via repeated appends.
    # A Generic List avoids the array-copy-per-append cost of "+=" on a
    # plain array (small collection here, but the pattern is fixed
    # consistently across every module in this pass).
    $results = [System.Collections.Generic.List[object]]::new()
    $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Name"; Value = $os.Caption })
    $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Build Number"; Value = $os.BuildNumber })
    $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Version"; Value = $os.Version })
    $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Architecture"; Value = $os.OSArchitecture })
    $results.Add([PSCustomObject]@{ Category = "Computer"; Property = "Name"; Value = $env:COMPUTERNAME })
    $results.Add([PSCustomObject]@{ Category = "Computer"; Property = "Domain"; Value = $computer.Domain })

    Write-Log "  OS: $($os.Caption) ($($os.OSArchitecture))" "Info"

    # ----- 2. CPU -----
    Write-ProgressEx -Activity "System Info" -Status "Collecting CPU information" -PercentComplete 15
    $cpu = Get-CimInstance -ClassName Win32_Processor
    if ($cpu) {
        $firstCpu = $cpu | Select-Object -First 1
        $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Name"; Value = $firstCpu.Name.Trim() })
        $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Cores"; Value = $firstCpu.NumberOfCores })
        $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Logical Processors"; Value = $firstCpu.NumberOfLogicalProcessors })
        $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Max Clock Speed (MHz)"; Value = $firstCpu.MaxClockSpeed })
        $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Socket Designation"; Value = $firstCpu.SocketDesignation })
        Write-Log "  CPU: $($firstCpu.Name.Trim()) ($($firstCpu.NumberOfCores) Cores)" "Info"
    }
    else {
        $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Status"; Value = "No CPU found" })
        Write-Log "  CPU: Not found" "Warning"
    }

    # ----- 3. RAM -----
    Write-ProgressEx -Activity "System Info" -Status "Collecting RAM information" -PercentComplete 30
    $totalRAM = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Total Physical Memory (GB)"; Value = $totalRAM })

    $memoryModules = Get-CimInstance -ClassName Win32_PhysicalMemory
    if ($memoryModules) {
        $slotCount = 0
        foreach ($mod in $memoryModules) {
            $slotCount++
            $sizeGB = [math]::Round($mod.Capacity / 1GB, 0)
            $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Size (GB)"; Value = $sizeGB })
            $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Speed (MHz)"; Value = $mod.Speed })
            $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Manufacturer"; Value = $mod.Manufacturer })
            $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Part Number"; Value = $mod.PartNumber })
        }
    }

    # OPTIMIZATION: reuse the $os object from section 1 instead of
    # issuing a second Win32_OperatingSystem query just for these two
    # fields (Get-CimInstance already has FreePhysicalMemory and
    # TotalVisibleMemorySize on the same object).
    $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $totalRAMGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $usedRAM = $totalRAMGB - $freeRAM
    $ramPercentUsed = [math]::Round(($usedRAM / $totalRAMGB) * 100, 1)

    $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Total RAM (GB)"; Value = [math]::Round($totalRAMGB, 0) })
    $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Used RAM (GB)"; Value = [math]::Round($usedRAM, 0) })
    $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Free RAM (GB)"; Value = [math]::Round($freeRAM, 0) })
    $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "RAM Usage (%)"; Value = "$ramPercentUsed%" })

    Write-Log "  RAM: $([math]::Round($totalRAMGB, 0)) GB total, $([math]::Round($freeRAM, 0)) GB free ($ramPercentUsed% used)" "Info"

    # ----- 4. GPU (Safe) -----
    Write-ProgressEx -Activity "System Info" -Status "Collecting GPU information" -PercentComplete 50
    $gpus = Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Mirror*" }
    $gpuCount = 0
    foreach ($gpu in $gpus) {
        $gpuCount++
        $gpuName = if ($gpu.Name) { $gpu.Name.Trim() } else { "Unknown GPU" }
        $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Name"; Value = $gpuName })
        $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Driver Version"; Value = if ($gpu.DriverVersion) { $gpu.DriverVersion } else { "N/A" } })
        $ramMB = if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) { [math]::Round($gpu.AdapterRAM / 1MB, 0) } else { 0 }
        $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Video Memory (MB)"; Value = $ramMB })
        $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Status"; Value = if ($gpu.Status) { $gpu.Status } else { "Unknown" } })
        if ($gpuCount -eq 1) {
            Write-Log "  GPU: $gpuName" "Info"
        }
    }
    if ($gpuCount -eq 0) {
        $results.Add([PSCustomObject]@{ Category = "GPU"; Property = "Status"; Value = "No dedicated GPU found" })
        Write-Log "  GPU: No dedicated GPU found" "Info"
    }

    # ----- 5. Motherboard -----
    Write-ProgressEx -Activity "System Info" -Status "Collecting motherboard information" -PercentComplete 65
    $motherboard = Get-CimInstance -ClassName Win32_BaseBoard
    if ($motherboard) {
        $mb = $motherboard | Select-Object -First 1
        $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Manufacturer"; Value = if ($mb.Manufacturer) { $mb.Manufacturer } else { "N/A" } })
        $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Model"; Value = if ($mb.Product) { $mb.Product } else { "N/A" } })
        $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Serial Number"; Value = if ($mb.SerialNumber) { $mb.SerialNumber } else { "N/A" } })
        $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Version"; Value = if ($mb.Version) { $mb.Version } else { "N/A" } })
        Write-Log "  Motherboard: $($mb.Manufacturer) $($mb.Product)" "Info"
    }
    else {
        $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Status"; Value = "Not found" })
        Write-Log "  Motherboard: Not found" "Warning"
    }

    # ----- 6. Disk -----
    Write-ProgressEx -Activity "System Info" -Status "Collecting disk information" -PercentComplete 80
    $disks = Get-CimInstance -ClassName Win32_DiskDrive | Where-Object { $_.InterfaceType -ne "USB" }
    $diskIndex = 0
    foreach ($disk in $disks) {
        $diskIndex++
        $model = if ($disk.Model) { $disk.Model.Trim() } else { "Unknown" }
        $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 0) } else { 0 }
        $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Model"; Value = $model })
        $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Size (GB)"; Value = $sizeGB })
        $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Interface Type"; Value = if ($disk.InterfaceType) { $disk.InterfaceType } else { "Unknown" } })
        $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Media Type"; Value = if ($disk.MediaType) { $disk.MediaType } else { "Unknown" } })
        $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Serial Number"; Value = if ($disk.SerialNumber) { $disk.SerialNumber } else { "N/A" } })
        if ($diskIndex -eq 1) {
            Write-Log "  Disk: $model ($sizeGB GB)" "Info"
        }
    }
    if ($diskIndex -eq 0) {
        $results.Add([PSCustomObject]@{ Category = "Disk"; Property = "Status"; Value = "No disks found" })
        Write-Log "  Disk: None found" "Warning"
    }

    # ----- 7. PowerShell -----
    Write-ProgressEx -Activity "System Info" -Status "Collecting PowerShell version" -PercentComplete 90
    $psVersion = $PSVersionTable.PSVersion.ToString()
    $results.Add([PSCustomObject]@{ Category = "PowerShell"; Property = "Version"; Value = $psVersion })
    Write-Log "  PowerShell Version: $psVersion" "Info"

    # ----- 8. .NET -----
    try {
        $dotNetVersion = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -ErrorAction SilentlyContinue |
        Get-ItemPropertyValue -Name Release -ErrorAction SilentlyContinue
        if ($dotNetVersion) {
            $results.Add([PSCustomObject]@{ Category = ".NET Framework"; Property = "Version"; Value = $dotNetVersion })
        }
    }
    catch { }

    # ----- 9. Timezone & Uptime -----
    # OPTIMIZATION: LastBootUpTime comes from the same $os object queried
    # once in section 1, instead of a third separate CIM/WMI call to
    # Win32_OperatingSystem.
    $tz = (Get-TimeZone).DisplayName
    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeDays = [math]::Round($uptime.TotalDays, 1)
    $results.Add([PSCustomObject]@{ Category = "System"; Property = "Timezone"; Value = $tz })
    $results.Add([PSCustomObject]@{ Category = "System"; Property = "Uptime (Days)"; Value = $uptimeDays })
    Write-Log "  Uptime: $uptimeDays days" "Info"

    # ----- Save main CSV -----
    Write-ProgressEx -Activity "System Info" -Status "Saving results" -PercentComplete 95
    $csvPath = Join-Path $script:OutputCSV "SystemInfo.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Log "Saved SystemInfo.csv ($($results.Count) records)" "Success"

    # ----- Save Summary (with error handling) -----
    try {
        # Safe access to objects
        $cpuName = if ($cpu -and $cpu[0]) { $cpu[0].Name.Trim() } else { "N/A" }
        $cpuCores = if ($cpu -and $cpu[0]) { $cpu[0].NumberOfCores } else { 0 }
        $gpuName = if ($gpus -and $gpus.Count -gt 0 -and $gpus[0].Name) { $gpus[0].Name.Trim() } else { "None" }
        $mbManufacturer = if ($motherboard -and $motherboard[0] -and $motherboard[0].Manufacturer) { $motherboard[0].Manufacturer } else { "N/A" }
        $mbProduct = if ($motherboard -and $motherboard[0] -and $motherboard[0].Product) { $motherboard[0].Product } else { "N/A" }
        $diskModel = if ($disks -and $disks[0] -and $disks[0].Model) { $disks[0].Model.Trim() } else { "None" }
        $diskSize = if ($disks -and $disks[0] -and $disks[0].Size) { [math]::Round($disks[0].Size / 1GB, 0) } else { 0 }

        $summary = [PSCustomObject]@{
            Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ComputerName      = $env:COMPUTERNAME
            OS                = $os.Caption
            OSBuild           = $os.BuildNumber
            CPU               = $cpuName
            Cores             = $cpuCores
            TotalRAM          = [math]::Round($totalRAMGB, 0)
            FreeRAM           = [math]::Round($freeRAM, 0)
            GPU               = $gpuName
            Motherboard       = "$mbManufacturer $mbProduct"
            Disk              = "$diskModel ($diskSize GB)"
            PowerShellVersion = $psVersion
            UptimeDays        = $uptimeDays
        }

        $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "SystemInfoSummary.json")
        $summary | Export-Csv -Path (Join-Path $script:OutputCSV "SystemInfoSummary.csv") -NoTypeInformation
        Write-Log "Saved summary files" "Success"
    }
    catch {
        Write-Log "Summary export failed: $($_.Exception.Message)" "Warning"
        # Continue anyway
    }

    Write-ProgressEx -Activity "System Info" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "System Info" -Completed

    # ----- Display -----
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "SYSTEM INFORMATION COMPLETE" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "OS: $($os.Caption) Build $($os.BuildNumber)" -ForegroundColor White
    Write-Host "CPU: $($cpu[0].Name.Trim()) ($($cpu[0].NumberOfCores) Cores)" -ForegroundColor White
    Write-Host "RAM: $([math]::Round($totalRAMGB, 0)) GB ($([math]::Round($freeRAM, 0)) GB free)" -ForegroundColor White
    $gpuDisplay = if ($gpus.Count -gt 0) { $gpus[0].Name.Trim() } else { "None" }
    Write-Host "GPU: $gpuDisplay" -ForegroundColor White
    $mbDisplay = "$($motherboard[0].Manufacturer) $($motherboard[0].Product)"
    Write-Host "Motherboard: $mbDisplay" -ForegroundColor White
    $diskDisplay = "$($disks[0].Model.Trim()) ($([math]::Round($disks[0].Size / 1GB, 0)) GB)"
    Write-Host "Disk: $diskDisplay" -ForegroundColor White
    Write-Host "Uptime: $uptimeDays days" -ForegroundColor White
    Write-Host ""
    Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-SystemInfo

# # SystemGuardian/Modules/SystemInfo.psm1
# # System Information Collector – Final Safe Version
# # Version: 1.0.3

# function Invoke-SystemInfo {
#     <#
#     .SYNOPSIS
#         Collects detailed system hardware and OS information
#     #>

#     # ----- Robust Path Setup -----
#     $script:ModuleDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
#     $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
#     $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"

#     if (-not (Test-Path $script:OutputCSV)) {
#         New-Item -Path $script:OutputCSV -ItemType Directory -Force | Out-Null
#     }

#     # ----- Logging -----
#     function Write-Log {
#         param([string]$Message, [string]$Level = "Info")
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

#     function Write-ProgressEx {
#         param([string]$Activity, [string]$Status, [int]$PercentComplete = -1)
#         if ($PercentComplete -ge 0) {
#             Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
#         } else {
#             Write-Progress -Activity $Activity -Status $Status
#         }
#     }

#     Write-Log "Starting System Information Collection" "Info"

#     # ----- 1. OS & Computer -----
#     Write-ProgressEx -Activity "System Info" -Status "Collecting OS information" -PercentComplete 5
#     # OPTIMIZATION: Legacy WMI query is deprecated in favor of Get-CimInstance
#     # (faster, no legacy DCOM overhead for local queries). This single
#     # Win32_OperatingSystem query is also reused later for the RAM
#     # section and the uptime section instead of querying it two more
#     # times, which the original code did.
#     $os = Get-CimInstance -ClassName Win32_OperatingSystem
#     $computer = Get-CimInstance -ClassName Win32_ComputerSystem

#     # OPTIMIZATION: $results collects ~40+ rows via repeated appends.
#     # A Generic List avoids the array-copy-per-append cost of "+=" on a
#     # plain array (small collection here, but the pattern is fixed
#     # consistently across every module in this pass).
#     $results = [System.Collections.Generic.List[object]]::new()
#     $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Name"; Value = $os.Caption })
#     $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Build Number"; Value = $os.BuildNumber })
#     $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Version"; Value = $os.Version })
#     $results.Add([PSCustomObject]@{ Category = "Operating System"; Property = "Architecture"; Value = $os.OSArchitecture })
#     $results.Add([PSCustomObject]@{ Category = "Computer"; Property = "Name"; Value = $env:COMPUTERNAME })
#     $results.Add([PSCustomObject]@{ Category = "Computer"; Property = "Domain"; Value = $computer.Domain })

#     Write-Log "  OS: $($os.Caption) ($($os.OSArchitecture))" "Info"

#     # ----- 2. CPU -----
#     Write-ProgressEx -Activity "System Info" -Status "Collecting CPU information" -PercentComplete 15
#     $cpu = Get-CimInstance -ClassName Win32_Processor
#     if ($cpu) {
#         $firstCpu = $cpu | Select-Object -First 1
#         $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Name"; Value = $firstCpu.Name.Trim() })
#         $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Cores"; Value = $firstCpu.NumberOfCores })
#         $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Logical Processors"; Value = $firstCpu.NumberOfLogicalProcessors })
#         $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Max Clock Speed (MHz)"; Value = $firstCpu.MaxClockSpeed })
#         $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Socket Designation"; Value = $firstCpu.SocketDesignation })
#         Write-Log "  CPU: $($firstCpu.Name.Trim()) ($($firstCpu.NumberOfCores) Cores)" "Info"
#     } else {
#         $results.Add([PSCustomObject]@{ Category = "CPU"; Property = "Status"; Value = "No CPU found" })
#         Write-Log "  CPU: Not found" "Warning"
#     }

#     # ----- 3. RAM -----
#     Write-ProgressEx -Activity "System Info" -Status "Collecting RAM information" -PercentComplete 30
#     $totalRAM = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
#     $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Total Physical Memory (GB)"; Value = $totalRAM })

#     $memoryModules = Get-CimInstance -ClassName Win32_PhysicalMemory
#     if ($memoryModules) {
#         $slotCount = 0
#         foreach ($mod in $memoryModules) {
#             $slotCount++
#             $sizeGB = [math]::Round($mod.Capacity / 1GB, 0)
#             $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Size (GB)"; Value = $sizeGB })
#             $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Speed (MHz)"; Value = $mod.Speed })
#             $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Manufacturer"; Value = $mod.Manufacturer })
#             $results.Add([PSCustomObject]@{ Category = "RAM - Module $slotCount"; Property = "Part Number"; Value = $mod.PartNumber })
#         }
#     }

#     # OPTIMIZATION: reuse the $os object from section 1 instead of
#     # issuing a second Win32_OperatingSystem query just for these two
#     # fields (Get-CimInstance already has FreePhysicalMemory and
#     # TotalVisibleMemorySize on the same object).
#     $freeRAM = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
#     $totalRAMGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
#     $usedRAM = $totalRAMGB - $freeRAM
#     $ramPercentUsed = [math]::Round(($usedRAM / $totalRAMGB) * 100, 1)

#     $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Total RAM (GB)"; Value = [math]::Round($totalRAMGB, 0) })
#     $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Used RAM (GB)"; Value = [math]::Round($usedRAM, 0) })
#     $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "Free RAM (GB)"; Value = [math]::Round($freeRAM, 0) })
#     $results.Add([PSCustomObject]@{ Category = "RAM"; Property = "RAM Usage (%)"; Value = "$ramPercentUsed%" })

#     Write-Log "  RAM: $([math]::Round($totalRAMGB, 0)) GB total, $([math]::Round($freeRAM, 0)) GB free ($ramPercentUsed% used)" "Info"

#     # ----- 4. GPU (Safe) -----
#     Write-ProgressEx -Activity "System Info" -Status "Collecting GPU information" -PercentComplete 50
#     $gpus = Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Mirror*" }
#     $gpuCount = 0
#     foreach ($gpu in $gpus) {
#         $gpuCount++
#         $gpuName = if ($gpu.Name) { $gpu.Name.Trim() } else { "Unknown GPU" }
#         $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Name"; Value = $gpuName })
#         $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Driver Version"; Value = if ($gpu.DriverVersion) { $gpu.DriverVersion } else { "N/A" } })
#         $ramMB = if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) { [math]::Round($gpu.AdapterRAM / 1MB, 0) } else { 0 }
#         $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Video Memory (MB)"; Value = $ramMB })
#         $results.Add([PSCustomObject]@{ Category = "GPU $gpuCount"; Property = "Status"; Value = if ($gpu.Status) { $gpu.Status } else { "Unknown" } })
#         if ($gpuCount -eq 1) {
#             Write-Log "  GPU: $gpuName" "Info"
#         }
#     }
#     if ($gpuCount -eq 0) {
#         $results.Add([PSCustomObject]@{ Category = "GPU"; Property = "Status"; Value = "No dedicated GPU found" })
#         Write-Log "  GPU: No dedicated GPU found" "Info"
#     }

#     # ----- 5. Motherboard -----
#     Write-ProgressEx -Activity "System Info" -Status "Collecting motherboard information" -PercentComplete 65
#     $motherboard = Get-CimInstance -ClassName Win32_BaseBoard
#     if ($motherboard) {
#         $mb = $motherboard | Select-Object -First 1
#         $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Manufacturer"; Value = if ($mb.Manufacturer) { $mb.Manufacturer } else { "N/A" } })
#         $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Model"; Value = if ($mb.Product) { $mb.Product } else { "N/A" } })
#         $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Serial Number"; Value = if ($mb.SerialNumber) { $mb.SerialNumber } else { "N/A" } })
#         $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Version"; Value = if ($mb.Version) { $mb.Version } else { "N/A" } })
#         Write-Log "  Motherboard: $($mb.Manufacturer) $($mb.Product)" "Info"
#     } else {
#         $results.Add([PSCustomObject]@{ Category = "Motherboard"; Property = "Status"; Value = "Not found" })
#         Write-Log "  Motherboard: Not found" "Warning"
#     }

#     # ----- 6. Disk -----
#     Write-ProgressEx -Activity "System Info" -Status "Collecting disk information" -PercentComplete 80
#     $disks = Get-CimInstance -ClassName Win32_DiskDrive | Where-Object { $_.InterfaceType -ne "USB" }
#     $diskIndex = 0
#     foreach ($disk in $disks) {
#         $diskIndex++
#         $model = if ($disk.Model) { $disk.Model.Trim() } else { "Unknown" }
#         $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 0) } else { 0 }
#         $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Model"; Value = $model })
#         $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Size (GB)"; Value = $sizeGB })
#         $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Interface Type"; Value = if ($disk.InterfaceType) { $disk.InterfaceType } else { "Unknown" } })
#         $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Media Type"; Value = if ($disk.MediaType) { $disk.MediaType } else { "Unknown" } })
#         $results.Add([PSCustomObject]@{ Category = "Disk $diskIndex"; Property = "Serial Number"; Value = if ($disk.SerialNumber) { $disk.SerialNumber } else { "N/A" } })
#         if ($diskIndex -eq 1) {
#             Write-Log "  Disk: $model ($sizeGB GB)" "Info"
#         }
#     }
#     if ($diskIndex -eq 0) {
#         $results.Add([PSCustomObject]@{ Category = "Disk"; Property = "Status"; Value = "No disks found" })
#         Write-Log "  Disk: None found" "Warning"
#     }

#     # ----- 7. PowerShell -----
#     Write-ProgressEx -Activity "System Info" -Status "Collecting PowerShell version" -PercentComplete 90
#     $psVersion = $PSVersionTable.PSVersion.ToString()
#     $results.Add([PSCustomObject]@{ Category = "PowerShell"; Property = "Version"; Value = $psVersion })
#     Write-Log "  PowerShell Version: $psVersion" "Info"

#     # ----- 8. .NET -----
#     try {
#         $dotNetVersion = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -ErrorAction SilentlyContinue |
#                          Get-ItemPropertyValue -Name Release -ErrorAction SilentlyContinue
#         if ($dotNetVersion) {
#             $results.Add([PSCustomObject]@{ Category = ".NET Framework"; Property = "Version"; Value = $dotNetVersion })
#         }
#     } catch { }

#     # ----- 9. Timezone & Uptime -----
#     # OPTIMIZATION: LastBootUpTime comes from the same $os object queried
#     # once in section 1, instead of a third separate CIM/WMI call to
#     # Win32_OperatingSystem.
#     $tz = (Get-TimeZone).DisplayName
#     $uptime = (Get-Date) - $os.LastBootUpTime
#     $uptimeDays = [math]::Round($uptime.TotalDays, 1)
#     $results.Add([PSCustomObject]@{ Category = "System"; Property = "Timezone"; Value = $tz })
#     $results.Add([PSCustomObject]@{ Category = "System"; Property = "Uptime (Days)"; Value = $uptimeDays })
#     Write-Log "  Uptime: $uptimeDays days" "Info"

#     # ----- Save main CSV -----
#     Write-ProgressEx -Activity "System Info" -Status "Saving results" -PercentComplete 95
#     $csvPath = Join-Path $script:OutputCSV "SystemInfo.csv"
#     $results | Export-Csv -Path $csvPath -NoTypeInformation
#     Write-Log "Saved SystemInfo.csv ($($results.Count) records)" "Success"

#     # ----- Save Summary (with error handling) -----
#     try {
#         # Safe access to objects
#         $cpuName = if ($cpu -and $cpu[0]) { $cpu[0].Name.Trim() } else { "N/A" }
#         $cpuCores = if ($cpu -and $cpu[0]) { $cpu[0].NumberOfCores } else { 0 }
#         $gpuName = if ($gpus -and $gpus.Count -gt 0 -and $gpus[0].Name) { $gpus[0].Name.Trim() } else { "None" }
#         $mbManufacturer = if ($motherboard -and $motherboard[0] -and $motherboard[0].Manufacturer) { $motherboard[0].Manufacturer } else { "N/A" }
#         $mbProduct = if ($motherboard -and $motherboard[0] -and $motherboard[0].Product) { $motherboard[0].Product } else { "N/A" }
#         $diskModel = if ($disks -and $disks[0] -and $disks[0].Model) { $disks[0].Model.Trim() } else { "None" }
#         $diskSize = if ($disks -and $disks[0] -and $disks[0].Size) { [math]::Round($disks[0].Size / 1GB, 0) } else { 0 }

#         $summary = [PSCustomObject]@{
#             Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
#             ComputerName = $env:COMPUTERNAME
#             OS = $os.Caption
#             OSBuild = $os.BuildNumber
#             CPU = $cpuName
#             Cores = $cpuCores
#             TotalRAM = [math]::Round($totalRAMGB, 0)
#             FreeRAM = [math]::Round($freeRAM, 0)
#             GPU = $gpuName
#             Motherboard = "$mbManufacturer $mbProduct"
#             Disk = "$diskModel ($diskSize GB)"
#             PowerShellVersion = $psVersion
#             UptimeDays = $uptimeDays
#         }

#         $summary | ConvertTo-Json | Out-File -FilePath (Join-Path $script:OutputCSV "SystemInfoSummary.json")
#         $summary | Export-Csv -Path (Join-Path $script:OutputCSV "SystemInfoSummary.csv") -NoTypeInformation
#         Write-Log "Saved summary files" "Success"
#     } catch {
#         Write-Log "Summary export failed: $($_.Exception.Message)" "Warning"
#         # Continue anyway
#     }

#     Write-ProgressEx -Activity "System Info" -Status "Complete" -PercentComplete 100
#     Write-Progress -Activity "System Info" -Completed

#     # ----- Display -----
#     Write-Host ""
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host "SYSTEM INFORMATION COMPLETE" -ForegroundColor Yellow
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host ""
#     Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor White
#     Write-Host "OS: $($os.Caption) Build $($os.BuildNumber)" -ForegroundColor White
#     Write-Host "CPU: $($cpu[0].Name.Trim()) ($($cpu[0].NumberOfCores) Cores)" -ForegroundColor White
#     Write-Host "RAM: $([math]::Round($totalRAMGB, 0)) GB ($([math]::Round($freeRAM, 0)) GB free)" -ForegroundColor White
#     $gpuDisplay = if ($gpus.Count -gt 0) { $gpus[0].Name.Trim() } else { "None" }
#     Write-Host "GPU: $gpuDisplay" -ForegroundColor White
#     $mbDisplay = "$($motherboard[0].Manufacturer) $($motherboard[0].Product)"
#     Write-Host "Motherboard: $mbDisplay" -ForegroundColor White
#     $diskDisplay = "$($disks[0].Model.Trim()) ($([math]::Round($disks[0].Size / 1GB, 0)) GB)"
#     Write-Host "Disk: $diskDisplay" -ForegroundColor White
#     Write-Host "Uptime: $uptimeDays days" -ForegroundColor White
#     Write-Host ""
#     Write-Host "Output saved to: $script:OutputCSV" -ForegroundColor Green
#     Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
#     Write-Host ""

#     return $true
# }

# Export-ModuleMember -Function Invoke-SystemInfo
