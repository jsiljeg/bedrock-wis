# CI/CD Workflows Overview

This repository uses three GitHub Actions workflows:

1. **Bedrock application pipeline** — `.github/workflows/deploy.yml`  
   Builds Bedrock + Sage + selected plugins, publishes a versioned release tarball, deploys to a GCE VM with atomic releases, runs a health check, and rolls back on failure.

2. **Monitoring deployment (Ansible, no vault)** — `.github/workflows/deploy-monitoring-ansible.yml`  
   Uses Ansible to install/update the monitoring stack (Prometheus, Alertmanager, Grafana, exporters) on the same VM (or target host).

3. **Monitoring smoke test (Alertmanager → Slack)** — `.github/workflows/monitoring-smoke-test.yml`  
   Sends a synthetic alert into Alertmanager to verify Slack notifications end-to-end.

> Caching (Composer/Yarn) is documented in **[BUILD_CACHE_STRATEGY.md](./BUILD_CACHE_STRATEGY.md)**. The Bedrock pipeline implements weekly-rotating cache keys and restore-key fallbacks to keep builds fast yet fresh.

---

## Required GitHub Secrets

Common:
- `GCE_HOST` — target VM IP/DNS
- `GCE_USER` — SSH user on the VM
- `GCE_SSH_KEY` — private key with VM access (PEM content)

Bedrock deploy:
- `GCE_DEPLOY_PATH` — e.g. `/var/www/bedrock`
- `HEALTHCHECK_URL` — public site URL to probe after deploy
- `WP_ADMIN_USER`, `WP_ADMIN_PASS`, `WP_ADMIN_EMAIL` — one-time WordPress core install (idempotent)

Monitoring (Ansible deploy):
- `SLACK_WEBHOOK_URL` — Slack webhook (consumed by rules/templates)
- `SLACK_CHANNEL` — destination Slack channel
- `GF_ADMIN_USER`, `GF_ADMIN_PASSWORD` — Grafana admin bootstrap

---

## 1) Bedrock Application Pipeline (`deploy.yml`)

**Triggers**
- On push to `master`
- Manual `workflow_dispatch`

**Jobs**
### `bedrock_build`
- Checks out repo.
- Sets up PHP/Composer.
- **Caches Composer (root) with weekly-rotating key** (see BUILD_CACHE_STRATEGY.md).
- Runs `composer install` (no-dev).
- Uploads `vendor.tar.gz` artifact.

### `theme_build`
- Checks out repo.
- Sets up PHP & Composer.
- **Caches Composer (theme) with weekly rotation.**
- Installs **Sage** theme PHP deps (no-dev).
- Sets up Node.
- **Caches Yarn + `node_modules` with weekly rotation.**
- Builds Sage (Bud): `yarn build`. Fails if `public/entrypoints.json` missing.
- Uploads built theme as `theme-build` artifact.

### `plugins_build`
- Checks out repo.
- **Caches plugin deps and build outputs** (Composer/Yarn/vendor/node_modules) with weekly rotation.
- Clones plugins listed in `BUILD_PLUGINS` env (e.g., Yoast, WooCommerce) into `web/app/plugins`, strips `.git/` dirs.
- Uploads `plugins` artifact.

### `package_release`
- Downloads artifacts (`vendor`, `theme-build`, `plugins`).
- Injects them into the working tree (`web/app/...`).
- Validates WordPress core under `web/wp`; if missing, downloads via WP-CLI fallback.
- Composer install (no-dev) to ensure deterministic lock/installed set.
- Adds **Roots Acorn** (prefers `^5`, falls back to `^4.4` if needed) with a conflict-safe update routine.
- Creates a tarball `bedrock-YYYYMMDD-HHMMSS.tar.gz` and publishes a **GitHub Release** with this asset.

### `deploy`
- Downloads the release tarball.
- Uses a custom action to deploy via SSH/Rsync into an **atomic release** structure under `GCE_DEPLOY_PATH`:
  - `releases/<timestamp>` — new release
  - `current` symlink — active release
  - `shared/` — persistent data (e.g., caches)
