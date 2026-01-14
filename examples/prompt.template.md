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
4. Update the tasks file: set `"done": true` for {{TASK_ID}}, add implementation notes to the `"notes"` field
5. Commit your changes with message format: `feat({{TASK_ID}}): <brief description>`

## Validation

Before marking the task as done, verify your implementation:

{{VALIDATION_STEPS}}

## After Committing: Rebase and Merge

After your commit, rebase onto the latest base branch and merge back:

```bash
# 1. Rebase onto latest base
git fetch origin {{BASE_BRANCH}}
git rebase origin/{{BASE_BRANCH}}

# 2. After successful rebase, merge into base branch (from main worktree)
(cd {{MAIN_DIR}} && git merge {{RALPH_BRANCH}} --ff-only)
```

### If Rebase Has Conflicts

**For tasks.json conflicts:**

- Both versions are likely updating different tasks
- Accept both changes: keep all updates from both sides
- Make sure `"done"` and `"notes"` fields reflect the latest state for each task

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
3. Continue to next iteration (another ralph or human can help later)

## Important Notes

- ONLY work on {{TASK_ID}} - do not work on other tasks
- Keep changes additive when possible
- If {{TASK_ID}} is already complete or blocked, output `<promise>SKIP</promise>`
- If all tasks are complete, output `<promise>COMPLETE</promise>`
