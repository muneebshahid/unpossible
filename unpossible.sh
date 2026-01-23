#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PRD_FILE="prd.json"
PROMPT_TEMPLATE="prompt.template.md"
UNPOSSIBLE_DIR_NAME=".unpossible"
RALPHS_DIR_NAME="$UNPOSSIBLE_DIR_NAME/ralphs"
LOCKS_DIR_NAME="$UNPOSSIBLE_DIR_NAME/locks"
LOGS_DIR_NAME="$UNPOSSIBLE_DIR_NAME/logs"

# Cleanup function
do_cleanup() {
  echo "Cleaning up..."
  git worktree prune 2>/dev/null || true

  # Remove all ralph worktrees and branches
  for dir in "$RALPHS_DIR"/ralph-*; do
    if [ -d "$dir" ]; then
      ralph_num=$(basename "$dir" | sed 's/ralph-//')
      git worktree remove "$dir" --force 2>/dev/null || true
      git branch -D "ralph-$ralph_num" 2>/dev/null || true
    fi
  done

  rm -rf "$RALPHS_DIR" "$LOCKS_DIR" 2>/dev/null || true
  echo "Cleanup complete"
}

# Show usage
show_usage() {
  echo "Usage: $0 <num_ralphs> [iterations_per_ralph] [model]"
  echo "       $0 clean    # Clean up worktrees and locks"
  echo ""
  echo "  num_ralphs: Number of parallel ralphs to spawn"
  echo "  iterations_per_ralph: Max iterations per ralph (default: 10)"
  echo "  model: Claude model name (optional, e.g. opus/sonnet/haiku)"
}

# Handle cleanup flag
if [ "$1" = "clean" ] || [ "$1" = "--clean" ] || [ "$1" = "-c" ]; then
  MAIN_WORKTREE="$(pwd)"
  RALPHS_DIR="$MAIN_WORKTREE/$RALPHS_DIR_NAME"
  LOCKS_DIR="$MAIN_WORKTREE/$LOCKS_DIR_NAME"
  UNPOSSIBLE_DIR="$MAIN_WORKTREE/$UNPOSSIBLE_DIR_NAME"
  do_cleanup
  rm -rf "$UNPOSSIBLE_DIR" 2>/dev/null || true
  exit 0
fi

if [ -z "$1" ]; then
  show_usage
  exit 1
fi

NUM_RALPHS=$1
ITERATIONS=${2:-10}
CLAUDE_MODEL="${3:-${CLAUDE_MODEL:-}}"
MAIN_WORKTREE="$(pwd)"
RALPHS_DIR="$MAIN_WORKTREE/$RALPHS_DIR_NAME"
LOCKS_DIR="$MAIN_WORKTREE/$LOCKS_DIR_NAME"
LOGS_DIR="$MAIN_WORKTREE/$LOGS_DIR_NAME"

echo ""
echo "=========================================="
echo "  Unpossible - Starting $NUM_RALPHS ralphs"
echo "=========================================="
echo ""

# Determine base branch
BASE_BRANCH="${BASE_BRANCH:-$(git branch --show-current)}"

if [ "$BASE_BRANCH" != "$(git branch --show-current)" ]; then
  echo "Note: Base branch is '$BASE_BRANCH', current branch is '$(git branch --show-current)'"
fi

echo "Base branch: $BASE_BRANCH"
echo "PRD file: $PRD_FILE"
if [ -n "$CLAUDE_MODEL" ]; then
  echo "Claude model: $CLAUDE_MODEL"
fi

# Initialize run logs directory
RUN_STARTED_AT="$(date -u +%Y%m%dT%H%M%SZ)"
BASE_SHA="$(git rev-parse --short "$BASE_BRANCH" 2>/dev/null || git rev-parse --short HEAD)"
SAFE_BRANCH="$(echo "$BASE_BRANCH" | tr '/\\ ' '---' | tr -cd '[:alnum:]._-' )"
RUN_ID="$RUN_STARTED_AT-$SAFE_BRANCH-$BASE_SHA"
RUN_LOG_DIR="$LOGS_DIR/$RUN_ID"

