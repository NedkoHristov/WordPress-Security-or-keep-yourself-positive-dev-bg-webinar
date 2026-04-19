<?php
/**
 * IDOR (Insecure Direct Object Reference) Demo
 *
 * VULNERABILITY: No authorization check - any user can access any user's data
 * FIX: Check current_user_can() and verify user owns the resource
 */

class Vuln_IDOR_Demo {

    public function __construct() {
        // Vulnerable - no authz check
        add_action( 'wp_ajax_vuln_get_user', [ $this, 'vulnerable_get_user' ] );
        add_action( 'wp_ajax_nopriv_vuln_get_user', [ $this, 'vulnerable_get_user' ] );

        // Vulnerable - draft post exposure
        add_action( 'wp_ajax_vuln_get_post', [ $this, 'vulnerable_get_post' ] );
        add_action( 'wp_ajax_nopriv_vuln_get_post', [ $this, 'vulnerable_get_post' ] );

        // Fixed version
        add_action( 'wp_ajax_vuln_get_user_fixed', [ $this, 'fixed_get_user' ] );
    }

    /**
     * VULNERABLE: Access any user's data by changing the ID parameter
     *
     * Attack: Iterate through IDs to dump all users:
     *   ?action=vuln_get_user&id=1
     *   ?action=vuln_get_user&id=2
     *   ?action=vuln_get_user&id=3
     */
    public function vulnerable_get_user() {
        $user_id = isset( $_GET['id'] ) ? intval( $_GET['id'] ) : 0;

        // VULNERABILITY: No check if current user is authorized to view this data
        $user = get_userdata( $user_id );

        if ( $user ) {
            wp_send_json_success( [
                'id'            => $user->ID,
                'login'         => $user->user_login,
                'email'         => $user->user_email,
                'display_name'  => $user->display_name,
                'role'          => implode( ', ', $user->roles ),
                'registered'    => $user->user_registered,
                'vulnerability' => 'IDOR - No authorization check. Any visitor can enumerate all users.',
            ] );
        }

        wp_send_json_error( 'User not found' );
    }

    /**
     * VULNERABLE: Access any post including drafts and private posts
     *
     * Attack: ?action=vuln_get_post&id=5  (draft with secrets)
     */
    public function vulnerable_get_post() {
        $post_id = isset( $_GET['id'] ) ? intval( $_GET['id'] ) : 0;

        // VULNERABILITY: No check on post_status or ownership
        $post = get_post( $post_id );

        if ( $post ) {
            wp_send_json_success( [
                'id'            => $post->ID,
                'title'         => $post->post_title,
                'content'       => $post->post_content,
                'status'        => $post->post_status,
                'author'        => get_the_author_meta( 'user_login', $post->post_author ),
                'vulnerability' => 'IDOR - Exposes drafts and private posts without authorization',
            ] );
        }

        wp_send_json_error( 'Post not found' );
    }

    /**
     * FIXED: Proper authorization check
     */
    public function fixed_get_user() {
        // FIXED: Only admins can view other users, regular users can only view themselves
        if ( ! is_user_logged_in() ) {
            wp_send_json_error( 'Authentication required' );
        }

        $user_id = isset( $_GET['id'] ) ? intval( $_GET['id'] ) : 0;
        $current_user_id = get_current_user_id();

        // Only allow viewing own profile, unless admin
        if ( $user_id !== $current_user_id && ! current_user_can( 'list_users' ) ) {
            wp_send_json_error( 'Unauthorized: You can only view your own profile' );
        }

        $user = get_userdata( $user_id );

        if ( $user ) {
            wp_send_json_success( [
                'id'           => $user->ID,
                'display_name' => $user->display_name,
                'security'     => 'Authorization check enforced',
            ] );
        }

        wp_send_json_error( 'User not found' );
    }
}
