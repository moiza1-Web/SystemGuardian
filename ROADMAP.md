# Roadmap

System Guardian is being developed incrementally with a strong focus on stability, reliability, and maintainability.

The project follows a "build, verify, improve" workflow rather than implementing every feature at once. Every release should leave the project in a usable and stable state.

---

## Current Milestone

### ~~v0.1.0-dev~~ ✔ Complete

The core analysis engine is built and all 8 modules are implemented.

Delivered in this stage:

- Project architecture
- Configuration system
- Logging framework
- Storage analysis
- Drive usage reporting
- Large file detection
- Large folder detection
- Browser cache inventory
- Installed application inventory (`-Applications`)
- Duplicate file detection (`-Duplicates`)
- System information collection (`-SystemInfo`)
- Browser analysis (`-Browser`)
- Smart Review recommendations (`-ReviewAnalyzer`)
- HTML Reports (`-Reports`)
- Interactive Dashboard (`-Dashboard`)
- CSV report generation

The toolkit scans a Windows system safely and produces useful reports without making any changes to the computer.

---

## Previous Milestone

### ~~v0.2~~ ✔ Delivered

With the core engine stable, quality and performance improvements were delivered:

- Better HTML reports
- Faster scan performance (single-pass file enumeration replacing multi-pass)
- Improved logging
- More accurate folder size calculations
- Better progress reporting
- Enhanced error handling

---

## Previous Milestone

### ~~v0.5~~ ✔ Delivered

Usability work delivered:

- Interactive HTML dashboard
- Search and filtering
- Better report navigation
- Improved report summaries
- Cleaner visual design

---

## Current Milestone

### v1.0 — Stabilization & First Public Release

**Status: Complete — All core tasks finished, ready for release tagging.**

Completed work:

- [x] Complete analysis engine (8/8 modules: `-Storage`, `-Duplicates`, `-SystemInfo`, `-Applications`, `-Browser`, `-ReviewAnalyzer`, `-Reports`, `-Dashboard`)
- [x] Interactive dashboard
- [x] Full Pester test coverage for all modules (8/8 test suites)
- [x] Professional documentation (Project Charter, Release Plan, Architecture, Coding Standards, Testing Plan)
- [x] Error handling pass across all modules
- [x] Config validation (all thresholds read from `config.json` via `Config.psm1`)
- [ ] Installer / setup script *(deferred to v1.1)*
- [ ] Versioned GitHub release tag

System Guardian is reliable and ready for regular personal use.

---

## Beyond Version 1.0

Future development may include:

- Native Windows GUI
- Scan history
- Scheduled scans
- Export to PDF
- Plugin support
- Additional reporting modules
- Performance improvements

These ideas will only be implemented if they improve the overall user experience without compromising the project's simplicity.

> [!NOTE]
> **Removed Switches (`-Security` / `-KaliScanner`):** These switches were part of early planning but have been removed since no corresponding modules exist. They are explicitly **not planned** for v1.0. Any future security scanning functionality will be evaluated post-v1.0.

---

## Development Philosophy

System Guardian is intentionally designed as a read-only analysis tool.

The project will never automatically delete, move, rename, or modify user files.

Instead, it provides clear information and recommendations, allowing users to make informed decisions themselves.

Accuracy is preferred over speed.

Maintainability is preferred over unnecessary complexity.

User trust is more important than adding new features.

---

## Project Status

Current Stage:

Stabilization (v1.0 release preparation)

Status:

Ready — Core engine complete (8/8 modules), all tests passing, docs finalized

Target:

Version 1.0

> Roadmaps are living documents.
>
> Priorities may change as the project evolves, but stability and user trust will always take precedence over feature count.