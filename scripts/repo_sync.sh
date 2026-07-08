#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "Not on a branch. Check out a branch before syncing." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Tracked changes are not committed. Commit or stash them before syncing." >&2
  git status --short
  exit 1
fi

echo "Fetching origin..."
git fetch --prune origin

if ! upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  echo "Branch '$branch' has no upstream. Current status:"
  git status --short --branch
  exit 0
fi

read -r ahead behind < <(git rev-list --left-right --count HEAD..."$upstream")

if [[ "$behind" == "0" ]]; then
  echo "Branch '$branch' is already up to date with $upstream."
else
  echo "Rebasing '$branch' onto $upstream..."
  git rebase "$upstream"
fi

echo
git status --short --branch

if [[ "$ahead" != "0" ]]; then
  echo
  echo "Local commits remain unpublished. Use ./scripts/repo_publish.sh when ready."
fi
