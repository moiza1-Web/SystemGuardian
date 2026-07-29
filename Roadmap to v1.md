# System Guardian — Roadmap to v1.0 (Verified State)

> This roadmap reflects the ACTUAL code state as of the last repo review — not the
> conflicting claims in README.md / ROADMAP.md / Summary. All 8 core modules
> (Storage, Duplicates, SystemInfo, Applications, Browser, ReviewAnalyzer,
> Reports, Dashboard) are implemented. Run.ps1 wiring has been fixed so all 8
> are reachable via CLI. What remains is stabilization, not feature-building.

**Current real status: ~70-75% to v1.0.**

---

## Phase A — Stabilization (do this first)

Goal: prove every module actually works end-to-end, not just that it compiles.

- [ ] Run `.\Run.ps1 -All` on a real Windows machine, confirm all 8 modules
      complete without error and produce their CSV/JSON output
- [ ] Fix the remaining `Get-WmiObject` call in `Storage.psm1`'s drive-usage
      section (missed during the Phase 1 performance pass — replace with
      `Get-CimInstance` for consistency with the rest of the codebase)
- [ ] Add Pester tests for the 4 modules that currently have none:
      `ReviewAnalyzer.psm1`, `Applications.psm1`, `SystemInfo.psm1`, `Browser.psm1`
      (Storage, Duplicates, Reports, Dashboard already have tests)
- [ ] Verify `ReviewAnalyzer` behaves correctly when run standalone (i.e. when
      `Output\CSV\LargeFiles.csv` etc. don't exist yet) — it should skip
      gracefully, not error

## Phase B — Documentation Reconciliation

Goal: one true story, told the same way in every file.

- [ ] Decide the single canonical status line (suggested: "Core engine complete,
      stabilizing for v1.0 release")
- [ ] Update `README.md` — remove "Coming Soon" labels on Duplicates/
      SystemInfo/Browser/Applications, since they're done
- [ ] Update `Summary` doc — stop claiming "GitHub Release: Ready to publish"
      until Phase A is actually complete
- [ ] Update `ROADMAP.md` — move current milestone marker from v0.1.0-dev to
      reflect that v0.2 and v0.5 milestones are functionally complete
- [ ] Make sure the `-ReviewAnalyzer` and `-Applications` switches are
      documented as available (not "coming soon") in every doc

## Phase C — Final Polish

- [ ] Config validation: confirm every threshold used in code actually reads
      from `config.json` (per your existing rule — no hardcoded values)
- [ ] Error handling pass: confirm every module fails gracefully if a
      dependency CSV/file is missing (not just ReviewAnalyzer)
- [ ] Decide the fate of the removed `-Security` / `-KaliScanner` switches —
      either scope them into a real future module in ROADMAP.md, or drop the
      idea entirely so nothing references them

## Phase D — v1.0 Packaging

- [ ] Update `CHANGELOG.md` with everything since last version
- [ ] Tag a real `v1.0.0` release on GitHub
- [ ] Write install/usage instructions matching the corrected `Run.ps1` switches
- [ ] (Optional, can slip to v1.1) Basic installer/setup script

---

## Explicitly NOT in scope for v1.0

- WPF GUI (v2.0, per existing ROADMAP.md)
- AI-powered insights (v3.0, per existing ROADMAP.md)
- Any Security/KaliScanner functionality (no module exists yet — don't
  document it as available until it's built)