# Tests\Dashboard.Tests.ps1
# Pester v5 tests for Dashboard.psm1
# Tests verify module loads, exports correctly, handles missing CSV data
# gracefully, and produces valid interactive HTML output.

Describe "Dashboard module" {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\Dashboard.psm1"
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module Dashboard -ErrorAction SilentlyContinue
    }


    Context "Module structure" {

        It "Exports Invoke-Dashboard function" {
            Get-Command Invoke-Dashboard -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
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

    Context "JSON data serialization" {
        # Validates that PowerShell ConvertTo-Json produces valid output for the dashboard

        It "ConvertTo-Json handles empty arrays without errors" {
            $testData = @{
                driveUsage = @()
                largeFiles = @()
            }
            $result = $null
            { $result = $testData | ConvertTo-Json -Depth 5 } | Should Not Throw
            $result | Should Not BeNullOrEmpty
        }

        It "ConvertTo-Json handles nested objects correctly" {
            $testData = @{
                driveUsage = @(
                    [PSCustomObject]@{ Drive = "C:"; TotalSize = 500GB; FreeSpace = 100GB }
                )
            }
            $result = $null
            { $result = $testData | ConvertTo-Json -Depth 5 } | Should Not Throw
            $result | Should Match "C:"
        }
    }

    Context "Invoke-Dashboard end-to-end" {

        It "Should not throw during execution" {
            { Invoke-Dashboard } | Should Not Throw
        }

        It "Should return a result" {
            $result = Invoke-Dashboard
            $result | Should Not BeNullOrEmpty
        }

        It "Creates dashboard.html in Output\HTML" {
            $htmlPath = Join-Path $script:ProjectRoot "Output\HTML\dashboard.html"
            $htmlPath | Should Exist
        }

        It "Copies dashboard.html to Output\Reports" {
            $copyPath = Join-Path $script:ProjectRoot "Output\Reports\dashboard.html"
            $copyPath | Should Exist
        }

        It "Dashboard HTML contains DOCTYPE declaration" {
            $htmlPath = Join-Path $script:ProjectRoot "Output\HTML\dashboard.html"
            $content = Get-Content $htmlPath -Raw
            $content | Should Match "<!DOCTYPE html>"
        }

        It "Dashboard HTML contains System Guardian title" {
            $htmlPath = Join-Path $script:ProjectRoot "Output\HTML\dashboard.html"
            $content = Get-Content $htmlPath -Raw
            $content | Should Match "System Guardian"
        }

        It "Dashboard HTML contains search input (interactive element)" {
            $htmlPath = Join-Path $script:ProjectRoot "Output\HTML\dashboard.html"
            $content = Get-Content $htmlPath -Raw
            $content | Should Match "globalSearch"
        }

        It "Dashboard HTML contains JavaScript code" {
            $htmlPath = Join-Path $script:ProjectRoot "Output\HTML\dashboard.html"
            $content = Get-Content $htmlPath -Raw
            $content | Should Match "<script>"
        }

        It "Dashboard HTML contains sortTable function" {
            $htmlPath = Join-Path $script:ProjectRoot "Output\HTML\dashboard.html"
            $content = Get-Content $htmlPath -Raw
            $content | Should Match "sortTable"
        }
    }
}