- Idempotent **WP core install** with admin credentials (no-op if already installed).
- Ensures shared **Acorn cache** permissions and links `web/app/cache` to `shared/cache`.
- Activates the **Sage** theme, sets permalinks, and flushes rewrites.
- If Acorn is present as a plugin, activate and clear Acorn caches.

### `monitoring_probe` (informational)
- SSH port-forwards to Prometheus (9090) and Grafana (3000) and validates they respond (`/-/ready`, `/login`). Does **not** change infra.

### `health_check`
- Polls `HEALTHCHECK_URL` with retries/delay until success.

### `rollback_on_failure`
- If any dependency job failed (deploy or health), runs a **rollback action** that flips `current` symlink back to the previous release.

**How to Run/Verify**
- Run `workflow_dispatch`.
- First run: expect cache misses; second run: expect cache hits (see logs for `Cache restored from key:`).
- Confirm a new **Release** exists with the tarball; on the VM, `current` points to the latest `releases/<timestamp>`.
- Site responds on `HEALTHCHECK_URL`.
- Rollback test: temporarily break `HEALTHCHECK_URL` (e.g., nonexistent path), re-run, watch rollback execute, and `current` revert.

---

## 2) Monitoring Deployment via Ansible (`deploy-monitoring-ansible.yml`)

**Trigger conditions**

This workflow runs in two cases:

- **Manual trigger (`workflow_dispatch`)**  
  Can be started from the **Actions** tab in GitHub.  
  Includes an optional input:  
  - `run-health-checks` (boolean, default `true`) — reserved for future post-deploy validation steps.

- **Automatic trigger (`push`)**  
  Runs on commits to the `master` branch **only when monitoring-related files change**, such as:
  - `monitoring/**` — monitoring stack definitions  
  - `ansible/monitoring.yml` — main playbook  
  - `ansible/roles/monitoring/**` or `ansible/roles/docker/**` — supporting roles  
  - `.github/workflows/deploy-monitoring-ansible.yml` — the workflow file itself  


**What it does**
- Checks out repo.
- Sets up Python + Ansible 9.x.
- Prepares SSH (`~/.ssh/id_rsa`, known_hosts).
- Installs Galaxy collections: `community.general`, `community.docker`.
- Runs the playbook `ansible/monitoring.yml` against an **inline inventory** consisting of a single host (`GCE_HOST,` — note the trailing comma) with `-u GCE_USER` and private key auth.
- Exposes variables to the play: Slack webhook/channel, Grafana admin creds, and deploy path.

**Expected result**
- Prometheus, Alertmanager, Grafana (and exporters) are installed/updated on the target host.
- Any Docker services/compose files/templates are applied idempotently by the playbook.

**How to Run/Verify**
1. Dispatch the workflow with defaults.  
2. SSH to the VM and verify services are up (examples):
   - `curl -fsS http://127.0.0.1:9090/-/ready` (Prometheus)
   - `curl -fsS http://127.0.0.1:9093/-/ready` (Alertmanager)
   - Open Grafana via port-forward or HTTPS and login using Grafana admin creds.
3. Check Slack for notifications (if your rules send startup/heartbeat alerts).

**Notes**
- No Ansible Vault is used; **all secrets come from GitHub Secrets**.
- The inventory is inline; to target multiple hosts/environments, switch to a real inventory file and matrix strategy.

---

## 3) Monitoring Slack Smoke Test (`monitoring-smoke-test.yml`)

**Trigger**
- Manual `workflow_dispatch` with inputs:
  - `severity`: one of `info`, `warning`, `critical` (default `warning`)
  - `instance`: free-form label value (default `smoke-test`)

**What it does**
- Prepares SSH and connects to the VM.
- Creates a small JSON alert payload with labels (`alertname=SlackSmokeTest`, `severity`, `instance`) and annotations.
- POSTs it to the **local Alertmanager** API: `http://127.0.0.1:9093/api/v2/alerts`.

**Expected result**
- The configured Alertmanager route(s) and Slack receiver deliver the alert to your **Slack channel**.
- You should see a message like: “Synthetic test alert from GitHub Actions”.

