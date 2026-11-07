#!/bin/bash
# Lands a stack of squash-merged PRs in order, from the bottom up.
#
#   scripts/land-stack.sh 1081:guides/mixer-hub 1082:guides/tap-points 1083:guides/x32
#
# Each argument is PR:branch, bottom of the stack first; the first PR must already target main.
# For each PR above the bottom one, once the PR below it merges, the script:
#   1. rebases the branch onto origin/main, dropping the commits of the PR below. It drops them
#      by the parent branch's tip as it was BEFORE anything was rewritten, recorded at the start:
#      after a squash merge, the parent's later tip no longer marks where this branch began.
#   2. retargets the PR to main BEFORE pushing. The org's required "spelling" workflow runs
#      only for pushes to a PR that already targets main, so push-then-retarget leaves the PR
#      blocked with every visible check green.
#   3. pushes with --force-with-lease, turns on auto-merge (squash), and checks that the
#      spelling check started; if it didn't, closes and reopens the PR to start it and turns
#      auto-merge back on (reopening turns it off).
# Stops on a rebase conflict, leaving the branch as it was.
set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,4p' "$0"; exit 2; }

wait_merged() {
  for _ in $(seq 1 120); do
    [ "$(gh pr view "$1" --json state --jq .state)" = MERGED ] && return 0
    sleep 30
  done
  echo "timed out waiting for #$1 to merge" >&2; exit 1
}

spelling_started() {
  gh pr checks "$1" 2>/dev/null | awk -F'\t' '$1=="spelling"{found=1} END{exit !found}'
}

ensure_spelling() {
  for _ in $(seq 1 8); do spelling_started "$1" && return 0; sleep 15; done
  echo "#$1: spelling check didn't start; reopening the PR to start it"
  gh pr close "$1" >/dev/null
  gh pr reopen "$1" >/dev/null
  gh pr merge "$1" --auto --squash
}

git fetch -q origin
declare -a prs branches bases
for arg in "$@"; do
  prs+=("${arg%%:*}"); branches+=("${arg#*:}")
done
# Record each branch's parent tip now, before any rebase rewrites it.
bases+=("")
for ((i = 1; i < ${#branches[@]}; i++)); do
  bases+=("$(git rev-parse "origin/${branches[i-1]}")")
done

gh pr merge "${prs[0]}" --auto --squash
echo "auto-merge on #${prs[0]}"

for ((i = 1; i < ${#prs[@]}; i++)); do
  n=${prs[i]}; br=${branches[i]}
  wait_merged "${prs[i-1]}"; echo "#${prs[i-1]} merged"
  git fetch -q origin
  git checkout -q "$br"
  git reset -q --hard "origin/$br"
  if ! git rebase -q --onto origin/main "${bases[i]}" "$br"; then
    git rebase --abort
    echo "rebase conflict on #$n ($br); stopping" >&2; exit 1
  fi
  gh pr edit "$n" --base main >/dev/null
  git push -q --force-with-lease origin "$br"
  gh pr merge "$n" --auto --squash
  ensure_spelling "$n"
  echo "#$n rebased onto main, auto-merge on"
done

wait_merged "${prs[-1]}"; echo "#${prs[-1]} merged; stack landed"
