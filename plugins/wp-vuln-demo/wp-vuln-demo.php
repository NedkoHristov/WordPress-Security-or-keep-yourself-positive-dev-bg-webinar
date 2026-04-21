<?php
/**
 * Plugin Name: WP Vulnerability Demo
 * Plugin URI: https://github.com/your-repo/wp-vuln-demo
 * Description: INTENTIONALLY VULNERABLE plugin for security demonstrations. DO NOT USE IN PRODUCTION.
 * Version: 1.0.0
 * Author: Nedko Hristov
 * License: GPL v2
 *
 * ██████████████████████████████████████████████████████████
 * ██  WARNING: THIS PLUGIN IS INTENTIONALLY VULNERABLE!  ██
 * ██  DO NOT INSTALL ON ANY PRODUCTION WORDPRESS SITE!   ██
 * ██  FOR EDUCATIONAL / DEMO PURPOSES ONLY.              ██
 * ██████████████████████████████████████████████████████████
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

define( 'VULN_DEMO_VERSION', '1.0.0' );
define( 'VULN_DEMO_PATH', plugin_dir_path( __FILE__ ) );
define( 'VULN_DEMO_URL', plugin_dir_url( __FILE__ ) );

// Load vulnerability modules
require_once VULN_DEMO_PATH . 'includes/class-sqli-demo.php';
require_once VULN_DEMO_PATH . 'includes/class-xss-demo.php';
require_once VULN_DEMO_PATH . 'includes/class-csrf-demo.php';
require_once VULN_DEMO_PATH . 'includes/class-idor-demo.php';
require_once VULN_DEMO_PATH . 'includes/class-file-upload-demo.php';
require_once VULN_DEMO_PATH . 'includes/class-rce-demo.php';
require_once VULN_DEMO_PATH . 'includes/class-enumeration-demo.php';

// Initialize all vulnerable modules
add_action( 'init', 'vuln_demo_init' );

function vuln_demo_init() {
    new Vuln_SQLi_Demo();
    new Vuln_XSS_Demo();
    new Vuln_CSRF_Demo();
    new Vuln_IDOR_Demo();
    new Vuln_File_Upload_Demo();
    new Vuln_RCE_Demo();
    new Vuln_Enumeration_Demo();
}

// Add admin menu
add_action( 'admin_menu', 'vuln_demo_admin_menu' );

function vuln_demo_admin_menu() {
    add_menu_page(
        'Vulnerability Demo',
        '⚠️ Vuln Demo',
        'manage_options',
        'vuln-demo',
        'vuln_demo_admin_page',
        'dashicons-warning',
        3
    );
}

function vuln_demo_admin_page() {
    ?>
    <div class="wrap">
        <h1>⚠️ WordPress Vulnerability Demo Plugin</h1>
        <div class="notice notice-error">
            <p><strong>WARNING:</strong> This plugin contains intentional security vulnerabilities for educational demonstrations. NEVER use in production!</p>
        </div>

        <h2>Available Vulnerability Demos</h2>
        <table class="widefat">
            <thead>
                <tr>
                    <th>Vulnerability</th>
                    <th>OWASP Category</th>
                    <th>Endpoint</th>
                    <th>Description</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><strong>SQL Injection</strong></td>
                    <td>A03:2021 – Injection</td>
                    <td><code>/wp-admin/admin-ajax.php?action=vuln_search&q=</code></td>
                    <td>Unsanitized input in DB query</td>
                </tr>
                <tr>
                    <td><strong>Stored XSS</strong></td>
                    <td>A03:2021 – Injection</td>
                    <td><code>/wp-admin/admin-ajax.php?action=vuln_guestbook_submit</code></td>
                    <td>Unescaped output in guestbook</td>
                </tr>
                <tr>
                    <td><strong>Reflected XSS</strong></td>
                    <td>A03:2021 – Injection</td>
                    <td><code>/?vuln_search_page=1&q=</code></td>
                    <td>Reflected search parameter</td>
                </tr>
                <tr>
                    <td><strong>CSRF</strong></td>
                    <td>A01:2021 – Broken Access Control</td>
                    <td><code>/wp-admin/admin-ajax.php?action=vuln_change_email</code></td>
                    <td>Missing nonce verification</td>
                </tr>
                <tr>
                    <td><strong>IDOR</strong></td>
                    <td>A01:2021 – Broken Access Control</td>
                    <td><code>/wp-admin/admin-ajax.php?action=vuln_get_user&id=</code></td>
                    <td>No authorization check on user data</td>
                </tr>
                <tr>
                    <td><strong>File Upload</strong></td>
                    <td>A04:2021 – Insecure Design</td>
                    <td><code>/wp-admin/admin-ajax.php?action=vuln_upload</code></td>
                    <td>No file type validation</td>
                </tr>
                <tr>
                    <td><strong>RCE (eval)</strong></td>
                    <td>A03:2021 – Injection</td>
                    <td><code>/wp-admin/admin-ajax.php?action=vuln_calculator</code></td>
                    <td>eval() on user input</td>
                </tr>
                <tr>
                    <td><strong>User Enumeration</strong></td>
                    <td>A07:2021 – Auth Failures</td>
                    <td><code>/?author=1</code> / <code>/wp-json/wp/v2/users</code></td>
                    <td>Username disclosure</td>
                </tr>
            </tbody>
        </table>

        <h2>Guestbook (Stored XSS Demo)</h2>
        <?php vuln_demo_render_guestbook(); ?>

        <h2>Search (SQL Injection Demo)</h2>
        <form method="get" action="<?php echo admin_url('admin-ajax.php'); ?>">
            <input type="hidden" name="action" value="vuln_search">
            <input type="text" name="q" placeholder="Search users..." size="50">
            <button type="submit" class="button">Search</button>
        </form>
        <p class="description">Try: <code>1' UNION SELECT user_login,user_pass,user_email FROM wp_users-- -</code></p>

        <h2>Calculator (RCE Demo)</h2>
        <form method="post" action="<?php echo admin_url('admin-ajax.php'); ?>">
            <input type="hidden" name="action" value="vuln_calculator">
            <input type="text" name="expression" placeholder="e.g., 2+2" size="50">
            <button type="submit" class="button">Calculate</button>
        </form>
        <p class="description">Try: <code>system('id')</code></p>
    </div>
    <?php
}

function vuln_demo_render_guestbook() {
    global $wpdb;
    $table = $wpdb->prefix . 'vuln_guestbook';

    // Create table if not exists
    $wpdb->query("CREATE TABLE IF NOT EXISTS $table (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255),
        message TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");

    $entries = $wpdb->get_results("SELECT * FROM $table ORDER BY created_at DESC LIMIT 20");

    echo '<form method="post" action="' . admin_url('admin-ajax.php') . '">';
    echo '<input type="hidden" name="action" value="vuln_guestbook_submit">';
    echo '<p><input type="text" name="name" placeholder="Your name" size="30"></p>';
    echo '<p><textarea name="message" placeholder="Your message" rows="3" cols="50"></textarea></p>';
    echo '<p><button type="submit" class="button button-primary">Sign Guestbook</button></p>';
    echo '</form>';

    if ( $entries ) {
        echo '<div style="background:#f9f9f9;padding:15px;margin-top:10px;border:1px solid #ddd;">';
        foreach ( $entries as $entry ) {
            // VULNERABILITY: No output escaping - Stored XSS
            echo '<div style="margin-bottom:10px;padding:10px;background:#fff;border:1px solid #eee;">';
            echo '<strong>' . $entry->name . '</strong>';
            echo '<p>' . $entry->message . '</p>';
            echo '<small>' . $entry->created_at . '</small>';
            echo '</div>';
        }
        echo '</div>';
    }
}

// Create guestbook table on activation
register_activation_hook( __FILE__, 'vuln_demo_activate' );

function vuln_demo_activate() {
    global $wpdb;
    $table = $wpdb->prefix . 'vuln_guestbook';
    $wpdb->query("CREATE TABLE IF NOT EXISTS $table (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255),
        message TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");
}
