# Session Context

> Updated after every prompt. Purpose: survive VS Code crashes and allow conversation recovery.
> Last updated: 19 April 2026 — full dry-run rebuild session.

---

## Project

**WordPress Security Webinar Demo** — a Docker-based environment for a live security demo at a dev.bg webinar.

- **Event**: dev.bg webinar, 20.04.2026 at 19:30
- **Branch**: `develop`
- **Stack**: WordPress 6.9 / PHP 8.3-apache (port 8080) + MySQL 8.0 (`db` service, user `wpuser`/`wppassword`/`wordpress`) + Redis 7 + attacker Flask C2 (port 9090) + WPScan (profile: `tools`)
- WordPress at `http://localhost:8080`, attacker C2 at `http://localhost:9090`
- **WPScan API token**: `j7U2vFIvwayMPpsxJUGFjWcf4YMlTQGpQ15Ud5doSZE` — rotate after presentation

---

## File Map

| File | Purpose | Status |
|------|---------|--------|
| `docker-compose.yml` | All services + WPScan API token env var | Modified |
| `Dockerfile.wordpress` | WP image: mysql-client, apache2-utils (ab), wp-cli, redis ext, 4 scripts | Modified |
| `plugins/wp-vuln-demo/` | Deliberately vulnerable WP plugin | Unchanged |
| `plugins/wp-security-hardened/` | Hardened comparison plugin | Unchanged |
| `scripts/attacker_server.py` | Flask C2 that receives stolen cookies | Unchanged |
| `scripts/wp-setup.sh` | WordPress init + WooCommerce install + 150-revision demo post | Modified |
| `scripts/wp-bloat.sh` | Seeds DB bloat for Section 12 demo (8 steps, idempotent) | **New** |
| `scripts/wp-cleanup.sh` | Cleans all bloat, BEFORE/AFTER output (8 steps) | **New** |
| `scripts/wp-perf-test.sh` | Performance measurement for Sections 11+12 | **New** |
| `demos/csrf-attack.html` | CSRF demo page | Unchanged |
| `demos/passwords.txt` | Mounted into WPScan at `/tmp/passwords.txt:ro` | Unchanged |
| `config/nginx-hardened.conf` | Hardened nginx config | Unchanged |
| `config/php-demo.ini` / `php-hardened.ini` | PHP configs | Unchanged |
| `themes/nulled-theme-demo/functions.php` | 6 obfuscation techniques + 3 backdoor types | Modified |
| `themes/nulled-theme-demo/social-icons.php` | Live webshell: hex `system()` + POST base64 eval | Modified |
| `presentation-demo-execution.md` | **Full 1,090-line demo cheat sheet (second monitor)** | Modified |

---

## Scripts Detail

### `scripts/wp-setup.sh`
- WordPress init (idempotent)
- Creates 4 demo users: admin/editor/author/subscriber
- Activates `wp-vuln-demo` plugin
- **Installs WooCommerce** (`wp plugin install woocommerce --activate`)
- **Installs and enables Redis Object Cache** (`wp plugin install redis-cache --activate` + `wp redis enable`) — fully automated, no manual step needed after rebuild
- Seeds "Revision Bloat Demo" draft post with **150 revisions** (post ID 12)
- Sets permalink structure

### `scripts/wp-bloat.sh`
Idempotent guard: checks for `bloat_defunct_` prefix. 8 steps:
1. 800 expired transients
2. 100 × ~50KB autoloaded orphan options (~5MB autoload bloat)
3. 3,000 orphaned post meta (fake post IDs 99001–102000)
4. 1,500 orphaned user meta (fake user IDs 99001–100500)
5. 750 spam comments
6. 250 auto-draft posts
7. 200 published posts × 100 revisions = 20,000 revision rows (direct SQL)
8. **WooCommerce**: 10 GD placeholder images + 1,000 products + ~12 meta each + 5 revisions each

**Expected BEFORE state**: Autoload ~5MB, 25,000+ revisions, 1,000 WC products, ~12,000 product meta, 800 expired transients, 750 spam, 250 auto-drafts, ~4,500 orphaned meta

### `scripts/wp-cleanup.sh`
Shows BEFORE metrics → 8 cleanup steps → AFTER metrics:
1. `wp transient delete --expired` + manual delete of seeded transients
2. DELETE orphaned autoload options (LIKE `bloat_defunct_%`)
3. DELETE orphaned post meta (LEFT JOIN)
4. DELETE orphaned user meta (LEFT JOIN)
5. DELETE spam comments
6. DELETE auto-drafts
7. DELETE all revisions + OPTIMIZE TABLE
8. DELETE WC bloat products (via `_bloat_product` meta marker) + placeholder images

**Expected AFTER state**: Autoload ~0.03MB, everything else 0

### `scripts/wp-perf-test.sh`
Three subcommands:
- `before` — 10× curl (TTFB + total, avg), ab (req/s + p99), DB stats → saves to `/tmp/perf-baseline.txt`
- `after` — same measurements + prints BEFORE vs AFTER diff table with % change
- `redis` — disables Redis, measures, enables Redis, warms cache, measures, prints Redis OFF vs ON diff table

**Bugs fixed and verified**: curl uses `--no-location --max-time 10` (avoids redirect to `:8080`), `ab` uses `-r`, Redis disable uses `mv` on the drop-in (not `wp redis disable` which silently failed), curl `-w` format ends with `\n` to prevent `read` exit-code-1 under `set -e`. All fixes are baked into the Docker image — no hot-copy needed.

---

## Dockerfile.wordpress

