# 🛡️ System Guardian

> **Know Your System. Optimize Smarter.**

Ever looked at your C: drive and thought, *"Where did all my space go?"* 

You're not alone. Most of us have random ISOs, old node_modules folders, or browser caches eating up gigabytes without us knowing.

**System Guardian** is my attempt to fix that. It's a professional, read-only Windows analysis toolkit that helps you understand exactly what's on your PC — without touching a single file.

---

## ✨ What Can It Do? (The Good Stuff)

I built this because I was tired of guessing. Here's what it tells you:

### 📊 Storage Analysis (The Core)
- **Drive Usage**: See exactly how full your drives are at a glance.
- **Large Files & Folders**: Finds the usual suspects >10MB and >100MB.
- **Downloads Analysis**: We all have that "Download" folder from 2019. Let's size it up.
- **Temp & Cache**: Shows you how much space Windows and your browsers are hoarding.
- **Empty Folders**: Cleans up the visual clutter (without deleting anything!).
- **Recycle Bin**: Tells you how much "deleted" data is still taking up space.

### 🔍 Duplicate File Detection
Uses **SHA-256** hashing to find exact copies. Optimized to compare file sizes first so it doesn't take forever.

### 💻 System & App Inventory
- Full hardware spec list (CPU, GPU, RAM, Motherboard).
- Every installed application, its version, publisher, and install date.
- Startup programs that slow down your boot.

### 🌐 Browser Analysis
Supports **Chrome**, **Edge**, **Firefox**, and **Brave**. Shows extensions, cache size, and profile data.

### 💡 Smart Review Recommendations (The Unique Part)
I'm not building an antivirus. I'm building a *butler*.

Instead of saying *"Malware detected"* (boring), System Guardian says:
- *"Hey, you've got a 48 GB Windows 11 ISO in your Downloads. Do you still need it?"*
- *"Your Chrome cache is 9 GB. Review recommended."*
- *"node_modules folder is 24 GB. Might want to clean that up."*

It just flags things for **Review Recommended** so *you* decide what stays.

---

## 🔒 The Safety Promise (Read this first)

This tool is designed to be **completely safe**. 

I promise you: **It will never delete, move, rename, or modify anything** on your system. No registry edits. No internet calls. No data uploads. It just reads metadata and writes reports to your `Output` folder. 

You are always in control.

---

## 🗂️ Project Structure

I like keeping things clean:
SystemGuardian/
├── Run.ps1 # The main engine
├── Modules/ # All the brains (Storage, Duplicates, etc.)
├── Config/ # Your settings
├── Assets/ # CSS/JS for the dashboard
├── Output/ # Where all reports live (CSV, HTML, JSON)
├── Logs/ # Debug logs (if you need them)
├── Tests/ # Pester tests (for the nerds)
└── Docs/ # Full documentation

text

---

## 🚀 Getting Started (It's Simple)

1. Make sure you're on **Windows 10/11** with **PowerShell 5.1**.
2. Clone this repo or download the files.
3. Open PowerShell as Administrator (recommended for scanning all drives).
4. Run:

```powershell
.\Run.ps1 -Storage
```

Sit back, grab a coffee, and let it scan. When it's done, check the `Output\CSV` folder for your reports.

## 📈 What's Next? (The Roadmap)

**Current status:** Core engine complete (8/8 modules working), currently stabilizing for v1.0 release — testing and docs in progress.

All 8 analysis modules are implemented and functional:
`-Storage`, `-Duplicates`, `-SystemInfo`, `-Applications`, `-Browser`, `-ReviewAnalyzer`, `-Reports`, `-Dashboard`

Upcoming milestones:

- **v1.0** *(you are here — stabilization phase)*: Pester test coverage, documentation reconciliation, error handling pass, GitHub release tag.
- **v2.0**: A proper WPF GUI so you don't have to touch the terminal.
- **v3.0**: AI-powered insights and a plugin system.

Check the full [ROADMAP.md](ROADMAP.md) for details.

🤝 Wanna Help?
If you're a developer or just someone who loves clean Windows tools, I'd love your help!

Found a bug? Open an Issue.

Have a feature idea? Let's discuss it.

Want to contribute code? Fork it and submit a Pull Request.

📜 License
This is open-source under the MIT License. Use it, modify it, learn from it — just be cool about it.

⭐ Support the Project
If this tool saves you from buying a new hard drive or just makes you feel more in control of your PC, please consider giving this repo a ⭐ on GitHub.

It really helps me stay motivated to build v2.0!

👨‍💻 A Note from the Author
Hi, I'm Moiz Ahmed.

I built System Guardian out of my own frustration with messy drives and bloated "cleaner" apps that break things. I wanted something that shows me the problem rather than fixing it automatically.

I hope this tool helps you understand your PC as much as it helped me build it.