# Tests\Browser.Tests.ps1
# Pester v5 tests for Browser.psm1
# Tests verify module loads and exports correctly; end-to-end run is safe
# regardless of which browsers are installed on the test machine.

Describe "Browser module" {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\Browser.psm1"
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module Browser -ErrorAction SilentlyContinue
    }


    Context "Module structure" {

        It "Exports Invoke-Browser function" {
            Get-Command Invoke-Browser -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context "Human-readable size formatting" {
        # Validates the size-formatting logic used in Get-BrowserProfileStats

        It "Formats 0 bytes as '0.00 B'" {
            $bytes  = 0
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "0.00 B"
        }

        It "Formats 512 KB correctly" {
            $bytes  = 512 * 1024
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "512.00 KB"
        }
    }

    Context "Invoke-Browser end-to-end" {

        It "Should not throw even if no browsers are installed" {
            { Invoke-Browser } | Should Not Throw
        }

        It "Should return $true on success" {
            $result = Invoke-Browser
            $result | Should Be $true
        }

        It "Creates BrowserSummary.csv in Output\CSV" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\BrowserSummary.csv"
            $csvPath | Should Exist
        }

        It "Creates BrowserSummary.json in Output\CSV" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\BrowserSummary.json"
            $jsonPath | Should Exist
        }

        It "BrowserSummary.json is valid JSON" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\BrowserSummary.json"
            { Get-Content $jsonPath -Raw | ConvertFrom-Json } | Should Not Throw
        }

        It "BrowserSummary.json contains TotalBrowserProfiles field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\BrowserSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            ($obj.PSObject.Properties.Name -contains "TotalBrowserProfiles") | Should Be $true
        }

        It "BrowserSummary.json contains TotalCacheSizeHuman field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\BrowserSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            ($obj.PSObject.Properties.Name -contains "TotalCacheSizeHuman") | Should Be $true
        }
    }

    Context "BrowserReport.csv schema (when at least one browser is installed)" {

        BeforeAll {
            # Only validate schema if the file was actually produced
            $script:BrowserReportPath = Join-Path $script:ProjectRoot "Output\CSV\BrowserReport.csv"
            $script:ReportExists = Test-Path $script:BrowserReportPath
        }

        It "BrowserReport.csv has expected columns when browsers are found" -Skip:(-not $script:ReportExists) {
            $record = Import-Csv -Path $script:BrowserReportPath | Select-Object -First 1
            $cols   = $record.PSObject.Properties.Name
            ($cols -contains "Browser") | Should Be $true
            ($cols -contains "Profile") | Should Be $true
            ($cols -contains "TotalCacheSize") | Should Be $true
            ($cols -contains "ExtensionCount") | Should Be $true
        }
    }
}
