# Unpossible

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="ralph.png" alt="Ralph Wiggum - That's Unpossible" width="400">
</p>
<!-- markdownlint-enable MD033 -->

> "Me fail English? That's unpossible!" - Ralph Wiggum

Unpossible runs multiple Claude agents (ralphs) in parallel to work through a task list. Each ralph works in its own git worktree, coordinating via atomic filesystem locks.

A minimal experimental agent orchestration tool—use at your own risk.

**Success depends on two factors:**

1. **Minimal task overlap** — Tasks that touch different files/areas parallelize well. Overlapping tasks cause merge conflicts that slow everything down.
2. **Verifiable validation** — Each task needs clear validation criteria. Without this, ralphs may mark incomplete work as done.

## Quick Start

```bash
# 1. Set up required files
cp examples/prd.json prd.json
cp examples/progress.txt progress.txt
cp examples/prompt.template.md prompt.template.md

# 2. Run 3 ralphs in parallel
./unpossible.sh 3

# 3. Clean up when done
./unpossible.sh clean
```

## How It Works

```text
your-project/
├── prd.json               # Task list (JSON array) - required
├── progress.txt           # Append-only completion log - required
├── prompt.template.md     # Instructions for each ralph - required
│
└── .unpossible/           # Runtime directory (auto-created)
    ├── ralphs/            # Git worktrees (ralph-1/, ralph-2/, ...)
    ├── locks/             # Task locks (cleared on restart)
    └── logs/              # Per-run logs (persist across restarts)
```

**Git workflow per task:**

1. Ralph claims task via atomic `mkdir` lock
2. Implements task in its worktree
3. Commits changes
4. Rebases onto latest base branch
5. Fast-forward merges back to base
6. Releases lock and repeats

**Conflict handling:** Ralphs resolve merge conflicts autonomously during rebase, considering the other ralph's commit context.

## PRD File

Tasks must be **atomic** (completable independently) and **verifiable** (clear validation criteria).

```json
[
  {
    "id": "TASK-001",
    "title": "Create user schema",
    "description": "Add User table with id, email, passwordHash, createdAt fields",
    "validation": "Verify schema.prisma contains User model with all 4 fields",
    "done": false,
    "dependsOn": []
  },
  {
    "id": "TASK-002",
    "title": "Create login endpoint",
    "description": "Add POST /api/auth/login returning JWT",
    "validation": "curl -X POST localhost:3000/api/auth/login returns token",
    "done": false,
    "dependsOn": ["TASK-001"]
  }
]
```

**Required fields:** `id`, `done` (boolean)

**Recommended fields:**

- `validation`: How to verify completion—without this, ralphs may mark incomplete work as done
- `dependsOn`: Array of task IDs that must complete first (ralphs only claim tasks with all dependencies met)

## Prompt Template

Placeholders replaced at runtime:

| Placeholder | Value |
| -------------------- | -------------------------------- |
| `{{TASK_ID}}` | Current task ID |
| `{{TASK_JSON}}` | Full task object as JSON |
| `{{VALIDATION_STEPS}}` | Content of `validation` field |
| `{{RALPH_DIR}}` | Ralph's worktree path |
| `{{MAIN_DIR}}` | Main worktree path |
| `{{RALPH_BRANCH}}` | Ralph's branch name |
| `{{BASE_BRANCH}}` | Base branch name |

See `examples/prompt.template.md` for a complete example.

## Usage

```bash
./unpossible.sh <N>                      # Run N ralphs (default 10 iterations each)
./unpossible.sh <N> <iterations>         # Custom iteration limit
./unpossible.sh <N> <iterations> <model> # Specify Claude model (e.g., haiku)
./unpossible.sh clean                    # Remove worktrees and locks

WAIT_SECONDS=60 ./unpossible.sh 3        # Custom wait time when blocked
```

## Testing

```bash
# Create test repo with independent tasks
./tests/create-sandbox-repo.sh /tmp/unp --force
cd /tmp/unp && ./unpossible.sh 2 10 haiku

# Create test repo with task dependencies
./tests/create-sandbox-repo.sh /tmp/unp --force --fixture python-haiku-deps-repo
```

## Requirements

- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- `jq` for JSON processing
- `git` for worktree management
- Bash 4+

## Design Notes

- **`prd.json` is the source of truth**: Tasks are only "done" when `prd.json` is updated
- **Blocked ≠ done**: When tasks exist but none are claimable, ralphs wait and retry
- **Signals**: `<promise>SKIP</promise>` skips current task, `<promise>COMPLETE</promise>` exits ralph
- **Audit trail**: Include `lastUpdatedBy`/`lastUpdatedAt` in tasks and `RalphId` in progress.txt

## Inspiration

The concept of parallel AI agents called "ralphs" is inspired by [Geoffrey Huntley's original post](https://ghuntley.com/ralph/).

## License

MIT
