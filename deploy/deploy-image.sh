#!/usr/bin/env bash
# Install at /opt/evidence-validation/deploy-image.sh on the persistent identity VM.
set -euo pipefail
image=${1:?Pass the checked Artifact Registry image tagged by commit SHA}
[[ "$image" =~ ^[a-z0-9-]+-docker\.pkg\.dev/[a-z0-9-]+/[a-z0-9-]+/evidence-validation-identity:[a-f0-9]{40}$ ]] || { echo 'Invalid image reference'; exit 1; }
command -v docker >/dev/null
command -v gcloud >/dev/null
registry=${image%%/*}
gcloud auth configure-docker "$registry" --quiet
docker pull "$image"
install -d -o 10001 -g 10001 /var/lib/evidence-validation/pb_data
install -d -m 0700 /var/backups/evidence-validation
if docker inspect ev-identity >/dev/null 2>&1; then
  docker stop --time=30 ev-identity
  # Cold backup: no SQLite writer is active during the copy.
  tar -C /var/lib/evidence-validation -czf "/var/backups/evidence-validation/pre-deploy-$(date -u +%Y%m%dT%H%M%SZ).tar.gz" pb_data
  docker rm ev-identity
fi
docker run --detach --name ev-identity --restart unless-stopped \
  --publish 127.0.0.1:8090:8090 \
  --mount type=bind,source=/var/lib/evidence-validation/pb_data,target=/pb/pb_data \
  --memory=768m --cpus=1 --security-opt=no-new-privileges \
  "$image"
for attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:8090/api/health >/dev/null; then
    echo 'Identity service is healthy; persistent data retained.'
    exit 0
  fi
  sleep 2
done
echo 'Identity health check failed. Prior data backup retained; inspect locally before restoring.' >&2
exit 1
