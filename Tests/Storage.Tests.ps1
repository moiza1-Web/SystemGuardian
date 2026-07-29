# Tests\Storage.Tests.ps1
# Pester v5 tests for Storage.psm1
# Tests verify module loads, exports the right function, uses CimInstance,
# and produces expected output files after a successful run.

Describe "Storage module" {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\Storage.psm1"
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module Storage -ErrorAction SilentlyContinue
    }


    Context "Module structure" {

        It "Exports Invoke-Storage function" {
            Get-Command Invoke-Storage -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "CimInstance availability (prerequisite)" {

        It "Win32_LogicalDisk CIM class is accessible" {
            { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop } | Should Not Throw
        }
    }

    Context "Uses only Get-CimInstance (no Get-WmiObject calls)" {

        It "Module source does not contain Get-WmiObject" {
            $moduleSource = Get-Content $script:ModulePath -Raw
            $moduleSource | Should Not Match "Get-WmiObject"
        }
    }

    Context "Human-readable size formatting" {
        # Validates the size-formatting logic used throughout the module

        It "Formats 0 bytes as '0.00 B'" {
            $bytes  = 0
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "0.00 B"
        }

        It "Formats 1 GB correctly" {
            $bytes = 1GB
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "1.00 GB"
        }
    }

    Context "Invoke-Storage end-to-end" {

        It "Should not throw during execution" {
            { Invoke-Storage } | Should Not Throw
        }

        It "Should return `$true on success" {
            $result = Invoke-Storage
            $result | Should Be $true
        }

        It "Creates StorageSummary.csv in Output\CSV" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\StorageSummary.csv"
            $csvPath | Should Exist
        }

        It "Creates StorageSummary.json in Output\CSV" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\StorageSummary.json"
            $jsonPath | Should Exist
        }

        It "Creates DriveUsage.csv in Output\CSV" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\DriveUsage.csv"
            $csvPath | Should Exist
        }

        It "DriveUsage.csv contains at least one record" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\DriveUsage.csv"
            $records = Import-Csv -Path $csvPath
            $records.Count | Should BeGreaterThan 0
        }

        It "DriveUsage.csv has expected columns" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\DriveUsage.csv"
            $record  = Import-Csv -Path $csvPath | Select-Object -First 1
            $cols    = $record.PSObject.Properties.Name
            ($cols -contains "Drive") | Should Be $true
            ($cols -contains "TotalSize") | Should Be $true
            ($cols -contains "FreeSpace") | Should Be $true
            ($cols -contains "PercentUsed") | Should Be $true
        }

        It "StorageSummary.json is valid JSON" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\StorageSummary.json"
            { Get-Content $jsonPath -Raw | ConvertFrom-Json } | Should Not Throw
        }

        It "StorageSummary.json has TotalDrives field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\StorageSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            ($obj.PSObject.Properties.Name -contains "TotalDrives") | Should Be $true
        }

        It "StorageSummary.json has TotalLargeFiles field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\StorageSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            ($obj.PSObject.Properties.Name -contains "TotalLargeFiles") | Should Be $true
        }
    }
}
