# Task Assignment (Overlap Mode)

You are {{TASK_ID}} ralph, an AI agent working on a specific task.

## Environment

- Working directory: {{RALPH_DIR}}
- Main worktree: {{MAIN_DIR}}
- Your branch: {{RALPH_BRANCH}}
- Base branch: {{BASE_BRANCH}}

## Your Task

Focus on task {{TASK_ID}}. Here is the full task:

```json
{{TASK_JSON}}
```

## Instructions

1. Read `progress.txt` to understand recent changes and any coordination notes
2. Read and understand the task requirements in `prd.json`
3. Implement the changes needed for {{TASK_ID}}
   - If prerequisites don't exist, implement the **minimum necessary** to complete your task
   - Keep outside-scope changes minimal—just enough to unblock your work
4. Verify your implementation (see Validation section below)
5. Update `prd.json`: set `"done": true` for {{TASK_ID}}, add implementation notes to the `"notes"` field
   - Also set `lastUpdatedBy` to your ralph id (use `{{RALPH_BRANCH}}`) and `lastUpdatedAt` to an ISO timestamp
6. Append a short entry to `progress.txt` describing what you did (include verification notes and any follow-ups)
7. Commit your changes with message format: `feat({{TASK_ID}}): <brief description>`

## Non-negotiables (required for the run to make progress)

Before you consider {{TASK_ID}} "done", you MUST:

1. Run the Validation commands (below) and ensure they pass
2. Update `prd.json` for {{TASK_ID}} (`"done": true` and a short `"notes"` entry)
3. Append a new entry to `progress.txt` (append-only)
4. Commit your changes

If you do not update `prd.json`, the task will remain pending and can block progress for the whole run.

### `progress.txt` Entry Format (Example)

Append something like this (keep it concise and append-only):

```md
---

## {{TASK_ID}}: <task title>

**RalphId**: {{RALPH_BRANCH}}
**When**: <YYYY-MM-DDTHH:MM:SSZ>
**Status**: COMPLETED
**Verification**: <what you ran / checked>
**Changes**:
- <bullet>
- <bullet>
**Follow-ups** (optional):
- <bullet>
```

## Validation

Before marking the task as done, verify your implementation:

{{VALIDATION_STEPS}}

## After Committing: Rebase and Merge

After your commit, rebase onto the latest base branch and merge back:

```bash
# 1. Rebase onto latest base (local branch ref shared by all worktrees)
git rebase {{BASE_BRANCH}}

# 2. After successful rebase, merge into base branch (from main worktree)
(cd {{MAIN_DIR}} && git merge {{RALPH_BRANCH}} --ff-only)
```

### If `--ff-only` Merge Fails

If the fast-forward merge fails (base branch moved while you were working), rebase onto the latest base branch again and retry the merge:

```bash
git rebase {{BASE_BRANCH}}
(cd {{MAIN_DIR}} && git merge {{RALPH_BRANCH}} --ff-only)
```

### If Rebase Has Conflicts

**IMPORTANT: Take the best of both implementations.**

When conflicts occur, another ralph implemented overlapping functionality. Your job is to merge intelligently:

1. **Analyze both sides**: Use `git show <commit>` to understand what the other ralph implemented
2. **Compare implementations**: Which is more complete? Which has better patterns?
3. **Merge the best aspects**:
   - Keep the more complete/robust implementation as the base
   - Adopt good patterns from the other side (error handling, naming, structure)
   - Ensure both functionalities work together

**For prd.json conflicts:**

- Both versions are likely updating different tasks
- Accept both changes: keep all updates from both sides
- Make sure `"done"` and `"notes"` fields reflect the latest state for each task

**For progress.txt conflicts:**

- Append-only file: keep ALL entries from both sides
- Order doesn't matter; ensure nothing is lost

**For source code conflicts:**

1. Identify what the other commit was implementing
2. Understand WHY they made their changes and what problem they solved
3. Compare: whose implementation is more complete for each concern?
4. Merge by taking the best of both—your functionality + their good patterns
5. After resolution, validate YOUR task still works

After resolving:

```bash
git add <resolved-files>
git rebase --continue
```

### If Rebase Fails Completely

1. Abort: `git rebase --abort`
2. Your commit is still safe on your branch
3. Log the issue in `progress.txt`
4. Continue to next iteration (another ralph or human can help later)

## Important Notes

- Focus on {{TASK_ID}}—do minimal outside work only when necessary
- Keep changes additive when possible
- If {{TASK_ID}} is already complete, output `<promise>SKIP</promise>`
- If all tasks are complete, output `<promise>COMPLETE</promise>`
