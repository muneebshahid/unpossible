#!/bin/bash
set -e

RALPH_ID=${1:-"ralph-$$"}
MAX_ITERATIONS=${2:-10}

# Directories - set by orchestrator or use defaults
MAIN_WORKTREE=${MAIN_WORKTREE:-"$(pwd)"}
RALPH_DIR=${RALPH_DIR:-"$(pwd)"}
BASE_BRANCH=${BASE_BRANCH:-"main"}
LOCKS_DIR=${LOCKS_DIR:-"$MAIN_WORKTREE/.unpossible/locks"}
RUN_LOG_DIR=${RUN_LOG_DIR:-"$MAIN_WORKTREE/.unpossible/logs/manual"}

PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-prompt.template.md}"
PRD_FILE="prd.json"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"

log() {
  echo "[$RALPH_ID] $1"
}

# Try to claim a task by creating its lock directory (atomic via mkdir)
claim_task() {
  local task_id=$1
  local task_dir="$LOCKS_DIR/$task_id"

  if mkdir "$task_dir" 2>/dev/null; then
    echo "{\"ralphId\": \"$RALPH_ID\", \"pid\": $$, \"startedAt\": \"$(date -Iseconds)\"}" > "$task_dir/ralph.json"
    return 0
  else
    return 1
  fi
}

# Release a task lock
release_task() {
  local task_id=$1
  local task_dir="$LOCKS_DIR/$task_id"
  echo "{\"completedAt\": \"$(date -Iseconds)\"}" > "$task_dir/completed.json"
}

# Find next available pending task from tasks file (in ralph's worktree)
find_pending_task() {
  local tasks_file="$RALPH_DIR/$PRD_FILE"

  if [ ! -f "$tasks_file" ]; then
    echo ""
    return
  fi

  # Get all pending task IDs
  local pending_ids
  pending_ids=$(jq -r '.[] | select(.done != true) | .id' "$tasks_file" 2>/dev/null || echo "")

  for task_id in $pending_ids; do
    if claim_task "$task_id"; then
      echo "$task_id"
      return
    fi
  done

  echo ""
}

# Get full task JSON by ID
get_task_json() {
  local task_id=$1
  local tasks_file="$RALPH_DIR/$PRD_FILE"
  jq -c ".[] | select(.id == \"$task_id\")" "$tasks_file" 2>/dev/null || echo "{}"
}

# Build prompt from template
build_prompt() {
  local task_id=$1
  local task_json=$2
  local ralph_branch=$3

  local template_file="$MAIN_WORKTREE/$PROMPT_TEMPLATE"

  if [ ! -f "$template_file" ]; then
    log "Error: Prompt template not found: $template_file"
    exit 1
  fi

  local prompt
  prompt=$(cat "$template_file")

  # Extract validation steps from task JSON (if present)
  local validation_steps
  validation_steps=$(echo "$task_json" | jq -r '.validation // empty' 2>/dev/null)
  if [ -z "$validation_steps" ] || [ "$validation_steps" = "null" ]; then
    validation_steps="(No specific validation steps defined for this task)"
  fi

  # Replace placeholders
  prompt="${prompt//\{\{TASK_ID\}\}/$task_id}"
  prompt="${prompt//\{\{RALPH_DIR\}\}/$RALPH_DIR}"
  prompt="${prompt//\{\{MAIN_DIR\}\}/$MAIN_WORKTREE}"
  prompt="${prompt//\{\{RALPH_BRANCH\}\}/$ralph_branch}"
  prompt="${prompt//\{\{BASE_BRANCH\}\}/$BASE_BRANCH}"
  prompt="${prompt//\{\{VALIDATION_STEPS\}\}/$validation_steps}"

  # TASK_JSON is a single-line JSON string (via `jq -c`), safe for direct replacement
  prompt="${prompt//\{\{TASK_JSON\}\}/$task_json}"

  echo "$prompt"
}

log "Starting in worktree: $RALPH_DIR"
log "Base branch: $BASE_BRANCH, max iterations: $MAX_ITERATIONS"

# Change to ralph directory
cd "$RALPH_DIR"

for ((iter=1; iter<=MAX_ITERATIONS; iter++)); do
  log "Iteration $iter: Looking for work..."

  # Sync with base branch to get latest task file status.
  log "Syncing with $BASE_BRANCH..."
  git merge --ff-only "$BASE_BRANCH" 2>/dev/null || true

  # Find and claim a pending task
  TASK_ID=$(find_pending_task)

  if [ -z "$TASK_ID" ]; then
    log "No pending tasks available. Exiting."
    break
  fi

  log "Claimed task: $TASK_ID"

  # Set up logging for this task
  TASK_LOG_DIR="$RUN_LOG_DIR/$TASK_ID"
  TASK_LOG="$TASK_LOG_DIR/output.log"
  TASK_STREAM_JSONL="$TASK_LOG_DIR/stream.jsonl"
  mkdir -p "$TASK_LOG_DIR"

  # Persist claim metadata in logs
  cp "$LOCKS_DIR/$TASK_ID/ralph.json" "$TASK_LOG_DIR/ralph.json" 2>/dev/null || true

  # Get current branch name
  RALPH_BRANCH=$(git branch --show-current)

  # Get task JSON
  TASK_JSON=$(get_task_json "$TASK_ID")

  # Build the prompt
  PROMPT=$(build_prompt "$TASK_ID" "$TASK_JSON" "$RALPH_BRANCH")

  log "Running Claude on $TASK_ID..."

  # Run Claude in the ralph directory
  claude_args=(--output-format stream-json --verbose --dangerously-skip-permissions)
  if [ -n "$CLAUDE_MODEL" ]; then
    claude_args+=(--model "$CLAUDE_MODEL")
  fi

  set +e
  claude "${claude_args[@]}" -p "$PROMPT" 2>&1 | \
    tee "$TASK_STREAM_JSONL" | \
    tee -a "$TASK_LOG" | \
    jq --unbuffered -r --arg ralph "$RALPH_ID" '
      if .type == "assistant" then
        .message.content[]? |
        if .type == "tool_use" then
          "[\($ralph)] Tool: " + .name
        elif .type == "text" then
          "[\($ralph)] " + .text
        else empty end
      elif .type == "user" then
        .message.content[]? |
        if .type == "tool_result" and .is_error == true then
          "\n[\($ralph)] ERROR: " + (.content | tostring | .[0:200]) + "\n"
        else empty end
      elif .type == "result" then
        "\n[\($ralph)] Done (" + (.duration_ms | tostring) + "ms, $" + (.total_cost_usd | tostring | .[0:6]) + ")"
      else empty end
    ' 2>/dev/null
  CLAUDE_EXIT=$?
  set -e

  # Release the task lock
  release_task "$TASK_ID"
  cp "$LOCKS_DIR/$TASK_ID/completed.json" "$TASK_LOG_DIR/completed.json" 2>/dev/null || true

  # Check for completion signals in output
  if grep -q '"COMPLETE"' "$TASK_STREAM_JSONL" 2>/dev/null; then
    log "All tasks complete!"
    break
  fi

  if grep -q '"SKIP"' "$TASK_STREAM_JSONL" 2>/dev/null; then
    log "Skipped $TASK_ID"
  fi

  log "Finished $TASK_ID, looking for next task..."
done

log "Ralph finished"
