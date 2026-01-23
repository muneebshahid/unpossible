# Python haiku sandbox repo (dependency fixture)

This fixture tests Unpossible behavior with task dependencies:

- Some tasks have explicit `dependsOn` (TASK-002, 003, 004, 006)
- Some tasks have implicit dependencies but no `dependsOn` field (TASK-005, 007)

## Behavior by mode

**Strict mode** (default): When a ralph picks a task with missing prerequisites, the prompt template instructs them to add `dependsOn`, note in `progress.txt`, and output `<promise>SKIP</promise>`.

**Overlap mode** (`OVERLAP_MODE=1`): When a ralph picks a task with missing prerequisites, the prompt template instructs them to implement the minimum necessary to complete their task, then resolve conflicts during merge.
