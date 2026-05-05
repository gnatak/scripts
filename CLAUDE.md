# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Two standalone Windows automation utilities — `backup_dirs.bat` (encrypted 7z backups of subdirectories) and `winget_sync.bat` (export/diff/install winget package lists in a `.wgl` fixed-width file format). `bd.bat` and `ws.bat` are thin forwarders to the long-named scripts.

## Hybrid BAT + PowerShell architecture

Both `backup_dirs.bat` and `winget_sync.bat` are single-file hybrids. The top of each file is a short BAT shim; the rest is PowerShell embedded after a literal marker line:

```
#== POWERSHELL SCRIPT BELOW ==#
```

The BAT shim:
1. Sets `BAT_SELF=%~f0` and `BAT_ARGS=%*` (env vars are how args reach PowerShell — the BAT-side parser is intentionally minimal).
2. Calls `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ...` which re-reads the file, splits at `LastIndexOf($marker)`, and `& ([scriptblock]::Create($script))`s the tail.

Implications when editing:
- **Never break the marker.** It must remain exactly `#== POWERSHELL SCRIPT BELOW ==#` and appear only once meaningfully (the loader uses `LastIndexOf`). Tests rely on the same marker.
- **The embedded section is parsed at runtime as a string**, not as a `.ps1` file — `$PSScriptRoot` is empty there, and you cannot dot-source it. Any helpers must live inline or be re-derived from `$env:BAT_SELF`.
- **Args are re-parsed inside PowerShell** from `$env:BAT_ARGS` using a regex that handles quoted segments: `'"([^"]*)"|(\S+)'`. Adding a new flag means editing the `switch -Exact` block in the embedded script, not the BAT shim.
- **CRLF line endings are required** for the BAT portion to work on Windows. Keep the whole file CRLF.
- **Version metadata** lives in `$Script:Version` / `$Script:Author` near the top of the embedded section in each script. The two scripts version independently; bump both only if the change is cross-cutting. The black-box tests assert the version string (`backup_dirs 0\.1`), so update tests when bumping.

## Tests (Pester)

Tests live next to each script as `*.Tests.ps1`. They use the **same marker trick** to load the embedded PowerShell:

1. Read the `.bat` file, find the marker, take the substring after it.
2. AST-parse it with `[System.Management.Automation.Language.Parser]::ParseInput`.
3. `Invoke-Expression` each `FunctionDefinitionAst` to materialise the helpers (`Format-Bytes`, `Read-PackageFile`, `Find-7Zip`, etc.) into the test scope without executing the top-level script body.

This means **only top-level `function` definitions are testable** — code at script scope (the main `try { ... }` block, arg parsing) is not lifted into the test session and must be exercised via the black-box `& $batPath -v` style tests at the bottom of each test file.

Run tests:

```powershell
# All tests in the repo
Invoke-Pester -Path .

# A single file
Invoke-Pester -Path .\backup_dirs.Tests.ps1

# A single Describe block
Invoke-Pester -Path .\backup_dirs.Tests.ps1 -TestName 'Format-Bytes'
```

The tests use the legacy Pester v3 `Should Be` syntax (no hyphen), so they run on Windows PowerShell 5.1's bundled Pester without installing v5.

## .wgl file format

Fixed-width text with a header row, a separator row of dashes, and data rows. Column starts are detected by `IndexOf('Name'|'Id'|'Version'|'Source')` on the header line — never reformat by replacing the header with different column labels or shrinking columns below the longest value, or `Read-PackageFile` will mis-slice rows. A tab-delimited fallback (`id<TAB>version<TAB>source`) is also accepted on read but never produced by `-c`.

## Common ad-hoc runs

```batch
backup_dirs.bat "D:\Data" -e node_modules,.git
winget_sync.bat -c                              # writes COMPUTERNAME_YYYYMMDD.wgl
winget_sync.bat -d packages.wgl
backup_dirs.bat -v                              # version flag, useful smoke test
```

## Orchestration: prefer subagents

The user develops on two machines (home + work) and the home-directory `~\.claude\` does not sync. **Everything project-relevant lives under the repo's `.claude/` directory** so it travels with git.

When a task fits one of these subagents, delegate via the Agent tool instead of doing the work yourself:

| Agent | Model | Use for |
|-------|-------|---------|
| `script-editor` | sonnet | Any edit to `backup_dirs.bat`, `winget_sync.bat`, `bd.bat`, `ws.bat`, or the embedded PowerShell helpers. Knows the marker / CRLF / arg-passing pitfalls. |
| `test-runner` | haiku | Running Pester, interpreting failures, adding `Describe`/`It` blocks in v3 style. |

For broad codebase exploration use the built-in `Explore` agent — don't roll your own.

The orchestrator (top-level Claude) stays interactive: takes the user's intent, dispatches subagents, and reports back. Avoid doing the agents' work directly unless the task is one or two lines.

## Project-local memory

Memory for this project lives in **`.claude/memory/` inside the repo**, not in `~\.claude\projects\...\memory\`. The home-directory location is per-machine and does not sync across the user's two PCs.

When the auto-memory system would write to the home location, write to `<repo>\.claude\memory\` instead. The index file is `<repo>\.claude\memory\MEMORY.md`. Same format as the standard memory system (one file per memory, one-line pointer in the index).

## .gitignore

Only `.claude/settings.local.json`, `.obsidian/`, and `*.wgl` are ignored. `.claude/agents/`, `.claude/memory/`, and `CLAUDE.md` are versioned so they sync between machines.
