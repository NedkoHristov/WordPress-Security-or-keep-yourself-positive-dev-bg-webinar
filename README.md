# Actually Secure Your WordPress (or Keep Yourself Positive)

> DEV.BG Cyber Security User Group — 20.04.2026  
> Speaker: Nedko Hristov, Senior DevOps Engineer @ Nemetschek Bulgaria

## Main Reference

**[`presentation-demo-execution.md`](presentation-demo-execution.md)** — the primary guide for running all 16 demo sections. Covers every attack command, expected output, talking points, and section reset commands. Start here.

## Quick Start

```bash
# 1. Build and start the core stack
docker compose up -d --build

# 2. Run the setup script — installs WordPress, creates demo users,
#    activates plugins (wp-vuln-demo, WooCommerce, Redis Object Cache),
#    seeds demo content and revision bloat for Section 12
docker compose exec wordpress wp-setup.sh

# 3. Open WordPress
open http://localhost:8080           # Frontend
open http://localhost:8080/wp-admin  # Admin panel — user: admin / admin123

# 4. (Optional) Start attacker tools — WPScan scanner + Flask C2 server
#    Required for Sections 3 (XSS/cookie theft) and 8 (WPScan)
docker compose --profile tools up -d

# 5. Open attacker C2 dashboard
open http://localhost:9090
```

> The setup script is idempotent — safe to re-run. It handles everything including WooCommerce and Redis Object Cache activation.

### Seed demo bloat and record the baseline (Section 12)

```bash
# Seed all 8 bloat categories (25 000+ revisions, 1 000 WooCommerce products,
# 800 transients, 750 spam comments, 4 500 orphaned meta rows, …)
docker compose exec wordpress wp-bloat.sh

# Record the "before" performance baseline
docker compose exec wordpress wp-perf-test.sh before
```

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Browser    │────▶│  WordPress   │────▶│    MySQL     │
│              │     │  (Apache)    │     │    8.0       │
│              │     │  :8080       │     │              │
└──────────────┘     └──────┬───────┘     └──────────────┘
                            │
                     ┌──────▼───────┐
                     │    Redis     │
                     │ (obj cache)  │
                     └──────────────┘

┌──────────────┐     ┌──────────────┐
│   WPScan     │     │  Attacker    │
│  (scanner)   │     │  C2 Server   │
│  profile:    │     │  :9090       │
│  tools       │     │  profile:    │
└──────────────┘     │  tools       │
                     └──────────────┘
```

## What's Included

### Vulnerable Demo Plugin (`wp-vuln-demo`)

| Vulnerability | OWASP | Endpoint | Fix Endpoint |
|---|---|---|---|
| SQL Injection | A03:2021 | `?action=vuln_search&q=` | `?action=vuln_search_fixed&q=` |
| Stored XSS | A03:2021 | `?action=vuln_guestbook_submit` | — |
| Reflected XSS | A03:2021 | `/?vuln_search_page=1&q=` | — |
| CSRF | A01:2021 | `?action=vuln_change_email` | `?action=vuln_change_email_fixed` |
| IDOR | A01:2021 | `?action=vuln_get_user&id=` | `?action=vuln_get_user_fixed` |
| File Upload | A04:2021 | `?action=vuln_upload` | `?action=vuln_upload_fixed` |
| RCE (eval) | A03:2021 | `?action=vuln_calculator` | `?action=vuln_calculator_fixed` |
| Enumeration | A07:2021 | `?action=vuln_debug_info` | — |

### Nulled Theme Demo (`nulled-theme-demo`)

Demonstrates 3 types of backdoors found in pirated themes and a live webshell:
1. Obfuscated `eval()` disguised as a license-key check
2. Hidden admin account auto-creation on every `init`
3. Phone-home / data exfiltration to attacker C2
4. Webshell hidden in `social-icons.php` — directly web-accessible, no WordPress bootstrap required

### Security Hardened Plugin (`wp-security-hardened`)

Activate this plugin to demonstrate the "after" state:
- Disables REST API user enumeration
- Removes version info from HTML
- Adds security headers (CSP, X-Frame-Options, etc.)
- Generic login error messages
- Disables XML-RPC
- Logs failed login attempts to `wp-content/debug.log`

### Config Comparisons

| File | Purpose |
|---|---|
| `config/php-demo.ini` | Insecure PHP settings (default for demos) |
| `config/php-hardened.ini` | Hardened settings — `disable_functions`, `open_basedir`, `HttpOnly` cookies |
| `config/nginx-hardened.conf` | Rate limiting, block PHP in uploads, security headers, CSP |

## WPScan

Add your own API token to `docker-compose.yml` under the `wpscan` service (`WPSCAN_API_TOKEN`) to get CVE lookups against the WPScan vulnerability database.

```bash
# Enumerate users, vulnerable plugins and themes
docker compose --profile tools run --rm wpscan \
  --url http://wordpress \
  --force \
  --enumerate u,vp,vt \
  --no-banner

