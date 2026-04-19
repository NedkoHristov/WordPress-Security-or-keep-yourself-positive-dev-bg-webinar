<?php
/**
 * Plugin Name: WP Security Hardened
 * Description: Demonstrates proper WordPress security hardening. Activate this to show the "after" state.
 * Version: 1.0.0
 * Author: Nedko Hristov
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// =============================================================
// 1. DISABLE USER ENUMERATION
// =============================================================

// Block REST API user endpoint
add_filter( 'rest_endpoints', function( $endpoints ) {
    unset( $endpoints['/wp/v2/users'] );
    unset( $endpoints['/wp/v2/users/(?P<id>[\d]+)'] );
    return $endpoints;
});

// Block author archive enumeration
add_action( 'template_redirect', function() {
    if ( is_author() ) {
        wp_redirect( home_url(), 301 );
        exit;
    }
});

// =============================================================
// 2. REMOVE VERSION INFORMATION
// =============================================================

// Remove WP version from head
remove_action( 'wp_head', 'wp_generator' );
add_filter( 'the_generator', '__return_empty_string' );

// Remove version from scripts and styles
add_filter( 'style_loader_src', 'hardened_remove_version_query', 10, 2 );
add_filter( 'script_loader_src', 'hardened_remove_version_query', 10, 2 );

function hardened_remove_version_query( $src ) {
    if ( strpos( $src, 'ver=' ) ) {
        $src = remove_query_arg( 'ver', $src );
    }
    return $src;
}

// =============================================================
// 3. SECURITY HEADERS
// =============================================================

add_action( 'send_headers', function() {
    header( 'X-Content-Type-Options: nosniff' );
    header( 'X-Frame-Options: SAMEORIGIN' );
    header( 'X-XSS-Protection: 1; mode=block' );
    header( 'Referrer-Policy: strict-origin-when-cross-origin' );
    header( 'Permissions-Policy: camera=(), microphone=(), geolocation=()' );
    header_remove( 'X-Powered-By' );
});

// =============================================================
// 4. SECURE LOGIN
// =============================================================

// Generic login error message
add_filter( 'login_errors', function() {
    return 'Invalid credentials. Please try again.';
});

// Disable XML-RPC (common brute-force vector)
add_filter( 'xmlrpc_enabled', '__return_false' );

// Remove XML-RPC from head
remove_action( 'wp_head', 'rsd_link' );

// =============================================================
// 5. DISABLE FILE EDITOR
// =============================================================

if ( ! defined( 'DISALLOW_FILE_EDIT' ) ) {
    define( 'DISALLOW_FILE_EDIT', true );
}

// =============================================================
// 6. BLOCK PHP EXECUTION IN UPLOADS
// =============================================================

add_action( 'init', function() {
    $htaccess = WP_CONTENT_DIR . '/uploads/.htaccess';
    $rules    = "<Files *.php>\nDeny from all\n</Files>";

    if ( ! file_exists( $htaccess ) ) {
        @file_put_contents( $htaccess, $rules );
    }
});

// =============================================================
// 7. ADMIN AREA PROTECTIONS
// =============================================================

// Log all login attempts
add_action( 'wp_login_failed', function( $username ) {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    error_log( "[SECURITY] Failed login for '{$username}' from IP: {$ip}" );
});

add_action( 'wp_login', function( $user_login, $user ) {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    error_log( "[SECURITY] Successful login for '{$user_login}' from IP: {$ip}" );
}, 10, 2 );

// =============================================================
// 8. CONTENT SECURITY POLICY (Basic)
// =============================================================

// Note: CSP should be tailored per site. This is a starting point.
add_action( 'send_headers', function() {
    // Only set CSP on frontend, not admin (admin needs inline scripts)
    if ( ! is_admin() ) {
        header( "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-ancestors 'self';" );
    }
}, 20 );
