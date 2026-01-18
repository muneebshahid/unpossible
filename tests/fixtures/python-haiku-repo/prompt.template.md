# Task Assignment

You are {{TASK_ID}} ralph, an AI agent working on a specific task.

## Environment

- Working directory: {{RALPH_DIR}}
- Main worktree: {{MAIN_DIR}}
- Your branch: {{RALPH_BRANCH}}
- Base branch: {{BASE_BRANCH}}

## Your Task

Work ONLY on task {{TASK_ID}}.

```json
{{TASK_JSON}}
```

## Non-negotiables (required for the run to make progress)

1. Run the Validation commands (below) and ensure they pass.
2. Update `prd.json`: set `"done": true` for {{TASK_ID}} and add a short implementation note in `"notes"`.
3. Append a short entry to `progress.txt` (append-only).
4. Commit your changes with message format: `feat({{TASK_ID}}): <brief description>`.

If you do not update `prd.json`, the task will remain pending and can block progress for the whole run.

## Validation

{{VALIDATION_STEPS}}

## After Committing: Rebase and Merge

```bash
git rebase {{BASE_BRANCH}}
(cd {{MAIN_DIR}} && git merge {{RALPH_BRANCH}} --ff-only)
```
