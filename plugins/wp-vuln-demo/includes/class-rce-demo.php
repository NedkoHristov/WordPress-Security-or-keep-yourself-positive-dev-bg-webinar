<?php
/**
 * Remote Code Execution (RCE) Demo
 *
 * VULNERABILITY: eval() / system() on user input
 * FIX: Never use eval. Use safe math parsers, whitelist operations.
 */

class Vuln_RCE_Demo {

    public function __construct() {
        // Vulnerable calculator using eval()
        add_action( 'wp_ajax_vuln_calculator', [ $this, 'vulnerable_calculator' ] );
        add_action( 'wp_ajax_nopriv_vuln_calculator', [ $this, 'vulnerable_calculator' ] );

        // Fixed calculator
        add_action( 'wp_ajax_vuln_calculator_fixed', [ $this, 'fixed_calculator' ] );
        add_action( 'wp_ajax_nopriv_vuln_calculator_fixed', [ $this, 'fixed_calculator' ] );
    }

    /**
     * VULNERABLE: eval() on user-supplied math expression
     *
     * Attack examples:
     *   expression=2+2                    → Works normally: 4
     *   expression=system('id')           → RCE: shows OS user
     *   expression=system('cat /etc/passwd')   → Read system files
     *   expression=file_get_contents('/var/www/html/wp-config.php')  → Read WP config
     *   expression=system('ls -la /var/www/html/')  → List files
     */
    public function vulnerable_calculator() {
        $expression = isset( $_REQUEST['expression'] ) ? wp_unslash( $_REQUEST['expression'] ) : '';

        if ( empty( $expression ) ) {
            wp_send_json_error( 'No expression provided. Example: expression=2+2' );
        }

        // VULNERABILITY: eval() executes arbitrary PHP code
        ob_start();
        $result = @eval( "return {$expression};" );
        $output = ob_get_clean();

        wp_send_json_success( [
            'expression'    => $expression,
            'result'        => $result,
            'output'        => $output,
            'vulnerability' => 'RCE via eval() - arbitrary PHP/OS command execution',
        ] );
    }

    /**
     * FIXED: Safe calculator without eval()
     */
    public function fixed_calculator() {
        $expression = isset( $_REQUEST['expression'] ) ? $_REQUEST['expression'] : '';

        if ( empty( $expression ) ) {
            wp_send_json_error( 'No expression provided' );
        }

        // FIXED: Only allow numbers and basic math operators
        if ( ! preg_match( '/^[0-9+\-*\/\.\(\)\s]+$/', $expression ) ) {
            wp_send_json_error( 'Invalid expression. Only numbers and +, -, *, / are allowed.' );
        }

        // Simple and safe evaluation for basic math
        $tokens = preg_split( '/([\+\-\*\/])/', $expression, -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY );
        $tokens = array_map( 'trim', $tokens );

        if ( count( $tokens ) === 3 && is_numeric( $tokens[0] ) && is_numeric( $tokens[2] ) ) {
            $a  = floatval( $tokens[0] );
            $op = $tokens[1];
            $b  = floatval( $tokens[2] );

            switch ( $op ) {
                case '+': $result = $a + $b; break;
                case '-': $result = $a - $b; break;
                case '*': $result = $a * $b; break;
                case '/': $result = $b != 0 ? $a / $b : 'Division by zero'; break;
                default:  $result = 'Unknown operator'; break;
            }

            wp_send_json_success( [
                'expression' => $expression,
                'result'     => $result,
                'security'   => 'Safe parsing without eval()',
            ] );
        }

        wp_send_json_error( 'Only simple expressions like "2+2" supported in safe mode' );
    }
}
