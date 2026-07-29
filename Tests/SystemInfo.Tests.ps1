# Tests\SystemInfo.Tests.ps1
# Pester v5 tests for SystemInfo.psm1
# Tests verify the module loads, exports correctly, and produces expected output
# files; key hardware fields are checked for non-empty values.

Describe "SystemInfo module" {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\SystemInfo.psm1"
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module SystemInfo -ErrorAction SilentlyContinue
    }


    Context "Module structure" {

        It "Exports Invoke-SystemInfo function" {
            Get-Command Invoke-SystemInfo -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "CimInstance availability (prerequisite)" {

        It "Win32_OperatingSystem CIM class is accessible" {
            { Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } | Should Not Throw
        }

        It "Win32_ComputerSystem CIM class is accessible" {
            { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } | Should Not Throw
        }

        It "Win32_Processor CIM class is accessible" {
            { Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop } | Should Not Throw
        }
    }

    Context "Invoke-SystemInfo end-to-end" {

        It "Should not throw during execution" {
            { Invoke-SystemInfo } | Should Not Throw
        }

        It "Should return $true on success" {
            $result = Invoke-SystemInfo
            $result | Should Be $true
        }

        It "Creates SystemInfo.csv in Output\CSV" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfo.csv"
            $csvPath | Should Exist
        }

        It "Creates SystemInfoSummary.json in Output\CSV" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfoSummary.json"
            $jsonPath | Should Exist
        }

        It "SystemInfo.csv contains at least one record" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfo.csv"
            $records = Import-Csv -Path $csvPath
            $records.Count | Should BeGreaterThan 0
        }

        It "SystemInfo.csv has Category, Property, Value columns" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfo.csv"
            $record  = Import-Csv -Path $csvPath | Select-Object -First 1
            $cols    = $record.PSObject.Properties.Name
            ($cols -contains "Category") | Should Be $true
            ($cols -contains "Property") | Should Be $true
            ($cols -contains "Value") | Should Be $true
        }

        It "SystemInfo.csv contains an OS record" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfo.csv"
            $records = Import-Csv -Path $csvPath
            $osRecord = $records | Where-Object { $_.Category -eq "Operating System" }
            $osRecord | Should Not BeNullOrEmpty
        }

        It "SystemInfo.csv contains a CPU record" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfo.csv"
            $records = Import-Csv -Path $csvPath
            $cpuRecord = $records | Where-Object { $_.Category -eq "CPU" }
            $cpuRecord | Should Not BeNullOrEmpty
        }

        It "SystemInfo.csv contains a RAM record" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfo.csv"
            $records = Import-Csv -Path $csvPath
            $ramRecord = $records | Where-Object { $_.Category -eq "RAM" }
            $ramRecord | Should Not BeNullOrEmpty
        }

        It "SystemInfoSummary.json is valid JSON and has ComputerName field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\SystemInfoSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            $obj.ComputerName | Should Not BeNullOrEmpty
        }

        It "Uses only Get-CimInstance (no Get-WmiObject calls)" {
            # Verify the module source does not contain the deprecated API
            $moduleSource = Get-Content $script:ModulePath -Raw
            $moduleSource | Should Not Match "Get-WmiObject"
        }
    }
}
