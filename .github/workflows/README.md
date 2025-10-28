


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
