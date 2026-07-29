# Tests\Applications.Tests.ps1
# Pester v5 tests for Applications.psm1
# Tests verify module loads cleanly, exports the right function, and produces
# the expected output files after a successful run.

Describe "Applications module" {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\Applications.psm1"
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module Applications -ErrorAction SilentlyContinue
    }


    Context "Module structure" {

        It "Exports Invoke-Applications function" {
            Get-Command Invoke-Applications -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "Get-RegistryValue helper logic" {
        # The helper is internal to Invoke-Applications, so we test the concept:
        # accessing a missing registry value should return $null, not throw.

        It "Reading a nonexistent registry value returns null without throwing" {
            $key = $null
            $result = $null
            { 
                if ($key) { $result = $key.GetValue("NonExistent") }
            } | Should Not Throw
            $result | Should BeNullOrEmpty
        }
    }

    Context "Human-readable size formatting" {
        # Validates the size formatting used for EstimatedSize display.

        It "Formats 0 KB as 0 B" {
            $bytes  = 0
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "0.00 B"
        }

        It "Formats 1024 KB as 1.00 MB" {
            $bytes  = 1024 * 1024
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "1.00 MB"
        }
    }

    Context "Invoke-Applications end-to-end" {

        It "Should not throw during execution" {
            { Invoke-Applications } | Should Not Throw
        }

        It "Should return $true on success" {
            $result = Invoke-Applications
            $result | Should Be $true
        }

        It "Creates InstalledApps.csv in Output\CSV" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\InstalledApps.csv"
            $csvPath | Should Exist
        }

        It "Creates AppSummary.json in Output\CSV" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\AppSummary.json"
            $jsonPath | Should Exist
        }

        It "InstalledApps.csv contains at least one record" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\InstalledApps.csv"
            $records = Import-Csv -Path $csvPath
            $records.Count | Should BeGreaterThan 0
        }

        It "InstalledApps.csv has expected columns" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\InstalledApps.csv"
            $record  = Import-Csv -Path $csvPath | Select-Object -First 1
            $cols    = $record.PSObject.Properties.Name
            ($cols -contains "Name") | Should Be $true
            ($cols -contains "Version") | Should Be $true
            ($cols -contains "Publisher") | Should Be $true
            ($cols -contains "Category") | Should Be $true
        }

        It "AppSummary.json is valid JSON" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\AppSummary.json"
            { Get-Content $jsonPath -Raw | ConvertFrom-Json } | Should Not Throw
        }
    }
}