**How to Run/Verify**
1. Dispatch the workflow with the desired `severity` and `instance`.
2. Confirm a message appears in the Slack channel configured by your Alertmanager/Grafana/Prometheus rules.
3. If not, check:
   - Alertmanager logs
   - Slack webhook validity (`SLACK_WEBHOOK_URL`)
   - Network reachability (if Alertmanager isn’t bound to localhost, adjust URL accordingly).

---

## Operational Tips

- **Atomic releases**: All deploys are non-destructive. Rollback simply flips `current` to the previous `releases/<timestamp>`. Keep at least 2 releases on disk.
- **WP-CLI fallback**: If `web/wp` is missing in the release bundle, the pipeline auto-downloads WordPress core to guarantee a runnable install.
- **Acorn/Sage**: The build will **fail** if `public/entrypoints.json` is missing, ensuring the theme assets are produced.
- **Cache freshness**: Weekly-rotating keys keep caches from going stale. See **BUILD_CACHE_STRATEGY.md** for details.
- **Troubleshooting**:
  - SSH from your machine using the same key to validate network reachability.
  - Check systemd/Docker logs for services installed by Ansible.
  - Use `gh run watch` to stream logs during a run.

---

## Common Commands

On the VM:
```bash
# Release pointers
readlink -f /var/www/bedrock/current
ls -1 /var/www/bedrock/releases

# Prometheus/Alertmanager/Grafana health
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:9093/-/ready
curl -I    http://127.0.0.1:3000/login | head -n 1
```

Locally, with GH CLI:
```bash
# View caches
gh cache list

# Force cache purge if needed
gh cache delete <ID>

# Trigger a workflow manually with inputs
gh workflow run monitoring-smoke-test.yml -f severity=warning -f instance=smoke-test
```



# Build Cache Strategy

We cache dependency managers and build outputs to speed up CI while keeping caches fresh.

## Layers Cached
- **Composer (root Bedrock)** → `~/.cache/composer`
- **Composer (Sage theme)** → `~/.cache/composer`
- **Yarn (Sage theme)** → `~/.cache/yarn` and `web/app/themes/sage/node_modules`
- **Plugins (optional)** → `~/.cache/composer`, `~/.cache/yarn`, and per-plugin `vendor` / `node_modules`

## Key Design
Cache keys include:
1. **OS** — `${{ runner.os }}`  
2. **Runtime version** — `php${PHP_VERSION}`, `node${NODE_VERSION}`  
3. **Lockfile hash** — `hashFiles('composer.lock')`, `hashFiles('yarn.lock')`, etc.  
4. **Weekly stamp** — ISO week (`date -u +%G-W%V`) to simulate a “TTL” and avoid stale caches.

### Example keys
- Root Composer:  
  `composer-${OS}-php${PHP_VERSION}-${hash(composer.lock)}-${WEEK}`
- Theme Composer:  
  `composer-${OS}-php${PHP_VERSION}-${hash(theme/composer.lock)}-${WEEK}`
- Theme Yarn:  
  `yarn-${OS}-node${NODE_VERSION}-${hash(theme/yarn.lock)}-${WEEK}`
- Plugins (aggregate):  
  `plugins-${OS}-php${PHP_VERSION}-node${NODE_VERSION}-${hash(plugins/**/locks)}-${WEEK}`

## Restore Keys (Fallback)
Each cache uses a **restore-keys** ladder to gracefully fall back:
1. exact (`…-lock-hash-<WEEK>`)
2. same lock hash (any week)
3. same runtime (any lock, any week)
4. same OS (last resort)

This yields fast builds after the first hit while ensuring we rotate caches weekly.

## Eviction / TTL
GitHub Actions **cache** entries are evicted automatically ~**7 days** after last access (and when storage limits are hit).  
We **don’t set TTLs** directly (not supported for caches). Instead, the **weekly stamp** forces a regular refresh while still allowing fallbacks.

## Manual Purge
Use GitHub CLI:

```bash
gh cache list
gh cache delete <ID>
```
This forces a cold run on the next build.
