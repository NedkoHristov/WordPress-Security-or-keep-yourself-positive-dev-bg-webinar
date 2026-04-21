<?php
/**
 * CSRF (Cross-Site Request Forgery) Demo
 *
 * VULNERABILITY: No nonce verification on state-changing actions
 * FIX: Use wp_nonce_field() + wp_verify_nonce() or check_admin_referer()
 */

class Vuln_CSRF_Demo {

    public function __construct() {
        // Vulnerable - no nonce check
        add_action( 'wp_ajax_vuln_change_email', [ $this, 'vulnerable_change_email' ] );

        // Fixed - with nonce check
        add_action( 'wp_ajax_vuln_change_email_fixed', [ $this, 'fixed_change_email' ] );
    }

    /**
     * VULNERABLE: Change user email without CSRF protection
     *
     * Attack: Trick an authenticated admin into visiting a page with:
     *   <img src="http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_change_email&email=attacker@evil.com" />
     *
     *   Or auto-submitting form:
     *   <form action="http://localhost:8080/wp-admin/admin-ajax.php" method="POST">
     *     <input name="action" value="vuln_change_email">
     *     <input name="email" value="attacker@evil.com">
     *   </form>
     *   <script>document.forms[0].submit();</script>
     */
    public function vulnerable_change_email() {
        // VULNERABILITY: No nonce verification, no referer check
        $email = isset( $_REQUEST['email'] ) ? $_REQUEST['email'] : '';

        if ( ! empty( $email ) ) {
            $user_id = get_current_user_id();
            wp_update_user( [
                'ID'         => $user_id,
                'user_email' => $email,
            ] );

            wp_send_json_success( [
                'message'       => "Email changed to: {$email}",
                'vulnerability' => 'CSRF - No nonce verification, attacker can forge this request',
            ] );
        }

        wp_send_json_error( 'No email provided' );
    }

    /**
     * FIXED: Change email with proper CSRF protection
     */
    public function fixed_change_email() {
        // FIXED: Verify nonce before processing
        if ( ! isset( $_POST['_wpnonce'] ) || ! wp_verify_nonce( $_POST['_wpnonce'], 'vuln_change_email_action' ) ) {
            wp_send_json_error( 'Invalid security token (nonce). CSRF attack prevented!' );
        }

        $email = isset( $_POST['email'] ) ? sanitize_email( $_POST['email'] ) : '';

        if ( ! empty( $email ) && is_email( $email ) ) {
            $user_id = get_current_user_id();
            wp_update_user( [
                'ID'         => $user_id,
                'user_email' => $email,
            ] );

            wp_send_json_success( [
                'message'  => "Email changed to: {$email}",
                'security' => 'CSRF protected with WordPress nonce',
            ] );
        }

        wp_send_json_error( 'Invalid email' );
    }
}
