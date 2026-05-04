# Windows Automation Scripts

A collection of PowerShell and batch scripts for Windows automation, focused on `winget` package management and encrypted backups.

## Scripts

### backup_dirs.bat

Backup subdirectories to encrypted 7-Zip archives.

**Features:**
- Automatically discovers 7-Zip and prompts for installation if missing
- Secure password input (masked)
- Creates individual `.7z` archives for each subdirectory
- Displays directory sizes before backup
- Skips existing archives by default

**Usage:**
```batch
backup_dirs.bat                  # Backup current directory subdirectories
backup_dirs.bat "D:\Data"        # Backup specific directory subdirectories
```

**Requirements:**
- 7-Zip (automatically installed if missing)
- Windows 10+

**Output:**
```
directory_name_YYYYMMDD.7z
```

---

### winget_sync.bat

Synchronise winget packages across PCs using `.wgl` package list files.

**Features:**
- Export installed packages to a file
- Compare current system against a saved package list
- Install packages from a saved package list
- Fixed-width file format for easy version control
- Automatic filename generation for exports

**Usage:**
```batch
winget_sync.bat -c                      # Export packages (auto-generates filename)
winget_sync.bat -c mypackages.wgl       # Export to specific file
winget_sync.bat -d mypackages.wgl       # Compare installed vs. file
winget_sync.bat -i mypackages.wgl       # Install packages from file
winget_sync.bat -h                      # Show help
```

**Options:**
- `-c, --create` — Export installed packages to file
- `-d, --diff` — Compare installed packages against file
- `-i, --install` — Install packages listed in file
- `-h, --help` — Show help

**File Format:**
Fixed-width columns with header and separator line:
```
Name                                  Id                                       Version             Source
---------------------------------------------------------------------------------------------------------------
Arduino IDE 2.3.8                     9NBLGGH4RSD8                             2.3.8               msstore
Git                                   Git.Git                                  2.54.0              winget
```

**Example Workflow:**
```batch
# On source PC: export current packages
winget_sync.bat -c

# Copy the generated .wgl file to target PC

# On target PC: preview what will be installed
winget_sync.bat -d source_packages.wgl

# Install all packages from the file
winget_sync.bat -i source_packages.wgl
```

---

### wg_sync.ps1

PowerShell version of winget sync (pure PowerShell, no BAT wrapper).

**Same functionality as `winget_sync.bat`** but requires PowerShell to run directly.

---

## Getting Started

### Backup Example

```batch
# Create encrypted backup of documents
backup_dirs.bat "C:\Users\YourName\Documents"

# Enter password when prompted (input is masked)
# Archives created: Documents_20260504.7z, Pictures_20260504.7z, etc.
```

### Package Synchronization Example

```batch
# On your main PC
cd \path\to\scripts
winget_sync.bat -c

# This creates: COMPUTERNAME_20260504.wgl

# Copy this file to another PC, then:
winget_sync.bat -i COMPUTERNAME_20260504.wgl

# Review differences first:
winget_sync.bat -d COMPUTERNAME_20260504.wgl
```

## File Formats

### .wgl (Winget List) Format

Fixed-width text format with columns: Name, Id, Version, Source

```
Name                                  Id                                       Version             Source
---------------------------------------------------------------------------------------------------------------
Package Name                          Package.Id                               1.0.0               winget
```

Also supports tab-delimited fallback format:
```
Package.Id	1.0.0	winget
```

---

## Technical Details

### backup_dirs.bat

- Hybrid BAT + PowerShell script
- Uses 7-Zip with `-mx=9 -mhe=on` (maximum compression, header encryption)
- Securely handles passwords via PowerShell `Read-Host -AsSecureString`
- Automatically refreshes PATH after winget installation
- CRLF line endings (Windows batch compatible)

### winget_sync.bat

- Hybrid BAT + PowerShell script
- Exports via `winget export` (JSON format)
- Compares package IDs between systems
- Display names sourced from `winget list` output
- Supports all winget sources (msstore, winget, etc.)
- Interactive file selection if no filename provided

---

## Author

Daniel Komárek, Claude (Anthropic)

## Version

- **backup_dirs.bat** — 1.0 (2026-05-04)
- **winget_sync.bat** — 1.0 (2026-05-04)
- **wg_sync.ps1** — 1.0 (2026-04-26)

## License

Use freely for personal and commercial purposes.