# Brute-force passwords for enumerated users
docker compose --profile tools run --rm wpscan \
  --url http://wordpress \
  --force \
  --enumerate u \
  --passwords /tmp/passwords.txt \
  --no-banner
```

> `--force` is required because WordPress's `siteurl` is `http://localhost:8080` — WPScan follows the redirect to a host unreachable from inside Docker and otherwise aborts. `--force` skips that detection check.

## Reset Commands

```bash
# Reset guestbook (Section 3 — stored XSS)
docker compose exec wordpress wp eval 'global $wpdb; $wpdb->query("TRUNCATE TABLE wp_vuln_guestbook");' --allow-root

# Clear attacker C2 loot (Section 3)
docker compose exec attacker bash -c 'echo "[]" > /app/loot.json'

# Delete uploaded webshell (Section 6)
docker compose exec wordpress rm -f /tmp/shell.php /var/www/html/wp-content/uploads/vuln-demo/shell.php

# Restore tampered core file (Section 15)
docker compose exec wordpress wp core download --force --allow-root

# Remove read-only constants set in Section 14
docker compose exec wordpress wp config delete DISALLOW_FILE_EDIT --allow-root || true
docker compose exec wordpress wp config delete DISALLOW_FILE_MODS --allow-root || true

# Full reset — wipe everything and rebuild from scratch
docker compose down -v && docker compose up -d --build
docker compose exec wordpress wp-setup.sh
docker compose exec wordpress wp-bloat.sh
docker compose exec wordpress wp-perf-test.sh before
```

## File Structure

```
.
├── docker-compose.yml                  # Core stack + attacker tools (profile: tools)
├── Dockerfile.wordpress                # WordPress image with WP-CLI, Redis, scripts
├── Dockerfile.attacker                 # Python Flask C2 server
├── presentation-demo-execution.md      # ★ Main demo guide — start here
├── PRESENTATION_OUTLINE.md             # Full talk outline
├── README.md                           # This file
├── config/
│   ├── php-demo.ini                    # Insecure PHP config (default)
│   ├── php-hardened.ini                # Hardened PHP config (Section 10)
│   └── nginx-hardened.conf             # Hardened Nginx config (Section 13)
├── plugins/
│   ├── wp-vuln-demo/                   # Intentionally vulnerable plugin
│   │   ├── wp-vuln-demo.php
│   │   └── includes/
│   │       ├── class-sqli-demo.php
│   │       ├── class-xss-demo.php
│   │       ├── class-csrf-demo.php
│   │       ├── class-idor-demo.php
│   │       ├── class-file-upload-demo.php
│   │       ├── class-rce-demo.php
│   │       └── class-enumeration-demo.php
│   └── wp-security-hardened/           # Hardening plugin — the "after" state
│       └── wp-security-hardened.php
├── themes/
│   └── nulled-theme-demo/              # Simulated backdoored nulled theme
│       ├── functions.php               # 3 backdoor types (obfuscated eval, hidden admin, exfil)
│       ├── style.css
│       ├── index.php
│       └── social-icons.php            # Live webshell — web-accessible, no auth
├── demos/
│   ├── attack-playbook.sh              # Condensed attack command reference
│   ├── csrf-attack.html                # CSRF attack page (Section 4)
│   ├── passwords.txt                   # Wordlist for WPScan brute-force (Section 8)
│   └── db-hygiene-queries.sql          # Full set of DB hygiene queries (Section 12)
└── scripts/
    ├── wp-setup.sh                     # WordPress install + demo content seeding
    ├── wp-bloat.sh                     # Seeds 8 categories of DB bloat (Section 12)
    ├── wp-cleanup.sh                   # Runs all hygiene fixes, prints before/after
    ├── wp-perf-test.sh                 # TTFB benchmark — before/after/redis modes
    └── attacker_server.py              # Flask C2 server — /steal, /exfil, /loot endpoints
```

## Disclaimer

**This project is for EDUCATIONAL PURPOSES ONLY.** All vulnerabilities are intentional and designed for controlled demonstration in an isolated Docker environment. Never deploy this on a public network or production server.

## License

MIT — Use freely for educational purposes.
