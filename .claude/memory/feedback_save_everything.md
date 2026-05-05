---
name: "ulož vše" trigger
description: Czech phrase "ulož vše" means: snapshot memory + project status + other relevant info to md files in the repo, then commit and push to GitHub main. Triggered when user is about to switch dev machines.
type: feedback
---

When the user says **"ulož vše"** (or close variants like "uložit všechno", "save everything"):

1. Persist any new memories from this session into `.claude/memory/*.md` (and update `MEMORY.md` index).
2. Refresh `.claude/STATUS.md` with a handoff snapshot — current branch/commit, what was just done, open items, anything in flight (uncommitted edits, half-finished work).
3. Stage all relevant changes, commit, and `git push` to `origin/master` (or the active main branch).
4. Confirm with one line: what was saved, the commit hash, push result.

**Why:** The user develops on two PCs (home + work). The home-directory `~\.claude\` does not sync. Everything needed to resume work on the other machine has to live in the repo and be pushed before they relocate.

**How to apply:** Treat "ulož vše" as a complete workflow, not a question. Don't ask for confirmation on the push — that's the explicit point of the phrase. Do still warn if there are dirty/unexpected files you haven't seen before in case they shouldn't be committed.
