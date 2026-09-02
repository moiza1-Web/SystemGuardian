# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-09-02

### Added
- **`Setup.ps1` Installer & Environment Verification**:
  - One-time setup script verifying system prerequisites (PowerShell 5.1+, Windows 10/11).
  - Automatically creates required output folders (`Output\CSV`, `Output\HTML`, `Output\Reports`, `Logs`).
  - Validates `Config\config.json` syntax and confirms presence of all 5 Core shared modules.
  - Interactive/Silent options (`-NoShortcut`, `-Silent`) and optional creation of Desktop shortcut (`System Guardian.lnk`).

## [1.1.0] - 2026-08-01

### Added
- **Core Shared Modules Fully Wired**: All 8 feature modules (`Storage`, `Duplicates`, `SystemInfo`, `Applications`, `Browser`, `ReviewAnalyzer`, `Reports`, `Dashboard`) now use the 5 shared Core modules (`Logger.psm1`, `Formatter.psm1`, `Progress.psm1`, `Config.psm1`, `Utils.psm1`) instead of duplicating logging, formatting, progress, config, and CSV logic locally.
- **`Initialize-ModulePaths` (Utils.psm1)**: Standardized path setup (`ModuleDir`, `ProjectRoot`, `OutputCSV`, `OutputReports`, `OutputHTML`, `ConfigPath`) across all modules.
- **`Read-CsvSafely` (Utils.psm1)**: Shared safe CSV-reading helper used by `Reports.psm1` and `Dashboard.psm1`.

### Fixed
- **Cross-Module Scope Bug**: `Initialize-ModulePaths` fixed to return a hashtable of paths so caller modules populate their own `$script:` scope reliably.
- **UTF-8 BOM Encoding**: Re-saved module source files with UTF-8 BOM encoding to fix emoji/special character display in HTML dashboards.
- **`Reports.psm1` / `Dashboard.psm1` Early-Exit**: Preserved directory safety checks before output folder initialization.

### Security & Data Privacy
- **Personal Data Removal**: Thoroughly sanitized git history and repository tracking to ensure no local system file paths, personal usernames, or scan result files are tracked or exposed.
- **Release Tag Realignment**: Aligned `v1.0.0` release tag to sanitized commit history.

## [1.0.0] - 2026-07-24

### Added
- **Full Pester Test Coverage**: Completed comprehensive Pester v5 tests for all 8 core modules (8/8 test suites):
  - `Tests/Storage.Tests.ps1`: Validates module structure, CIM prerequisites, WmiObject absence, size formatting, end-to-end execution, DriveUsage CSV schema, and StorageSummary JSON output.
  - `Tests/Duplicates.Tests.ps1`: Validates module structure, CIM checks, streaming SHA256 hash consistency, size formatting, end-to-end execution, and DuplicateSummary JSON schema.
  - `Tests/Reports.Tests.ps1`: Validates module structure, safe CSV reading, size formatting, HTML report generation, DOCTYPE/title checks, and ReportSummary CSV schema.
  - `Tests/Dashboard.Tests.ps1`: Validates module structure, JSON serialization, end-to-end execution, interactive HTML elements (search, sort, JavaScript), and file copy to Reports.
  - `Tests/ReviewAnalyzer.Tests.ps1`: Validates standalone runs (graceful skips), priority ordering, size formatting, and output file generation.
  - `Tests/Applications.Tests.ps1`: Validates registry safe-reading, size calculations, and output integrity.
  - `Tests/SystemInfo.Tests.ps1`: Validates CIM-only collection (absence of `Get-WmiObject`), property presence, and output file schemas.
  - `Tests/Browser.Tests.ps1`: Validates multi-browser data handling, safe behavior when no browsers are installed, and schema validations.
- **Config-driven Duplicate Finder**: Added support for configuring the minimum file size limit for duplicates via a new `DuplicateMinFileMB` setting under `DuplicateAnalysis` in `config.json`.
- **Project Charter**: Created `Docs/Project-Charter.md` defining the project goals, scope boundaries, and core development principles.
- **Release Plan**: Created `Docs/Release-Plan.md` outlining the verification checklist and steps required for the `v1.0.0` stable release.

### Changed
- **CIM Migration (Final Pass)**: Replaced the final remaining legacy `Get-WmiObject` calls with `Get-CimInstance` in both `Storage.psm1` (drive usage section) and `Duplicates.psm1` (logical disk check) to optimize query performance and ensure full compatibility with PowerShell Core (PS6+).
- **Storage.psm1 Cleanup**: Removed ~540 lines of commented-out dead code (pre-refactor backup from the Core modules migration). Active code unchanged.
- **Documentation Reconciliation**:
  - Reconciled `README.md` and `ROADMAP.md` to reflect the actual functional state of the 8 core modules.
  - Removed obsolete "Coming Soon" labels from Duplicates, SystemInfo, Browser, and Applications features.
  - Re-mapped ROADMAP milestone markers: v0.1.0-dev, v0.2, and v0.5 are now marked as completed/delivered.
  - Established a single canonical status line across documents.
  - Updated Release Plan checklist — all verification items checked off.
  - ROADMAP v1.0 milestone updated to reflect completion.

### Removed
- **Unplanned CLI Switches**: Clarified the removal of unused legacy `-Security` and `-KaliScanner` switches. Documented their fate in `ROADMAP.md` as explicitly unplanned for the v1.0.0 scope.
- **Dead Code**: Removed 540+ lines of commented-out backup code from `Storage.psm1`.
