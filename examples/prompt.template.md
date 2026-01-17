# Task Assignment

You are {{TASK_ID}} ralph, an AI agent working on a specific task.

## Environment

- Working directory: {{RALPH_DIR}}
- Main worktree: {{MAIN_DIR}}
- Your branch: {{RALPH_BRANCH}}
- Base branch: {{BASE_BRANCH}}

## Your Task

Work ONLY on task {{TASK_ID}}. Here is the full task:

```json
{{TASK_JSON}}
```

## Instructions

1. Read and understand the task requirements
2. Implement the changes needed
3. Verify your implementation (see Validation section below)
4. Update `prd.json`: set `"done": true` for {{TASK_ID}}, add implementation notes to the `"notes"` field
5. Append a short entry to `progress.txt` describing what you did (include verification notes and any follow-ups)
6. Commit your changes with message format: `feat({{TASK_ID}}): <brief description>`

### `progress.txt` Entry Format (Example)

Append something like this (adapt as needed, keep it concise and append-only):

```md
---

## {{TASK_ID}}: <task title>

**Ralph**: {{RALPH_BRANCH}}
**When**: <YYYY-MM-DDTHH:MM:SSZ>
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

**For prd.json conflicts:**

- Both versions are likely updating different tasks
- Accept both changes: keep all updates from both sides
- Make sure `"done"` and `"notes"` fields reflect the latest state for each task

**For progress.txt conflicts:**

- Append-only file: keep ALL entries from both sides
- Order doesn’t matter; ensure nothing is lost

**For source code conflicts:**

1. Identify what the other commit was implementing
2. Understand WHY they made their changes
3. Keep both functionalities working
4. Don't blindly accept one side

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

- ONLY work on {{TASK_ID}} - do not work on other tasks
- Keep changes additive when possible
- If {{TASK_ID}} is already complete or blocked, output `<promise>SKIP</promise>`
- If all tasks are complete, output `<promise>COMPLETE</promise>`
