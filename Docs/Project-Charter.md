# Project Charter: System Guardian

System Guardian is a lightweight, read-only Windows analysis toolkit designed to help users understand, analyze, and optimize their storage and system configurations without modifying any system state or user files.

---

## 🎯 Project Goal

To provide a safe, non-destructive, and high-performance toolkit that scans Windows systems and generates comprehensive reports. It enables users to make informed optimization decisions manually rather than delegating automated cleanup to third-party software.

---

## ⚙️ Scope Boundary

### In Scope
- **Read-Only Inspection**: Enumerating drives, directories, files, registry entries, and CIM instances.
- **8 Core Modules**:
  1. **Storage**: Analyzes drive space, temp folders, caches, recycle bin, large files/folders.
  2. **Duplicates**: Fast, memory-safe SHA256-based duplicate file identification.
  3. **SystemInfo**: Basic hardware and operating system profile aggregation.
  4. **Applications**: Scans installed applications, versions, and startup items.
  5. **Browser**: Scans user profiles, extensions, and caches for popular browsers (Chrome, Edge, Firefox, Brave).
  6. **ReviewAnalyzer**: Aggregates module outputs and provides warning recommendations.
  7. **Reports**: Compiles the CSV records into a static HTML report.
  8. **Dashboard**: Generates an interactive search/filterable HTML dashboard.
- **Safety Guarantee**: Ensuring zero writes outside of logs and the `Output/` directory.

### Out of Scope
- **Automated Deletion/Cleanup**: The toolkit will never delete, rename, or modify any files or registry settings.
- **Antivirus/Anti-Malware**: System Guardian is not a security scanning tool and does not inspect files for malicious signatures.
- **External Network Traffic**: No telemetry, API calls, or database reporting is performed; all data remains local.
- **Active System Optimization**: No tweaking of registry settings, disabling services, or altering system files.

---

## 🛡️ Core Principles

1. **User Trust is Paramount**: The tool must never do anything unexpected. It should never touch or modify the host system state.
2. **Performance & Efficiency**: Use streaming operations and memory-safe structures (e.g. streaming hashes for duplicates and Generic Lists to avoid array reallocation overhead).
3. **Transparency**: All logic must remain auditable; reports should present raw metrics clearly without obscured "scores" or hidden telemetry.
4. **Accuracy Over Speed**: Scanning must rely on verified filesystem properties and reliable OS metadata queries (`Get-CimInstance`).