mkdir -p "$RUN_LOG_DIR"
STARTED_AT_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg runId "$RUN_ID" \
  --arg startedAt "$STARTED_AT_ISO" \
  --arg baseBranch "$BASE_BRANCH" \
  --arg baseSha "$BASE_SHA" \
  --arg claudeModel "$CLAUDE_MODEL" \
  --arg mainWorktree "$MAIN_WORKTREE" \
  --arg unpossibleDir "$MAIN_WORKTREE/$UNPOSSIBLE_DIR_NAME" \
  --arg ralphsDir "$RALPHS_DIR" \
  --arg locksDir "$LOCKS_DIR" \
  --arg logsDir "$RUN_LOG_DIR" \
  --argjson numRalphs "$NUM_RALPHS" \
  --argjson iterationsPerRalph "$ITERATIONS" \
  '{
    runId: $runId,
    startedAt: $startedAt,
    endedAt: null,
    baseBranch: $baseBranch,
    baseSha: $baseSha,
    claudeModel: (if $claudeModel == "" then null else $claudeModel end),
    numRalphs: $numRalphs,
    iterationsPerRalph: $iterationsPerRalph,
    paths: {
      mainWorktree: $mainWorktree,
      unpossibleDir: $unpossibleDir,
      ralphsDir: $ralphsDir,
      locksDir: $locksDir,
      logsDir: $logsDir
    }
  }' > "$RUN_LOG_DIR/session.json"

# Validate required files
if [ ! -f "$PRD_FILE" ]; then
  echo "Error: PRD file not found: $PRD_FILE"
  exit 1
fi

if [ ! -f "$PROMPT_TEMPLATE" ]; then
  echo "Error: Prompt template not found: $PROMPT_TEMPLATE"
  exit 1
fi

# Initialize progress file if it doesn't exist (required for multi-ralph runs)
if [ ! -f "progress.txt" ]; then
  echo "# Progress Log" > progress.txt
  echo "" >> progress.txt
  echo "This file is an append-only log of completed work across ralphs." >> progress.txt
  echo "" >> progress.txt
  echo "---" >> progress.txt
  echo "" >> progress.txt
  echo "Note: Created progress.txt. For best results, commit it before running many ralphs to avoid add/add merge conflicts." 1>&2
fi

# Warn if progress.txt exists but isn't tracked (common source of add/add conflicts)
if ! git ls-files --error-unmatch progress.txt >/dev/null 2>&1; then
  echo "Note: progress.txt is not tracked by git. Consider committing it before running many ralphs to avoid add/add merge conflicts." 1>&2
fi

# Clean up locks from previous runs
if [ -d "$LOCKS_DIR" ]; then
  echo "Cleaning up stale locks..."
  rm -rf "$LOCKS_DIR"
fi
mkdir -p "$LOCKS_DIR"

