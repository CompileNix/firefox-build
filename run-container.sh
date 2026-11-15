#!/bin/bash
# vim: sw=4 et
#
# Start the firefox-build container.
#
# --oom-score-adj 1000 makes build processes (e.g. the 18+ GB gkrust rustc)
# the first victim when the host runs out of memory, instead of desktop apps.
#
# Usage:
#   ./run-container.sh                # detached, tmux session "build" (default)
#   ./run-container.sh --interactive  # throw-away interactive shell (--rm)
#
# Overrides (environment):
#   FIREFOX_BUILD_OOM_SCORE_ADJ  oom_score_adj for build processes (default: 1000)
#   FIREFOX_BUILD_NAME           container name (default: firefox-build)
#   FIREFOX_BUILD_IMAGE          image (default: firefox-build:fedora)
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

NAME="${FIREFOX_BUILD_NAME:-firefox-build}"
IMAGE="${FIREFOX_BUILD_IMAGE:-firefox-build:fedora}"
OOM_SCORE_ADJ="${FIREFOX_BUILD_OOM_SCORE_ADJ:-1000}"

limits=(
    --oom-score-adj "$OOM_SCORE_ADJ"
)

mounts=(
    -v "$PWD/dist:/dist:z"
    -v "$PWD/mozbuild:/root/.mozbuild:z"
    -v "$PWD/sccache:/root/.cache/sccache:z"
    -v "$PWD/firefox:/src/firefox:z"
    -v "$PWD/mozconfig:/src/mozconfig:z"
    -v "$PWD/patches:/src/patches:z"
)

if docker container inspect "$NAME" >/dev/null 2>&1; then
    current_adj=$(docker container inspect --format '{{.HostConfig.OomScoreAdj}}' "$NAME")
    echo "container \"$NAME\" already exists"
    if [ "$current_adj" != "$OOM_SCORE_ADJ" ]; then
        echo "note: oom-score-adj is $current_adj, not $OOM_SCORE_ADJ; it cannot be changed on a" >&2
        echo "      running container. Recreate it: docker rm -f $NAME && $0" >&2
    fi
    exit 0
fi

case "${1:-}" in
    "")
        docker run -d --name "$NAME" --hostname "$NAME" \
            "${limits[@]}" "${mounts[@]}" \
            -it "$IMAGE" tmux new-session -s build -x 220 -y 50
        echo "attach with: docker exec -it $NAME tmux attach -t build"
        ;;
    --interactive|-i)
        exec docker run --rm --name "$NAME" --hostname "$NAME" \
            "${limits[@]}" "${mounts[@]}" \
            -it "$IMAGE"
        ;;
    *)
        echo "usage: $0 [--interactive]" >&2
        exit 2
        ;;
esac
