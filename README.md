# evidence-validation-identity

Dedicated Go-based PocketBase runtime for evidence-validation. Suggested domain: identity.astra-via.com. This directory is a separate repository candidate.

PocketBase version pinned in Dockerfile: 0.40.4. The included migration has been applied and integration-tested on that release. Runtime upgrades must rerun the migration/access-control tests before deployment.

## Local setup

Install the official PocketBase binary for your platform and run from this directory:

```sh
pocketbase serve --http=127.0.0.1:8090 --dir=./pb_data --migrationsDir=./pb_migrations
```

Alternatively `docker compose up --build` creates a named persistent volume and exposes only localhost. Bootstrap a superuser using PocketBase's local installation instructions or CLI. Configure SMTP before public registration. Store the superuser credentials only in the application backend's secret store.

Collections:

- ev_users: authenticated people, names, email/password login, one-hour auth tokens.
- ev_jobs: owner-private drafts; public visibility only when an operator sets status=open for unpaid pilot review.
- ev_reviews: immutable independent submissions, one per reviewer/task; visible to author and task owner, not other reviewers.
- ev_api_keys: owner-visible metadata, hidden token hashes, server-only mutations.

Normal users cannot change a task status, mark a review accepted, change fee terms, or manage integration-key hashes directly. There is no paid/funded task state. Default task creation requires a 1000-basis-point fee; changes need a migration coordinated with the core service.

## Google hosting

Use a durable Compute Engine VM with persistent disk and one active PocketBase instance. Place HTTPS termination in front of it, restrict the administrative dashboard, configure SMTP, and maintain encrypted daily backups plus restore tests. Do not place SQLite/pb_data on Cloud Run's temporary filesystem. Do not start multiple writers against a shared disk.

Database migrations run at startup. Review migration rollback carefully: the down migration deletes the pilot collections. Do not run it against production data as a routine rollback.

PocketBase backs pilot identities and review records only. It does not replace a payment provider's ledger, establish that a person is unique, or qualify a validator. Review qualification and payout accounts require additional records and policy before paid launch.

## Integration verification

In the core repository, point EV_TEST_POCKETBASE_URL to a separate localhost instance, set EV_TEST_ADMIN_EMAIL and EV_TEST_ADMIN_PASSWORD, then run npm test. The test creates and removes its own records. Never point that test at production.

## Checked-image deployment workflow

The check-and-deploy workflow builds one image, applies migrations against fresh data, smoke-tests the running image, and transfers that exact image to deployment. Actions are pinned to commit hashes, deployments are serialized, and Google authentication uses Workload Identity Federation. Main-branch deployment stays disabled until DEPLOY_ENABLED=true and the persistent host is ready. Manual deployment additionally requires the security_reviewed input.

Repository variables: GCP_PROJECT_ID, GCP_REGION, GCP_ARTIFACT_REPOSITORY, GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_DEPLOY_SERVICE_ACCOUNT, IDENTITY_VM_NAME, IDENTITY_VM_ZONE. The deploy identity needs repository write access, IAP tunnel/OS Login permissions, and appropriately restricted VM access. The VM runtime identity needs Artifact Registry read access.

Install `deploy/deploy-image.sh` as `/opt/evidence-validation/deploy-image.sh` on the prepared VM, with root ownership and no write access for ordinary accounts. Docker, gcloud, curl, persistent disk, and the HTTPS reverse proxy must be configured first. The script binds PocketBase to localhost, preserves pb_data, and takes a cold local backup before replacement. Configure encrypted off-host backups and retention separately; local backups alone do not protect against disk loss. Startup-script provisioning and TLS routing depend on the existing Google infrastructure and must be verified before enabling deployment.

The application can use Cloud Run; this identity database deliberately uses persistent VM storage. Cloud Run NFS does not support locking, so mounting network storage is not a safe substitute for PocketBase's SQLite disk requirements.