# Show pending count
PENDING_COUNT=$(jq '[.[] | select(.done != true)] | length' "$PRD_FILE" 2>/dev/null || echo "?")
READY_COUNT=$(jq '
  (. as $all
   | reduce $all[] as $t ({}; .[$t.id]=$t) as $m
   | [ $all[]
       | select(.done != true)
       | select(((.dependsOn // []) | all(. as $d | ($m[$d]? | .done) == true)))
     ]
   | length
  )
' "$PRD_FILE" 2>/dev/null || echo "?")
echo "Pending tasks: $PENDING_COUNT (ready: $READY_COUNT)"
echo ""

# Set up worktrees
echo "Setting up worktrees..."

# Clean up any stale worktree references
git worktree prune 2>/dev/null || true

# Remove old worktrees and branches
for dir in "$RALPHS_DIR"/ralph-*; do
  if [ -d "$dir" ]; then
    ralph_num=$(basename "$dir" | sed 's/ralph-//')
    echo "  Removing existing worktree: ralph-$ralph_num"
    git worktree remove "$dir" --force 2>/dev/null || true
    git branch -D "ralph-$ralph_num" 2>/dev/null || true
  fi
done

git worktree prune 2>/dev/null || true
mkdir -p "$RALPHS_DIR"

# Create fresh worktrees
for ((i=1; i<=NUM_RALPHS; i++)); do
  RALPH_DIR="$RALPHS_DIR/ralph-$i"
  BRANCH_NAME="ralph-$i"

  # Clean up branch if it exists
  git branch -D "$BRANCH_NAME" 2>/dev/null || true

  echo "  Creating worktree: ralph-$i (branch: $BRANCH_NAME)"
  git worktree add "$RALPH_DIR" -b "$BRANCH_NAME" "$BASE_BRANCH"

  # Symlink node_modules if it exists
  if [ -d "$MAIN_WORKTREE/node_modules" ]; then
    ln -s "$MAIN_WORKTREE/node_modules" "$RALPH_DIR/node_modules"
  fi

  # Symlink common env files
  [ -f "$MAIN_WORKTREE/.env.local" ] && ln -s "$MAIN_WORKTREE/.env.local" "$RALPH_DIR/.env.local"
  [ -f "$MAIN_WORKTREE/.env" ] && ln -s "$MAIN_WORKTREE/.env" "$RALPH_DIR/.env"
done

echo ""
echo "Launching $NUM_RALPHS ralphs..."
echo ""

# Array to hold ralph PIDs
declare -a RALPH_PIDS

# Trap to clean up ralphs on exit
cleanup() {
  echo ""
  echo "Shutting down ralphs..."
  for pid in "${RALPH_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  echo "Ralphs stopped"
  echo ""
  echo "Worktrees preserved at: $RALPHS_DIR"
  echo "Run '$0 clean' to remove them"
}
trap cleanup EXIT INT TERM

# Launch ralphs
for ((i=1; i<=NUM_RALPHS; i++)); do
  RALPH_ID="ralph-$i"
  RALPH_DIR="$RALPHS_DIR/ralph-$i"

  echo "  Starting ralph $i..."

  MAIN_WORKTREE="$MAIN_WORKTREE" \
  RALPH_DIR="$RALPH_DIR" \
  BASE_BRANCH="$BASE_BRANCH" \
  CLAUDE_MODEL="$CLAUDE_MODEL" \
  PROMPT_TEMPLATE="$PROMPT_TEMPLATE" \
  LOCKS_DIR="$LOCKS_DIR" \
  RUN_LOG_DIR="$RUN_LOG_DIR" \
  OVERLAP_MODE="${OVERLAP_MODE:-0}" \
  "$SCRIPT_DIR/ralph.sh" "$RALPH_ID" "$ITERATIONS" &

  RALPH_PIDS+=($!)
done

echo ""
echo "All ralphs launched. Waiting for completion..."
echo "Press Ctrl+C to stop all ralphs"
echo ""

# Wait for all ralphs to complete
COMPLETED=0
FAILED=0
for pid in "${RALPH_PIDS[@]}"; do
  if wait "$pid"; then
    ((COMPLETED++))
  else
    ((FAILED++))
  fi
done

echo ""
echo "=========================================="
echo "  Session Complete"
echo "  Ralphs completed: $COMPLETED"
echo "  Ralphs failed: $FAILED"
echo "=========================================="

# Mark session ended
jq --arg endedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.endedAt=$endedAt' "$RUN_LOG_DIR/session.json" > "$RUN_LOG_DIR/session.json.tmp" && \
  mv "$RUN_LOG_DIR/session.json.tmp" "$RUN_LOG_DIR/session.json"

# Show branch status
echo ""
echo "Branch status:"
for ((i=1; i<=NUM_RALPHS; i++)); do
  BRANCH_NAME="ralph-$i"
  AHEAD=$(git rev-list --count "$BASE_BRANCH".."$BRANCH_NAME" 2>/dev/null || echo "?")
  echo "  $BRANCH_NAME: $AHEAD commits ahead of $BASE_BRANCH"
done

echo ""
echo "To merge all work:"
echo "  for b in \$(git branch --list 'ralph-*'); do git merge \$b; done"

# macOS notification
osascript -e "display notification \"$COMPLETED ralphs completed, $FAILED failed\" with title \"Unpossible Complete\"" 2>/dev/null || true
