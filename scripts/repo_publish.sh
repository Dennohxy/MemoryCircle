#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "Not on a branch. Check out a branch before publishing." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Tracked changes are not committed. Commit or stash them before publishing." >&2
  git status --short
  exit 1
fi

"$repo_root/scripts/repo_sync.sh"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  echo "Pushing '$branch' to its upstream..."
  git push
else
  echo "Creating upstream origin/$branch..."
  git push -u origin "$branch"
fi

echo
git status --short --branch
