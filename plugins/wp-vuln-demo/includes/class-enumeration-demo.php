<?php
/**
 * Enumeration & Fingerprinting Demo
 *
 * VULNERABILITY: Exposes usernames, versions, and server information
 * FIX: Disable REST API user endpoint, remove version info, secure headers
 */

class Vuln_Enumeration_Demo {

    public function __construct() {
        // Intentionally leave these exposed for demo:
        // 1. /?author=1 redirects → reveals username (WordPress default)
        // 2. /wp-json/wp/v2/users → user listing (WordPress default)
        // 3. Generator meta tag → WordPress version

        // Add an extra vulnerable endpoint that dumps even more info
        add_action( 'wp_ajax_vuln_debug_info', [ $this, 'vulnerable_debug_info' ] );
        add_action( 'wp_ajax_nopriv_vuln_debug_info', [ $this, 'vulnerable_debug_info' ] );

        // Add a page for demonstrating mitigations
        add_action( 'wp_ajax_vuln_enum_mitigations', [ $this, 'show_mitigations' ] );
    }

    /**
     * VULNERABLE: Exposes debug/server information
     *
     * Attack: ?action=vuln_debug_info
     * Reveals PHP version, server info, loaded extensions, WP version, plugin list
     */
    public function vulnerable_debug_info() {
        // VULNERABILITY: Exposing sensitive server information to anyone
        wp_send_json_success( [
            'wordpress_version' => get_bloginfo( 'version' ),
            'php_version'       => phpversion(),
            'server_software'   => $_SERVER['SERVER_SOFTWARE'] ?? 'unknown',
            'server_os'         => php_uname(),
            'document_root'     => $_SERVER['DOCUMENT_ROOT'] ?? 'unknown',
            'loaded_extensions' => get_loaded_extensions(),
            'active_plugins'    => get_option( 'active_plugins' ),
            'active_theme'      => get_template(),
            'db_prefix'         => $GLOBALS['wpdb']->prefix,
            'abspath'           => ABSPATH,
            'wp_debug'          => defined( 'WP_DEBUG' ) && WP_DEBUG,
            'vulnerability'     => 'Information Disclosure - server fingerprinting data exposed',
        ] );
    }

    /**
     * Show enumeration mitigations code
     */
    public function show_mitigations() {
        $mitigations = [
            'disable_rest_api_users' => [
                'description' => 'Block user enumeration via REST API',
                'code'        => "add_filter('rest_endpoints', function(\$endpoints) {\n    unset(\$endpoints['/wp/v2/users']);\n    unset(\$endpoints['/wp/v2/users/(?P<id>[\\d]+)']);\n    return \$endpoints;\n});",
            ],
            'disable_author_archives' => [
                'description' => 'Block /?author=N enumeration',
                'code'        => "add_action('template_redirect', function() {\n    if (is_author()) {\n        wp_redirect(home_url(), 301);\n        exit;\n    }\n});",
            ],
            'remove_wp_version' => [
                'description' => 'Remove WordPress version from HTML and feeds',
                'code'        => "remove_action('wp_head', 'wp_generator');\nadd_filter('the_generator', '__return_empty_string');",
            ],
            'secure_login_errors' => [
                'description' => 'Generic login error messages (prevent username disclosure)',
                'code'        => "add_filter('login_errors', function() {\n    return 'Invalid credentials.';\n});",
            ],
            'security_headers' => [
                'description' => 'Add security headers',
                'code'        => "add_action('send_headers', function() {\n    header('X-Content-Type-Options: nosniff');\n    header('X-Frame-Options: SAMEORIGIN');\n    header('X-XSS-Protection: 1; mode=block');\n    header('Referrer-Policy: strict-origin-when-cross-origin');\n    header('Permissions-Policy: camera=(), microphone=(), geolocation=()');\n    header_remove('X-Powered-By');\n});",
            ],
        ];

        wp_send_json_success( $mitigations );
    }
}
