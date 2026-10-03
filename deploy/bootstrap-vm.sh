#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq docker.io nginx curl jq ca-certificates
systemctl enable --now docker
install -d -m 0750 /opt/evidence-validation
cat > /opt/evidence-validation/deploy-image.sh <<'DEPLOY_SCRIPT'
#!/usr/bin/env bash
# Install at /opt/evidence-validation/deploy-image.sh on the persistent identity VM.
set -euo pipefail
image=${1:?Pass the checked Artifact Registry image tagged by commit SHA}
[[ "$image" =~ ^[a-z0-9-]+-docker\.pkg\.dev/[a-z0-9-]+/[a-z0-9-]+/evidence-validation-identity:[a-f0-9]{40}$ ]] || { echo 'Invalid image reference'; exit 1; }
command -v docker >/dev/null
command -v jq >/dev/null
registry=${image%%/*}
credential_dir=$(mktemp -d)
export DOCKER_CONFIG="$credential_dir"
trap 'rm -rf "$credential_dir"' EXIT
curl --fail --silent -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -r .access_token | docker login -u oauth2accesstoken --password-stdin "$registry" >/dev/null
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
DEPLOY_SCRIPT
chmod 0750 /opt/evidence-validation/deploy-image.sh
cat > /etc/nginx/sites-available/evidence-validation-identity <<'PROXY_CONFIG'
server {
    listen 8080;
    server_name identity.astra-via.com;
    client_max_body_size 128k;
    location ^~ /_/auth/ { proxy_pass http://127.0.0.1:8090; }
    location ^~ /_/assets/ { proxy_pass http://127.0.0.1:8090; }
    location ^~ /_/ { return 404; }
    location = /_ { return 404; }
    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }
}
PROXY_CONFIG
ln -sf /etc/nginx/sites-available/evidence-validation-identity /etc/nginx/sites-enabled/evidence-validation-identity
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx
if ! docker inspect ev-identity >/dev/null 2>&1; then
    image=me-west1-docker.pkg.dev/astra-via/astra-images/evidence-validation-identity:8578e420beadea7085ca7fac942cdac44852c307
    install -d -o 10001 -g 10001 /var/lib/evidence-validation/pb_data
    credential_dir=$(mktemp -d)
    export DOCKER_CONFIG="$credential_dir"
    trap 'rm -rf "$credential_dir"' EXIT
    token=$(curl --fail --silent -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -r .access_token)
    printf '%s' "$token" | docker login -u oauth2accesstoken --password-stdin me-west1-docker.pkg.dev >/dev/null
    docker pull "$image"
    docker run --rm --mount type=bind,source=/var/lib/evidence-validation/pb_data,target=/pb/pb_data "$image" migrate up --dir=/pb/pb_data --migrationsDir=/pb/pb_migrations
    email=$(curl --fail --silent -H "Authorization: Bearer $token" https://secretmanager.googleapis.com/v1/projects/astra-via/secrets/ev-pocketbase-superuser-email/versions/1:access | jq -r .payload.data | base64 -d)
    password=$(curl --fail --silent -H "Authorization: Bearer $token" https://secretmanager.googleapis.com/v1/projects/astra-via/secrets/ev-pocketbase-superuser-password/versions/1:access | jq -r .payload.data | base64 -d)
    docker run --rm --mount type=bind,source=/var/lib/evidence-validation/pb_data,target=/pb/pb_data "$image" superuser upsert "$email" "$password" --dir=/pb/pb_data
    unset token email password
    /opt/evidence-validation/deploy-image.sh "$image"
fi
