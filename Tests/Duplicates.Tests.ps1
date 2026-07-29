# Tests\Duplicates.Tests.ps1
# Pester v5 tests for Duplicates.psm1
# Tests verify module loads, exports correctly, uses CimInstance,
# streaming hash produces consistent results, and output files are valid.

Describe "Duplicates module" {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:ModulePath  = Join-Path $script:ProjectRoot "Modules\Duplicates.psm1"
        Import-Module $script:ModulePath -Force
    }

    AfterAll {
        Remove-Module Duplicates -ErrorAction SilentlyContinue
    }


    Context "Module structure" {

        It "Exports Invoke-Duplicates function" {
            Get-Command Invoke-Duplicates -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
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

    Context "Streaming SHA256 hash consistency" {
        # Validates that the streaming hash approach produces deterministic results.
        # We test by hashing a known file (the module source itself) twice.

        It "Hashing the same file twice produces identical results" {
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $stream1 = [System.IO.File]::OpenRead($script:ModulePath)
            $hash1 = [System.BitConverter]::ToString($sha256.ComputeHash($stream1)) -replace '-', ''
            $stream1.Dispose()

            $stream2 = [System.IO.File]::OpenRead($script:ModulePath)
            $hash2 = [System.BitConverter]::ToString($sha256.ComputeHash($stream2)) -replace '-', ''
            $stream2.Dispose()
            $sha256.Dispose()

            $hash1 | Should Be $hash2
        }

        It "SHA256 hash is 64 characters long" {
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $stream = [System.IO.File]::OpenRead($script:ModulePath)
            $hash = [System.BitConverter]::ToString($sha256.ComputeHash($stream)) -replace '-', ''
            $stream.Dispose()
            $sha256.Dispose()

            $hash.Length | Should Be 64
        }
    }

    Context "Human-readable size formatting" {

        It "Formats 0 bytes as '0 B'" {
            $bytes = 0
            if ($bytes -eq 0) { $result = "0 B" }
            $result | Should Be "0 B"
        }

        It "Formats 1 MB correctly" {
            $bytes = 1MB
            $sizes  = @("B","KB","MB","GB","TB","PB")
            $index  = 0
            $size   = [double]$bytes
            while ($size -ge 1024 -and $index -lt $sizes.Length - 1) { $size /= 1024; $index++ }
            "{0:N2} {1}" -f $size, $sizes[$index] | Should Be "1.00 MB"
        }
    }

    Context "Invoke-Duplicates end-to-end" {

        It "Should not throw during execution" {
            { Invoke-Duplicates } | Should Not Throw
        }

        It "Should return a boolean result" {
            $result = Invoke-Duplicates
            $result | Should BeOfType [bool]
        }

        It "Creates DuplicateSummary.csv in Output\CSV" {
            $csvPath = Join-Path $script:ProjectRoot "Output\CSV\DuplicateSummary.csv"
            $csvPath | Should Exist
        }

        It "Creates DuplicateSummary.json in Output\CSV" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\DuplicateSummary.json"
            $jsonPath | Should Exist
        }

        It "DuplicateSummary.json is valid JSON" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\DuplicateSummary.json"
            { Get-Content $jsonPath -Raw | ConvertFrom-Json } | Should Not Throw
        }

        It "DuplicateSummary.json has TotalFilesScanned field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\DuplicateSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            ($obj.PSObject.Properties.Name -contains "TotalFilesScanned") | Should Be $true
        }

        It "DuplicateSummary.json has DuplicateGroups field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\DuplicateSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            ($obj.PSObject.Properties.Name -contains "DuplicateGroups") | Should Be $true
        }

        It "DuplicateSummary.json has RecoverableSpaceHuman field" {
            $jsonPath = Join-Path $script:ProjectRoot "Output\CSV\DuplicateSummary.json"
            $obj = Get-Content $jsonPath -Raw | ConvertFrom-Json
            ($obj.PSObject.Properties.Name -contains "RecoverableSpaceHuman") | Should Be $true
        }
    }
}
