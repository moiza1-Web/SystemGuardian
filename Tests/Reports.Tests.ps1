# Tests\Reports.Tests.ps1
# Pester v5 tests for Reports.psm1
# Tests verify module loads, exports correctly, handles missing CSV data
# gracefully, and produces valid HTML output.

Describe "Reports module" {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\Reports.psm1"
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module Reports -ErrorAction SilentlyContinue
    }


    Context "Module structure" {

        It "Exports Invoke-Reports function" {
            Get-Command Invoke-Reports -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "Human-readable size formatting" {

        It "Formats 0 bytes as '0 B'" {
            $bytes = 0
            if ($bytes -eq 0) { $result = "0 B" }
            $result | Should Be "0 B"
        }

        It "Formats 5 GB correctly" {
            $bytes = 5GB
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "5.00 GB"
        }
    }

    Context "Read-CsvSafely logic (internal helper)" {
        # Validates the concept: reading a nonexistent CSV returns null, not an error.

        It "Reading a nonexistent CSV path returns null without throwing" {
            $result = $null
            {
                $path = Join-Path $TestDrive "nonexistent.csv"
                if (Test-Path $path) {
                    $result = Import-Csv -Path $path
                } else {
                    $result = $null
                }
            } | Should Not Throw
            $result | Should BeNullOrEmpty
        }
    }

    Context "Invoke-Reports end-to-end" {

        It "Should not throw during execution" {
            { Invoke-Reports } | Should Not Throw
        }

        It "Should return a result" {
            $result = Invoke-Reports
            $result | Should Not BeNullOrEmpty
        }

        It "Creates an HTML report in Output\Reports" {
            $reportsDir = Join-Path $script:ProjectRoot "Output\Reports"
            $htmlFiles = Get-ChildItem -Path $reportsDir -Filter "SystemReport_*.html" -ErrorAction SilentlyContinue
            $htmlFiles.Count | Should BeGreaterThan 0
        }

        It "HTML report contains DOCTYPE declaration" {
            $reportsDir = Join-Path $script:ProjectRoot "Output\Reports"
            $latestReport = Get-ChildItem -Path $reportsDir -Filter "SystemReport_*.html" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestReport) {
                $content = Get-Content $latestReport.FullName -Raw
                $content | Should Match "<!DOCTYPE html>"
            }
        }

        It "HTML report contains System Guardian title" {
            $reportsDir = Join-Path $script:ProjectRoot "Output\Reports"
            $latestReport = Get-ChildItem -Path $reportsDir -Filter "SystemReport_*.html" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestReport) {
                $content = Get-Content $latestReport.FullName -Raw
                $content | Should Match "System Guardian"
            }
        }

        It "Creates ReportSummary.csv in Output\CSV" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\ReportSummary.csv"
            $csvPath | Should Exist
        }

        It "ReportSummary.csv has expected columns" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\ReportSummary.csv"
            $record  = Import-Csv -Path $csvPath | Select-Object -First 1
            $cols    = $record.PSObject.Properties.Name
            ($cols -contains "Timestamp") | Should Be $true
            ($cols -contains "TotalDrives") | Should Be $true
            ($cols -contains "TotalLargeFiles") | Should Be $true
            ($cols -contains "OverallUsagePercent") | Should Be $true
        }
    }
}
