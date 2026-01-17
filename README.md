# Unpossible

<p align="center">
  <img src="ralph.png" alt="Ralph Wiggum - That's Unpossible" width="400">
</p>

> "Me fail English? That's unpossible!" - Ralph Wiggum

Run multiple Claude agents (ralphs) in parallel to work through a task list.

## Quick Start

```bash
# 1. Create your PRD file
cp examples/prd.json prd.json

# 2. Create a progress log
cp examples/progress.txt progress.txt

# 3. Create your prompt template
cp examples/prompt.template.md prompt.template.md

# 4. Run 3 ralphs in parallel
./unpossible.sh 3

# 5. Clean up when done
./unpossible.sh clean
```

## How It Works

Unpossible spawns multiple Claude agents (called "ralphs"), each in its own git worktree, working on different tasks simultaneously. Ralphs coordinate through file-based locks to avoid working on the same task.

**Success depends on task quality**: Each task must be atomic (completable independently) and verifiable (clear validation criteria). Well-defined tasks enable effective parallelization.

```text
your-project/
├── prd.json                   # Your task list
├── progress.txt               # Append-only log of completed work (required)
├── prompt.template.md         # Instructions for each ralph
│
├── .unpossible-ralphs/        # Git worktrees (one per ralph)
│   ├── ralph-1/
│   ├── ralph-2/
│   └── ralph-3/
│
└── .unpossible-locks/         # Task locks (prevents duplicates)
    ├── TASK-001/
    └── TASK-002/
```

## Conventions

Unpossible uses a fixed file layout:

- `prd.json`: task list (JSON array)
- `progress.txt`: append-only progress log
- `prompt.template.md`: prompt template

## PRD File

**CRITICAL**: Unpossible's effectiveness depends entirely on task quality. Tasks must be small, atomic, and verifiable.

Your `prd.json` file should be a JSON array. Example:

```json
[
  {
    "id": "TASK-001",
    "title": "Create user schema",
    "description": "Add User table to schema.prisma with id, email, passwordHash, createdAt fields",
    "validation": "Verify schema.prisma contains User model with all 4 fields",
    "done": false,
    "notes": ""
  },
  {
    "id": "TASK-002",
    "title": "Create login API endpoint",
    "description": "Add POST /api/auth/login endpoint that accepts email/password and returns JWT",
    "validation": "Test with curl: curl -X POST http://localhost:3000/api/auth/login -d '{\"email\":\"test@test.com\",\"password\":\"test123\"}' returns token",
    "done": false,
    "notes": ""
  }
]
```

**Field Configuration**: `taskIdField`, `taskCompleteField`, and `taskCompleteValue` are configurable.

**Validation field** (highly recommended): Specify how the ralph should verify completion. Without validation, ralphs may mark incomplete work as done.

## Prompt Template

Create a markdown file with placeholders that get replaced at runtime:

| Placeholder | Value |
|-------------|-------|
| `{{TASK_ID}}` | Current task ID |
| `{{TASK_JSON}}` | Full JSON object of current task |
| `{{VALIDATION_STEPS}}` | Content of `validation` field (or default message if empty) |
| `{{RALPH_DIR}}` | Ralph's worktree path |
| `{{MAIN_DIR}}` | Main worktree path |
| `{{RALPH_BRANCH}}` | Ralph's branch name |
| `{{BASE_BRANCH}}` | Base branch name |

See `examples/prompt.template.md` for a complete example.

## Usage

```bash
# Run N ralphs, each doing up to 10 iterations
./unpossible.sh <N>

# Run N ralphs with custom iteration limit
./unpossible.sh <N> <iterations>

# Stop all ralphs
Ctrl+C

# Clean up worktrees and locks
./unpossible.sh clean
```

## Requirements

- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- `jq` for JSON processing
- `git` for worktree management
- Bash 4+

## Git Workflow

Each ralph works on its own branch and merges back to base:

1. Ralph claims a task (via atomic `mkdir`)
2. Ralph implements the task in its worktree
3. Ralph commits changes
4. Ralph rebases onto latest base branch
5. Ralph merges back (fast-forward)
6. Ralph releases the task lock
7. Repeat with next task

## Known Limitations

**Task Dependencies**: If Task B depends on Task A, a ralph working on Task B might implement both tasks, causing merge conflicts. In practice, ralphs handle these conflicts autonomously during rebase.

**Possible improvements**:

- Add `dependsOn` field to prd.json and check dependencies before claiming
- Enforce strict scope in prompt template to prevent task overstepping

## Inspiration

The concept of spawning multiple AI agents called "ralphs" is inspired by [Geoffrey Huntley's original post](https://ghuntley.com/ralph/) about running parallel AI coding agents.

## License

MIT
