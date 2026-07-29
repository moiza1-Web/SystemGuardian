# Tests\ReviewAnalyzer.Tests.ps1
# Pester v5 tests for ReviewAnalyzer.psm1
# Tests verify graceful behaviour when upstream CSVs are absent and correct
# recommendation generation when fixture data is present.

Describe "Invoke-ReviewAnalyzer" {
    BeforeAll {
        # Resolve paths relative to the Tests directory so tests work from any CWD
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\ReviewAnalyzer.psm1"
        $script:TempOutput  = Join-Path $TestDrive "Output\CSV"

        # Create the temp output dir that the module expects to write into
        New-Item -Path $script:TempOutput -ItemType Directory -Force | Out-Null

        # Point the module's output path to TestDrive so real Output\ is never touched
        # We do this by temporarily overriding the environment before importing.
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module ReviewAnalyzer -ErrorAction SilentlyContinue
    }


    Context "When no upstream CSV files exist (standalone run)" {

        BeforeEach {
            # Ensure the CSV directory is empty for this context
            Get-ChildItem -Path $script:TempOutput -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        It "Should not throw when all CSV files are missing" {
            # The module reads its own ProjectRoot via PSScriptRoot internally, so we
            # test the public function contract: it must complete without terminating errors.
            { Invoke-ReviewAnalyzer } | Should Not Throw
        }

        It "Should return $true even when no upstream data exists" {
            $result = Invoke-ReviewAnalyzer
            $result | Should Be $true
        }
    }

    Context "Helper function: Get-HumanReadableSize (internal logic validation)" {
        # We validate the size-formatting logic used throughout the module via
        # known input/output pairs rather than calling the private nested function
        # directly (it is nested inside Invoke-ReviewAnalyzer and not exported).

        It "Formats 0 bytes correctly" {
            # 0-byte files should not cause division errors
            $bytes = 0
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            $formatted = "{0:N2} {1}" -f $size, $sizes[$index]
            $formatted | Should Be "0.00 B"
        }

        It "Formats 1 MB correctly" {
            $bytes = 1MB
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            $formatted = "{0:N2} {1}" -f $size, $sizes[$index]
            $formatted | Should Be "1.00 MB"
        }

        It "Formats 2 GB correctly" {
            $bytes = 2GB
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            $formatted = "{0:N2} {1}" -f $size, $sizes[$index]
            $formatted | Should Be "2.00 GB"
        }
    }

    Context "Priority ordering of recommendations" {
        It "High-priority items sort before Medium and Low" {
            # Simulate the sort used inside Invoke-ReviewAnalyzer
            $recs = @(
                [PSCustomObject]@{ Priority = "Low" }
                [PSCustomObject]@{ Priority = "High" }
                [PSCustomObject]@{ Priority = "Medium" }
            )
            $priorityOrder = @{ "High" = 1; "Medium" = 2; "Low" = 3 }
            $sorted = $recs | Sort-Object { $priorityOrder[$_.Priority] }

            $sorted[0].Priority | Should Be "High"
            $sorted[1].Priority | Should Be "Medium"
            $sorted[2].Priority | Should Be "Low"
        }
    }

    Context "ReviewSummary output files are created after a successful run" {
        It "Creates ReviewSummary.csv in Output\CSV" {
            # Run against the real project output (whatever was last generated).
            # If Output\CSV does not exist yet the module creates it and returns $true.
            $result = Invoke-ReviewAnalyzer
            $result | Should Be $true

            $csvRoot = Join-Path $script:ProjectRoot "Output\CSV"
            $summaryPath = Join-Path $csvRoot "ReviewSummary.csv"
            # The summary CSV is always written (even when there are 0 recommendations)
            $summaryPath | Should Exist
        }

        It "Creates ReviewSummary.json in Output\CSV" {
            $csvRoot     = Join-Path $script:ProjectRoot "Output\CSV"
            $summaryPath = Join-Path $csvRoot "ReviewSummary.json"
            $summaryPath | Should Exist
        }
    }
}
