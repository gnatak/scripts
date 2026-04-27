PowerShell script for synchronisation of packages installed using winget across different PCs.

## Functionality
- Exports list of installed packages to a `.wgl` file
- Compares currently installed packages against a saved file
- Installs packages listed in a file

## File Format
Fixed-width columns with header and separator row, matching the visual style of `winget list`. Extension: `.wgl`.

Columns:
1. **Name** — display name
2. **Id** — winget package identifier (used for install and comparison)
3. **Version** — installed version
4. **Source** — winget source (e.g. `winget`, `msstore`)

Example:
```
Name                          Id                       Version    Source
------------------------------------------------------------------------
Git                           Git.Git                  2.54.0     winget
Visual Studio Code            Microsoft.VisualStudioCode 1.88.0   winget
```

## Parameters
```
wg_sync [parameters] [filename]
```

| Parameter | Description |
|---|---|
| `-c`, `--create` | Export currently installed packages to `filename`. If `filename` is omitted, auto-generates `COMPUTERNAME_YYYYMMDD.wgl` in the current directory. |
| `-d`, `--diff` | Compare currently installed packages against `filename`. If `filename` is omitted, shows a picker of `.wgl` files in the script directory. |
| `-i`, `--install` | Install packages listed in `filename`. Shows list and asks for confirmation before installing. If `filename` is omitted, shows a picker. |
| `-h`, `--help` | Show help. |

## Implementation Notes
- Package IDs and versions are obtained via `winget export --include-versions` (reliable, no truncation).
- Display names are obtained by parsing `winget list` output and matched to IDs.
- Packages without a winget source (ARP registry entries, MSIX system packages) are excluded.
- Comparison and installation always use the **Id** column, not the display name.
