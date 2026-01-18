#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [dest] [--force]"
  echo ""
  echo "Creates a throwaway sandbox repo (default: /tmp/unp) suitable for running:"
  echo "  ./unpossible.sh 2 10 haiku"
}

DEST="/tmp/unp"
FORCE="0"

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      usage
      exit 0
      ;;
    --force)
      FORCE="1"
      ;;
    *)
      DEST="$arg"
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/python-haiku-repo"

if [ ! -d "$FIXTURE_DIR" ]; then
  echo "Error: fixture directory not found: $FIXTURE_DIR" 1>&2
  exit 1
fi

if [ -e "$DEST" ]; then
  if [ "$FORCE" = "1" ]; then
    case "$DEST" in
      /tmp/*|/private/tmp/*) ;;
      *)
        echo "Error: refusing to --force remove non-/tmp path: $DEST" 1>&2
        exit 2
        ;;
    esac
    rm -rf "$DEST"
  else
    echo "Error: destination already exists: $DEST (use --force to replace)" 1>&2
    exit 3
  fi
fi

mkdir -p "$DEST"
cp -R "$FIXTURE_DIR/." "$DEST/"

cp "$REPO_ROOT/unpossible.sh" "$DEST/unpossible.sh"
cp "$REPO_ROOT/ralph.sh" "$DEST/ralph.sh"
chmod +x "$DEST/unpossible.sh" "$DEST/ralph.sh"

cd "$DEST"

if [ ! -d .git ]; then
  git init -b main >/dev/null
fi

git config user.name "Unpossible Sandbox"
git config user.email "unpossible-sandbox@example.com"

git add -A
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  : # already has commits
else
  git commit -m "chore: seed unpossible sandbox" >/dev/null
fi

PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    PYTHON_BIN="python"
  fi
fi

"$PYTHON_BIN" -m unittest discover -s tests >/dev/null

echo "Created sandbox repo at: $DEST"
echo "Next:"
echo "  cd $DEST"
echo "  ./unpossible.sh 2 10 haiku"

