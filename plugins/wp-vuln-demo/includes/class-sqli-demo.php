<?php
/**
 * SQL Injection Demo
 *
 * VULNERABILITY: Direct string concatenation in SQL queries
 * FIX: Use $wpdb->prepare() with parameterized queries
 */

class Vuln_SQLi_Demo {

    public function __construct() {
        // Vulnerable endpoint (no auth required for demo)
        add_action( 'wp_ajax_vuln_search', [ $this, 'vulnerable_search' ] );
        add_action( 'wp_ajax_nopriv_vuln_search', [ $this, 'vulnerable_search' ] );

        // Fixed endpoint for comparison
        add_action( 'wp_ajax_vuln_search_fixed', [ $this, 'fixed_search' ] );
        add_action( 'wp_ajax_nopriv_vuln_search_fixed', [ $this, 'fixed_search' ] );
    }

    /**
     * VULNERABLE: SQL Injection via unsanitized user input
     *
     * Attack examples:
     *   ?action=vuln_search&q=1' UNION SELECT user_login,user_pass,user_email FROM wp_users-- -
     *   ?action=vuln_search&q=1' OR '1'='1
     *   ?action=vuln_search&q=1'; DROP TABLE wp_posts;-- -
     */
    public function vulnerable_search() {
        global $wpdb;

        // wp_unslash is commonly used by developers to undo WordPress magic quotes
        // This is what makes it injectable — the raw unslashed input goes into the query
        $search = isset( $_GET['q'] ) ? wp_unslash( $_GET['q'] ) : '';

        // VULNERABILITY: Direct concatenation - NO sanitization, NO prepared statement
        $query = "SELECT ID, post_title, post_content FROM {$wpdb->posts} WHERE post_title LIKE '%{$search}%' AND post_status = 'publish'";

        $results = $wpdb->get_results( $query );

        header( 'Content-Type: application/json' );
        echo json_encode( [
            'query_executed' => $query, // Exposing the query for demo visibility
            'results'        => $results,
            'vulnerability'  => 'SQL Injection - unsanitized input concatenated into SQL query',
        ] );
        wp_die();
    }

    /**
     * FIXED: Using $wpdb->prepare() for parameterized queries
     */
    public function fixed_search() {
        global $wpdb;

        $search = isset( $_GET['q'] ) ? sanitize_text_field( $_GET['q'] ) : '';

        // FIXED: Using prepare() with proper placeholder
        $query = $wpdb->prepare(
            "SELECT ID, post_title FROM {$wpdb->posts} WHERE post_title LIKE %s AND post_status = 'publish'",
            '%' . $wpdb->esc_like( $search ) . '%'
        );

        $results = $wpdb->get_results( $query );

        header( 'Content-Type: application/json' );
        echo json_encode( [
            'results'  => $results,
            'security' => 'Query uses $wpdb->prepare() with parameterized placeholders',
        ] );
        wp_die();
    }
}
