#!/bin/bash
set -e

RALPH_ID=${1:-"ralph-$$"}
MAX_ITERATIONS=${2:-10}
WAIT_SECONDS=${WAIT_SECONDS:-60}

# Directories - set by orchestrator or use defaults
MAIN_WORKTREE=${MAIN_WORKTREE:-"$(pwd)"}
RALPH_DIR=${RALPH_DIR:-"$(pwd)"}
BASE_BRANCH=${BASE_BRANCH:-"main"}
LOCKS_DIR=${LOCKS_DIR:-"$MAIN_WORKTREE/.unpossible/locks"}
RUN_LOG_DIR=${RUN_LOG_DIR:-"$MAIN_WORKTREE/.unpossible/logs/manual"}

PROMPT_TEMPLATE="${PROMPT_TEMPLATE:-prompt.template.md}"
PRD_FILE="prd.json"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
OVERLAP_MODE="${OVERLAP_MODE:-0}"

log() {
  # IMPORTANT: logs must go to stderr so command substitutions (e.g. TASK_ID=$(...))
  # only capture machine-readable stdout values like task IDs.
  echo "[$RALPH_ID] $1" 1>&2
}

# List task IDs that are not done and have all dependencies satisfied.
list_ready_task_ids() {
  local tasks_file="$MAIN_WORKTREE/$PRD_FILE"

  jq -r '
    (. as $all
     | reduce $all[] as $t ({}; .[$t.id]=$t) as $m
     | $all[]
     | select(.done != true)
     | select(((.dependsOn // []) | all(. as $d | ($m[$d]? | .done) == true)))
     | .id
    )
  ' "$tasks_file" 2>/dev/null || true
}

# List all pending task IDs sorted by number of incomplete dependencies (fewest first).
# Used in overlap mode where ralphs can claim tasks even if dependencies aren't met.
list_pending_task_ids_by_deps() {
  local tasks_file="$MAIN_WORKTREE/$PRD_FILE"

  jq -r '
    . as $all
    | reduce $all[] as $t ({}; .[$t.id]=$t) as $m
    | [
        $all[]
        | select(.done != true)
        | {
            id: .id,
            unmet: ((.dependsOn // []) | map(select(($m[.]? | .done) != true)) | length)
          }
      ]
    | sort_by(.unmet)
    | .[].id
  ' "$tasks_file" 2>/dev/null || true
}

# Print a human-readable list of blocked tasks (pending tasks with unmet dependencies).
print_blocked_tasks() {
  local tasks_file="$MAIN_WORKTREE/$PRD_FILE"

  jq -r '
    (. as $all
     | reduce $all[] as $t ({}; .[$t.id]=$t) as $m
     | $all[]
     | select(.done != true)
     | (.dependsOn // []) as $deps
     | ($deps | map(select(($m[.]? | .done) != true))) as $unmet
     | select(($unmet | length) > 0)
     | "\(.id) blocked by: \($unmet | join(\", \"))"
    )
  ' "$tasks_file" 2>/dev/null || true
}

# Detect tasks that are in a dependency cycle (best-effort). Only used for "no ready tasks" debugging.
list_cycle_task_ids() {
  local tasks_file="$MAIN_WORKTREE/$PRD_FILE"

  jq -r '
    def deps($m; $id):
      (($m[$id]? | .dependsOn // []) // []);

    def closure($m; $start; $n):
      reduce range(0; $n) as $i
        ({frontier: deps($m; $start), seen: []};
         .frontier as $f
         | .seen = (.seen + $f | unique)
         | .frontier = (
             ($f | map(deps($m; .)) | add // [])
             | unique
             | map(select((.seen | index(.)) | not))
           )
        )
      | .seen;

    (. as $all
     | reduce $all[] as $t ({}; .[$t.id]=$t) as $m
     | ($all | length) as $n
     | $all[]
     | .id as $id
     | select((closure($m; $id; $n) | index($id)) != null)
     | $id
    )
  ' "$tasks_file" 2>/dev/null | sort -u || true
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
  local tasks_file="$MAIN_WORKTREE/$PRD_FILE"

  if [ ! -f "$tasks_file" ]; then
    echo ""
    return
  fi

  local ready_ids

  # In overlap mode, consider all pending tasks sorted by fewest unmet dependencies
  if [ "$OVERLAP_MODE" = "1" ]; then
    ready_ids=$(list_pending_task_ids_by_deps)
  else
    ready_ids=$(list_ready_task_ids)
  fi

  if [ -z "$ready_ids" ]; then
    local pending_count
    pending_count=$(jq -r '[.[] | select(.done != true)] | length' "$tasks_file" 2>/dev/null || echo "0")

    if [ "$pending_count" != "0" ]; then
      log "No ready tasks (pending: $pending_count). Likely blocked by dependencies."
      log "Blocked tasks:"
      print_blocked_tasks | while read -r line; do
        [ -n "$line" ] && log "  $line"
      done

      local cycles
      cycles=$(list_cycle_task_ids)
      if [ -n "$cycles" ]; then
        log "Dependency cycle detected involving:"
        echo "$cycles" | while read -r id; do
          [ -n "$id" ] && log "  $id"
        done
      fi
    fi

    if [ "$pending_count" = "0" ]; then
      echo ""
    else
      echo "__WAIT__"
    fi
    return
  fi

  for task_id in $ready_ids; do
    if claim_task "$task_id"; then
      echo "$task_id"
      return
    fi
  done

  if [ -n "$ready_ids" ]; then
    log "No claimable tasks (ready tasks appear locked). Ready tasks were:"
    echo "$ready_ids" | while read -r id; do
      [ -n "$id" ] && log "  $id"
    done
  fi

  echo "__WAIT__"
}

# Get full task JSON by ID
get_task_json() {
  local task_id=$1
  local tasks_file="$MAIN_WORKTREE/$PRD_FILE"
  jq -c ".[] | select(.id == \"$task_id\")" "$tasks_file" 2>/dev/null || echo "{}"
}

# Extract assistant text from a stream-json file and check whether it contains an exact promise line.
stream_has_promise() {
  local stream_file="$1"
  local promise="$2"

  jq -r '
    select(.type == "assistant")
    | (.message.content[]? | select(.type == "text") | .text)
  ' "$stream_file" 2>/dev/null | \
    sed 's/\r$//' | \
    grep -Eq "^[[:space:]]*<promise>${promise}</promise>[[:space:]]*$"
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
log "Wait when blocked: ${WAIT_SECONDS}s"

# Change to ralph directory
cd "$RALPH_DIR"

iter=0
while true; do
  iter=$((iter + 1))
  log "Iteration $iter: Looking for work..."

  # Sync with base branch to get latest task file status.
  log "Syncing with $BASE_BRANCH..."
  git merge --ff-only "$BASE_BRANCH" 2>/dev/null || true

  # Find and claim a pending task
  TASK_ID=$(find_pending_task)

  if [ -z "$TASK_ID" ]; then
    log "No pending tasks available (all done). Exiting."
    break
  fi

  if [ "$TASK_ID" = "__WAIT__" ]; then
    log "Tasks remain but none are ready/claimable. Sleeping for ${WAIT_SECONDS}s..."
    sleep "$WAIT_SECONDS"
    continue
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

  # Check for completion/skip signals in output
  if stream_has_promise "$TASK_STREAM_JSONL" "COMPLETE"; then
    log "All tasks complete!"
    release_task "$TASK_ID"
    cp "$LOCKS_DIR/$TASK_ID/completed.json" "$TASK_LOG_DIR/completed.json" 2>/dev/null || true
    break
  fi

  if stream_has_promise "$TASK_STREAM_JSONL" "SKIP"; then
    log "Skipped $TASK_ID"
    echo "{\"skippedAt\": \"$(date -Iseconds)\"}" > "$TASK_LOG_DIR/skipped.json"
    rm -rf "$LOCKS_DIR/$TASK_ID" 2>/dev/null || true
    log "Finished $TASK_ID, looking for next task..."
    continue
  fi

  # Task ran normally: mark lock completed
  release_task "$TASK_ID"
  cp "$LOCKS_DIR/$TASK_ID/completed.json" "$TASK_LOG_DIR/completed.json" 2>/dev/null || true

  log "Finished $TASK_ID, looking for next task..."

  if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$iter" -ge "$MAX_ITERATIONS" ]; then
    pending_count=$(jq -r '[.[] | select(.done != true)] | length' "$MAIN_WORKTREE/$PRD_FILE" 2>/dev/null || echo "0")
    if [ "$pending_count" = "0" ]; then
      log "Reached max iterations ($MAX_ITERATIONS) and all tasks are done. Exiting."
      break
    fi
    log "Reached max iterations ($MAX_ITERATIONS) but tasks remain (pending: $pending_count). Continuing until all tasks are done."
  fi
done

log "Ralph finished"
