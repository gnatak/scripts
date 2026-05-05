# Session handoff status

> Point-in-time snapshot. Frozen — for current state always re-check `git log` and the working tree.

**Last session:** 2026-05-05
**Branch:** master
**Tip commit (will be one ahead after this snapshot's own commit):** `3e43cd3 Save session handoff snapshot and "ulož vše" trigger memory`
**Working tree at snapshot time:** clean.

## What was done in the previous session

1. Created `CLAUDE.md` documenting the hybrid BAT+PowerShell architecture, marker rule, CRLF requirement, embedded-script test trick, and `.wgl` format.
2. Set up Claude Code orchestration in the repo (so it travels via git instead of the non-syncing home directory):
   - `.claude/agents/script-editor.md` (sonnet) — for edits to the `.bat` scripts
   - `.claude/agents/test-runner.md` (haiku) — for Pester v3
   - `.claude/memory/` — project-local memory, replaces `~\.claude\projects\...\memory\`
3. Narrowed `.gitignore` from `.claude/` → `.claude/settings.local.json`; un-ignored `CLAUDE.md`.
4. Committed and pushed pre-existing feature work: `-e`/`--exclude` flag, interactive numbered exclusion, `bd.bat` / `ws.bat` aliases.
5. Installed the four `.bat` files to `c:\Apps\` (the user's PATH dir). Smoke-tested `-v` on each — all reported `0.1`.
6. Saved the **"ulož vše"** trigger as a feedback memory (see `.claude/memory/feedback_save_everything.md`).
7. Verified the trigger end-to-end: user invoked "ulož vše" once after the memory was written, and it correctly refreshed STATUS, committed, and pushed.

## Open items / next likely tasks

- None tracked. Repo is at a clean release boundary (v0.1 still current).
- If a v0.2 lands, remember to bump `$Script:Version` in **both** `.bat` files and update the corresponding black-box test assertions (`backup_dirs 0\.1` → new version).

## Conventions to remember on resume

- **Orchestrator-first:** delegate `.bat` edits to the `script-editor` subagent and Pester runs to `test-runner`. Don't edit the embedded PS section directly unless it's a one-liner.
- **Marker:** the literal `#== POWERSHELL SCRIPT BELOW ==#` must remain unique per file; the loader uses `LastIndexOf`.
- **Pester v3 only** (`Should Be`, no hyphen) — the bundled PS 5.1 Pester.
- **Czech UI language**, but English in code, comments, and commit messages.
- **Memory writes** go to `<repo>\.claude\memory\`, never to `~\.claude\projects\...\memory\`.

## Installed targets outside the repo

- `c:\Apps\backup_dirs.bat`, `winget_sync.bat`, `bd.bat`, `ws.bat` — copies of repo files; re-run install (just `cp` the four `.bat` files to `c:\Apps\`) after any change you want available system-wide.
