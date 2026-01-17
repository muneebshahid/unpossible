# How Unpossible Works

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         unpossible.sh                           │
│                        (Orchestrator)                           │
│                                                                 │
│  1. Loads config from unpossible.config.json                    │
│  2. Creates git worktrees for each ralph                        │
│  3. Spawns ralph.sh processes in parallel                       │
│  4. Waits for completion                                        │
└─────────────────────────────────────────────────────────────────┘
         │              │              │
         ▼              ▼              ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  ralph-1/   │ │  ralph-2/   │ │  ralph-3/   │
│ (worktree)  │ │ (worktree)  │ │ (worktree)  │
│             │ │             │ │             │
│ ralph.sh    │ │ ralph.sh    │ │ ralph.sh    │
│     ↓       │ │     ↓       │ │     ↓       │
│  Claude     │ │  Claude     │ │  Claude     │
└─────────────┘ └─────────────┘ └─────────────┘
         │              │              │
         └──────────────┼──────────────┘
                        ▼
              ┌─────────────────┐
              │ .unpossible-    │
              │   locks/        │
              │                 │
              │ TASK-001/       │
              │ TASK-002/       │
              └─────────────────┘
```

## Task Claiming (Race-Condition Free)

Ralphs use **atomic directory creation** to claim tasks:

```bash
# Ralph tries to claim TASK-001
mkdir .unpossible-locks/TASK-001

# If mkdir succeeds → Ralph claimed it (first one wins)
# If mkdir fails    → Another ralph already claimed it, try next task
```

This is race-condition-free because `mkdir` is atomic on Unix systems.

## Work Cycle

Each ralph loops through:

```text
┌─────────────────────────────────────────────────────────┐
│  1. Read tasks.json, find pending tasks                 │
│  2. Try to claim via mkdir (skip if already claimed)    │
│  3. Load prompt template, replace placeholders          │
│  4. Run Claude with the prompt                          │
│  5. Claude implements the task                          │
│  6. Claude commits to ralph's branch                    │
│  7. Claude rebases onto base branch                     │
│  8. Claude merges into base (--ff-only from main tree)  │
│  9. Release lock (mark completed)                       │
│ 10. Repeat until no pending tasks                       │
└─────────────────────────────────────────────────────────┘
```

## Git Workflow

Each ralph: commit → rebase → ff-merge

```text
Ralph 1:
  1. commit B on ralph-1 branch
  2. rebase onto base (A)
  3. ff-merge: base moves A → B

Ralph 2 (after ralph-1 merged):
  1. commit C on ralph-2 branch
  2. rebase onto base (now B)
  3. ff-merge: base moves B → C

Result: base = A → B → C (linear history)
```

The rebase puts the ralph's commit on top of latest base, then `--ff-only` advances the base pointer.

## Conflict Resolution

### Why Conflicts Happen

Multiple ralphs modify files simultaneously:

- **tasks.json**: Every ralph updates task status
- **Source files**: Occasionally, if tasks touch related code

### Resolution Strategy

#### tasks.json Conflicts (Easy)

Both ralphs are updating different tasks. Resolution:

- Keep ALL task updates from both sides
- Both ralphs marking different tasks as complete? Keep both.

#### Source Code Conflicts (Requires Context)

Before blindly resolving, the ralph should:

1. **Find the conflicting commit**:

   ```bash
   git log --oneline $BASE_BRANCH ^HEAD~1 -- <conflicted-file>
   ```

2. **Identify which task the other ralph was implementing**

3. **Understand their intent**:

   ```bash
   git show <commit-hash>  # See full diff and message
   ```

4. **Resolve with full context**:
   - Keep both functionalities working
   - Don't blindly accept one side
   - If changes are complementary, merge them thoughtfully

5. **If stuck**:
   - Abort rebase: `git rebase --abort`
   - Log the issue
   - Move on (human or another ralph can help later)

## File Structure

```text
your-project/
├── unpossible.config.json         # Configuration
├── tasks.json                     # Task list
├── prompt.template.md             # Instructions for ralphs
│
├── .unpossible-ralphs/            # Git worktrees
│   ├── ralph-1/                   # Branch: ralph-1
│   │   ├── src/
│   │   ├── tasks.json             # Ralph's copy (diverges as work happens)
│   │   └── node_modules → ../..   # Symlink to main repo
│   ├── ralph-2/                   # Branch: ralph-2
│   └── ralph-3/                   # Branch: ralph-3
│
└── .unpossible-locks/             # Task locks (shared across all ralphs)
    ├── TASK-001/
    │   ├── ralph.json             # Who claimed it
    │   ├── output.log             # Full Claude output
    │   └── completed.json         # Completion timestamp
    └── TASK-002/
        └── ...
```

## Logs

| Location | Contents |
|----------|----------|
| `.unpossible-locks/TASK-XXX/output.log` | Full Claude output for that task |
| `.unpossible-locks/TASK-XXX/ralph.json` | Who claimed it, when |
| `/tmp/claude/unpossible-logs/` | Raw JSON stream output |

## After Completion

The orchestrator shows branch status:

```text
Branch status:
  ralph-1: 3 commits ahead of main
  ralph-2: 2 commits ahead of main
  ralph-3: 1 commits ahead of main

To merge all work:
  for b in $(git branch --list 'ralph-*'); do git merge $b; done
```

## Manual Merge

If ralphs couldn't resolve all conflicts during rebase:

```bash
# Merge each branch manually
git merge ralph-1
# Resolve any conflicts
git merge ralph-2
# ...

# Or cherry-pick specific commits
git cherry-pick <commit-hash>
```

## Cleanup

```bash
# Use built-in cleanup
./unpossible.sh clean

# Or manually:
git worktree list | grep ralph- | awk '{print $1}' | xargs -I {} git worktree remove {} --force
git branch -D ralph-1 ralph-2 ralph-3
rm -rf .unpossible-ralphs .unpossible-locks
```

## Limitations

- **No resumption**: If you stop, must restart from scratch (locks cleared)
- **Local only**: Doesn't push to remote (by design - review first)
- **Single machine**: No distributed coordination (uses local filesystem locks)
