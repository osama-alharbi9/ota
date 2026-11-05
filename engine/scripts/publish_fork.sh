#!/usr/bin/env bash
# After building ENGINE_BRANCH: create FORK_BRANCH = ENGINE_BRANCH + a commit that
# writes the engine hash to bin/internal/engine.version, and push both branches,
# plus the flutter_release/<version> branch and <version> tag that flutter_tools
# reads, to the public fork. Prints the commit for cli/bin/internal/flutter.version.
# The commit is made with git plumbing (a temporary index), so the working tree
# and HEAD (ENGINE_BRANCH, possibly mid-build) are not touched.
set -euo pipefail
source "$(dirname "$0")/env.sh"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.7}"
E=$(engine_commit)
cd "$FLUTTER_SRC"
[ "$(git symbolic-ref -q --short HEAD || true)" != "$FORK_BRANCH" ] \
  || { echo "HEAD is on $FORK_BRANCH; git checkout $ENGINE_BRANCH first"; exit 1; }
blob=$(echo "$E" | git hash-object -w --stdin)
idx=$(mktemp); trap 'rm -f "$idx"' EXIT
GIT_INDEX_FILE=$idx git read-tree "$ENGINE_BRANCH"
GIT_INDEX_FILE=$idx git update-index --cacheinfo "100644,$blob,bin/internal/engine.version"
tree=$(GIT_INDEX_FILE=$idx git write-tree)
F=$(git -c user.name=ota -c user.email=dev@ota.local commit-tree "$tree" -p "$ENGINE_BRANCH" -m "ota: engine.version -> $E")
git branch -f "$FORK_BRANCH" "$F"
git push -q -f "$FORK_MIRROR" "$ENGINE_BRANCH:$ENGINE_BRANCH" "$FORK_BRANCH:$FORK_BRANCH"
git push -q -f "$FORK_MIRROR" "$FORK_BRANCH:refs/heads/flutter_release/$FLUTTER_VERSION" "$FORK_BRANCH:refs/tags/$FLUTTER_VERSION"
echo "published: framework $F (flutter.version), engine $E (engine.version)"
echo "$F"
