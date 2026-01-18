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

Before you consider {{TASK_ID}} “done”, you MUST:

1. Run the Validation commands (below) and ensure they pass
2. Update `prd.json` for {{TASK_ID}} (`"done": true` and a short `"notes"` entry)
   - Also set `lastUpdatedBy` to `{{RALPH_BRANCH}}` and `lastUpdatedAt` to an ISO timestamp.
3. Append a new entry to `progress.txt` (append-only). Include `RalphId: {{RALPH_BRANCH}}`.
4. Commit your changes with message format: `feat({{TASK_ID}}): <brief description>`

If you do not update `prd.json`, the task will remain pending and can block progress for the whole run.

## `progress.txt` entry format (required)

Append an entry in this structure (even if you SKIP):

```md
---

## {{TASK_ID}}: <task title>

RalphId: {{RALPH_BRANCH}}
When: <YYYY-MM-DDTHH:MM:SSZ>
Status: COMPLETED | SKIPPED
Verification: <what you ran / checked>
Changes:
- <bullet>
```

## Dependencies (`dependsOn`)

If you discover that {{TASK_ID}} depends on another task that is not yet done:

1. Update {{TASK_ID}} in `prd.json` to add `dependsOn: ["TASK-XXX", ...]` and add a short note explaining why.
   - Also set `lastUpdatedBy`/`lastUpdatedAt` when you edit the task object.
2. Append a coordination note to `progress.txt` (include which task you were blocked on).
3. Output `<promise>SKIP</promise>` (so the task can be retried later once dependencies are done).

Important: do NOT implement the dependency work inside {{TASK_ID}}.

## Validation

{{VALIDATION_STEPS}}

## After Committing: Rebase and Merge

```bash
git rebase {{BASE_BRANCH}}
(cd {{MAIN_DIR}} && git merge {{RALPH_BRANCH}} --ff-only)
```
