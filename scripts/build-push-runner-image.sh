#!/usr/bin/env bash
# build-push-runner-image.sh — build & push the agent-runner container image used by
# the GCP Cloud Run execution path. Uses Cloud Build, so NO local Docker is required.
#
# The resulting image's entrypoint is the agent-runner binary (see
# daemon/agent-runner/Dockerfile). Its tag is what you set as GCP_CLOUD_RUN_IMAGE on
# the push-backend deployment; the backend refuses to launch against the inert
# gcr.io/cloudrun/hello placeholder.
#
# Usage:
#   GCP_PROJECT=my-proj scripts/build-push-runner-image.sh [TAG]
#
# Env:
#   GCP_PROJECT   (required) target project for the build + Artifact/Container Registry
#   GCP_REGION    (default us-central1) — informational; image is pushed to gcr.io
#   IMAGE_REPO    (default gcr.io/$GCP_PROJECT/agent-runner) full repo path override
# Args:
#   TAG           (default: short git SHA, or "latest" outside a git tree)
set -euo pipefail

: "${GCP_PROJECT:?set GCP_PROJECT (the target GCP project id)}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER_DIR="$REPO_ROOT/daemon/agent-runner"
IMAGE_REPO="${IMAGE_REPO:-gcr.io/$GCP_PROJECT/agent-runner}"

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  TAG="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo latest)"
fi
IMAGE="$IMAGE_REPO:$TAG"

command -v gcloud >/dev/null || { echo "FATAL: gcloud CLI is required"; exit 2; }
[[ -f "$RUNNER_DIR/Dockerfile" ]] || { echo "FATAL: $RUNNER_DIR/Dockerfile not found"; exit 2; }

echo "=== Building $IMAGE via Cloud Build (project: $GCP_PROJECT) ==="
gcloud builds submit "$RUNNER_DIR" \
  --project "$GCP_PROJECT" \
  --tag "$IMAGE"

echo
echo "✓ Pushed $IMAGE"
echo
echo "Next: set this on the push-backend deployment and restart it:"
echo "  GCP_CLOUD_RUN_IMAGE=$IMAGE"
echo "  GCP_PROJECT=$GCP_PROJECT"
echo "Then run scripts/gcp-staging-smoke.sh to verify end-to-end."