```dockerfile
FROM wordpress:6.9-php8.3-apache
RUN apt-get update && apt-get install -y --no-install-recommends \
    default-mysql-client apache2-utils && rm -rf /var/lib/apt/lists/*
RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp
RUN pecl install redis && docker-php-ext-enable redis
COPY config/php-demo.ini /usr/local/etc/php/conf.d/zz-demo.ini
COPY scripts/wp-setup.sh     /usr/local/bin/wp-setup.sh
COPY scripts/wp-bloat.sh     /usr/local/bin/wp-bloat.sh
COPY scripts/wp-cleanup.sh   /usr/local/bin/wp-cleanup.sh
COPY scripts/wp-perf-test.sh /usr/local/bin/wp-perf-test.sh
RUN chmod +x /usr/local/bin/wp-setup.sh /usr/local/bin/wp-bloat.sh \
              /usr/local/bin/wp-cleanup.sh /usr/local/bin/wp-perf-test.sh
```

---

## DB Notes

- **MySQL client**: `docker compose exec db mysql -u wpuser -pwppassword --table wordpress -e "..."`
- **WP 6.6+ autoload values**: `NOT IN ('no','off','auto-off')` — old installs used `'yes'`/`'no'`
- **`wp db query`**: had TTY issues — use direct `mysql` exec instead
- **Redis**: `wp redis enable` is now automated inside `wp-setup.sh` — no manual step needed after a rebuild

---

## Current Container State

Fresh rebuild + full setup completed in this session. All 6/6 containers healthy. **`wp-setup.sh` ran successfully**: WordPress 6.9 installed, 4 users created, `wp-vuln-demo` + WooCommerce 10.7.0 + redis-cache 2.7.0 activated, Redis Object Cache enabled, posts 10–12 created (post 12 = "Revision Bloat Demo" with 150 revisions). **`wp-bloat.sh` has NOT yet been run** — DB bloat not seeded yet.

**To get to clean demo state from scratch:**
```bash
docker compose down -v && docker compose up -d --build
# wp-setup.sh: WP init, 4 users, wp-vuln-demo, WooCommerce, redis-cache + Redis enable, 150-revision post
docker compose exec wordpress wp-setup.sh
docker compose exec wordpress wp-bloat.sh        # seed all 8 categories of bloat
docker compose exec wordpress wp-perf-test.sh before   # record Section 12 baseline
# ... show Section 12 BEFORE queries ...
docker compose exec wordpress wp-cleanup.sh
docker compose exec wordpress wp-perf-test.sh after
# Redis (Section 11) already enabled by wp-setup.sh — run anytime:
#   docker compose exec wordpress wp-perf-test.sh redis
```

---

## presentation-demo-execution.md Structure

16 sections + Section 12.5. Total ~1,090 lines.

| Section | Topic | Key commands |
|---------|-------|-------------|
| 1 | Enumeration | author sweep, REST API, `vuln_debug_info`, login error |
| 2 | SQL Injection | `vuln_search`, UNION credential dump, `vuln_search_fixed` |
| 3 | XSS | reflected payload, stored guestbook, C2 cookie loot |
| 4 | CSRF | `csrf-attack.html` |
| 5 | IDOR | `vuln_get_user` sweep, `vuln_get_post` |
| 6 | File Upload | webshell upload, execute, `vuln_upload_fixed` |
| 7 | RCE | `vuln_calculator` eval, `system('id')`, `vuln_calculator_fixed` |
| 8 | WPScan | enumerate, brute-force |
| 9 | Supply Chain | nulled theme: 3 backdoors + webshell in social-icons.php |
| 10 | PHP Hardening | php-demo.ini vs php-hardened.ini |
| 11 | Redis | `wp-perf-test.sh redis` (OFF vs ON diff table) |
| 12 | DB Hygiene | autoload queries, cleanup, `wp-perf-test.sh before/after` |
| 12.5 | Before/after | `wp-bloat.sh` → queries → `wp-cleanup.sh` → perf diff |
| 13 | Nginx Hardening | block uploads PHP, rate limit, CSP headers |
| 14 | Read-Only | `DISALLOW_FILE_EDIT`, chmod 440 |
| 15 | Integrity Check | tamper `version.php`, `wp core verify-checksums`, restore |
| 16 | Logging & Backups | debug.log, `wp db export`, 3-2-1 rule |

---

## Pending / Next Session

1. **Run `wp-bloat.sh`** to seed all 8 bloat categories for Section 12 (next step):
   ```bash
   docker compose exec wordpress wp-bloat.sh
   ```
2. **Commit the `wp-setup.sh` redis-cache change** (unstaged `!2`):
   ```bash
   git add scripts/wp-setup.sh && git commit -m "wp-setup.sh: automate redis-cache install and enable"
   ```
3. **Rotate WPScan API token** after presentation: `j7U2vFIvwayMPpsxJUGFjWcf4YMlTQGpQ15Ud5doSZE`

| 5 | Add missing sections to demo guide | Added Sections 9–16 to `presentation-demo-execution.md`: Nulled Theme (S9), PHP Hardening (S10), Redis (S11), DB Hygiene (S12), Nginx Hardening (S13), Read-Only Protections (S14), Integrity Checking (S15), Logging & Backups (S16). Updated Quick Reference Table to 16 rows. |
| 6 | Make nulled theme backdoors real/educational | `social-icons.php`: real working webshell (hex-encoded `system()` GET + base64 eval POST). `functions.php` Backdoor 1: expanded with 6 obfuscation techniques (single/double base64, gzip+base64, hex, chr(), rot13), each with decoded comment. Demo guide S9.3 updated with live curl commands. |
