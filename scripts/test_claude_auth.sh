#!/usr/bin/env bash
set -euo pipefail

image="${1:?usage: scripts/test_claude_auth.sh <image> <host-home>}"
host_home="${2:?usage: scripts/test_claude_auth.sh <image> <host-home>}"
credentials="$host_home/.claude/.credentials.json"
settings="$host_home/.claude.json"
volume="holycode-claude-auth-$$"

test -f "$credentials"
test -f "$settings"

# Keep Git for Windows from rewriting container-side bind mount paths.
export MSYS_NO_PATHCONV=1

cleanup() {
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$volume" >/dev/null
docker run --rm --entrypoint sh \
  -v "$credentials:/source/credentials.json:ro" \
  -v "$settings:/source/claude.json:ro" \
  -v "$volume:/home/agent1" \
  "$image" -lc '
    mkdir -p /home/agent1/.claude
    cp /source/credentials.json /home/agent1/.claude/.credentials.json
    cp /source/claude.json /home/agent1/.claude.json
    chown -R agent1:agent1 /home/agent1/.claude /home/agent1/.claude.json
    sha256sum /home/agent1/.claude/.credentials.json /home/agent1/.claude.json > /home/agent1/.claude-auth-before
  '

for _ in 1 2; do
  docker run --rm --entrypoint sh \
    -v "$volume:/home/agent1" \
    "$image" -lc '
      runuser -u agent1 -- claude auth status --json |
        jq -e ".loggedIn == true and (.authMethod | length > 0)" >/dev/null
    '
done

docker run --rm --entrypoint sh \
  -v "$volume:/home/agent1" \
  "$image" -lc '
    sha256sum --check --status /home/agent1/.claude-auth-before
  '

echo "Claude authentication and recreation persistence passed"
