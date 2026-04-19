#!/bin/bash
# scripts/wp-cleanup.sh
# Cleans all DB bloat and shows a before/after summary.
# Usage: docker compose exec wordpress wp-cleanup.sh

echo "=== WordPress DB Cleanup ==="
echo ""

# ------------------------------------------------------------------ BEFORE
echo "--- BEFORE ---"
wp eval '
global $wpdb;
$autoload_mb = round((float)$wpdb->get_var("SELECT SUM(LENGTH(option_value)) FROM {$wpdb->options} WHERE autoload NOT IN (\"no\",\"off\",\"auto-off\")") / 1048576, 2);
$expired     = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name LIKE \"_transient_timeout_%\" AND option_value < " . time());
$revisions   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type = \"revision\"");
$auto_drafts = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_status = \"auto-draft\"");
$spam_coms   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->comments} WHERE comment_approved = \"spam\"");
$orphan_pm   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->postmeta} pm LEFT JOIN {$wpdb->posts} p ON pm.post_id = p.ID WHERE p.ID IS NULL");
$orphan_um   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->usermeta} um LEFT JOIN {$wpdb->users} u ON um.user_id = u.ID WHERE u.ID IS NULL");
echo "  Autoload size:       {$autoload_mb} MB\n";
echo "  Expired transients:  {$expired}\n";
echo "  Post revisions:      {$revisions}\n";
echo "  Auto-drafts:         {$auto_drafts}\n";
echo "  Spam comments:       {$spam_coms}\n";
echo "  Orphaned post meta:  {$orphan_pm}\n";
echo "  Orphaned user meta:  {$orphan_um}\n";
$wc_products = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type = \"product\" AND post_status = \"publish\"");
echo "  WooCommerce products:{$wc_products}\n";
' --allow-root

echo ""
echo "--- CLEANING ---"

# [1/7] Expired transients
echo "[1/8] Deleting expired transients..."
wp transient delete --expired --allow-root
wp eval '
global $wpdb;
$n = $wpdb->query("DELETE FROM {$wpdb->options} WHERE option_name REGEXP \"^_transient_(timeout_)?bloat_t[0-9]+$\"");
echo "  Deleted {$n} manually-seeded transient rows.\n";
' --allow-root

# [2/7] Orphaned autoloaded plugin options
echo "[2/8] Deleting orphaned autoload options..."
wp eval '
global $wpdb;
$n = $wpdb->query("DELETE FROM {$wpdb->options} WHERE option_name LIKE \"bloat_defunct_%\"");
echo "  Deleted {$n} orphaned option rows.\n";
' --allow-root

# [3/7] Orphaned post meta
echo "[3/8] Deleting orphaned post meta..."
wp eval '
global $wpdb;
$n = $wpdb->query("DELETE pm FROM {$wpdb->postmeta} pm LEFT JOIN {$wpdb->posts} p ON pm.post_id = p.ID WHERE p.ID IS NULL");
echo "  Deleted {$n} orphaned post meta rows.\n";
' --allow-root

# [4/7] Orphaned user meta
echo "[4/8] Deleting orphaned user meta..."
wp eval '
global $wpdb;
$n = $wpdb->query("DELETE um FROM {$wpdb->usermeta} um LEFT JOIN {$wpdb->users} u ON um.user_id = u.ID WHERE u.ID IS NULL");
echo "  Deleted {$n} orphaned user meta rows.\n";
' --allow-root

# [5/7] Spam comments
echo "[5/8] Deleting spam comments..."
wp eval '
global $wpdb;
$n = $wpdb->query("DELETE FROM {$wpdb->comments} WHERE comment_approved = \"spam\"");
echo "  Deleted {$n} spam comments.\n";
' --allow-root

# [6/7] Auto-drafts
echo "[6/8] Deleting auto-draft posts..."
wp eval '
global $wpdb;
$n = $wpdb->query("DELETE FROM {$wpdb->posts} WHERE post_status = \"auto-draft\"");
echo "  Deleted {$n} auto-draft posts.\n";
' --allow-root

# [7/7] All post revisions + OPTIMIZE
echo "[7/8] Deleting all revisions and optimizing tables..."
wp eval '
global $wpdb;
// Remove postmeta belonging to revision posts first
$wpdb->query("DELETE pm FROM {$wpdb->postmeta} pm INNER JOIN {$wpdb->posts} p ON pm.post_id = p.ID WHERE p.post_type = \"revision\"");
$n = $wpdb->query("DELETE FROM {$wpdb->posts} WHERE post_type = \"revision\"");
echo "  Deleted {$n} revision rows.\n";
$tables = implode(", ", [$wpdb->options, $wpdb->posts, $wpdb->postmeta, $wpdb->comments, $wpdb->commentmeta, $wpdb->usermeta]);
$wpdb->query("OPTIMIZE TABLE {$tables}");
echo "  Tables optimized (disk space reclaimed).\n";
' --allow-root

echo ""
# [8/8] WooCommerce bloat products and placeholder images
echo "[8/8] Deleting bloat WooCommerce products and images..."
wp eval '
global $wpdb;
// Delete placeholder image files + attachment posts
$att_ids = $wpdb->get_col("SELECT post_id FROM {$wpdb->postmeta} WHERE meta_key = \"_bloat_product_image\"");
if ($att_ids) {
    $bloat_dir = WP_CONTENT_DIR . "/uploads/bloat-products";
    if (is_dir($bloat_dir)) {
        foreach (glob("{$bloat_dir}/*.jpg") ?: [] as $f) unlink($f);
        rmdir($bloat_dir);
    }
    $in = implode(",", array_map("intval", $att_ids));
    $wpdb->query("DELETE FROM {$wpdb->postmeta} WHERE post_id IN ({$in})");
    $wpdb->query("DELETE FROM {$wpdb->posts} WHERE ID IN ({$in})");
    echo "  Deleted " . count($att_ids) . " placeholder image attachments.\n";
} else {
    echo "  No bloat images found.\n";
}
// Delete bloat products — identified by _bloat_product marker meta
$product_ids = $wpdb->get_col("SELECT post_id FROM {$wpdb->postmeta} WHERE meta_key = \"_bloat_product\" AND meta_value = \"1\"");
if ($product_ids) {
    $in = implode(",", array_map("intval", $product_ids));
    $wpdb->query("DELETE FROM {$wpdb->posts} WHERE post_type=\"revision\" AND post_parent IN ({$in})");
    $wpdb->query("DELETE FROM {$wpdb->postmeta} WHERE post_id IN ({$in})");
    $n = $wpdb->query("DELETE FROM {$wpdb->posts} WHERE ID IN ({$in})");
    echo "  Deleted {$n} bloat products (+ their meta and revisions).\n";
} else {
    echo "  No bloat products found.\n";
}
' --allow-root

# ------------------------------------------------------------------ AFTER
echo "--- AFTER ---"
wp eval '
global $wpdb;
$autoload_mb = round((float)$wpdb->get_var("SELECT SUM(LENGTH(option_value)) FROM {$wpdb->options} WHERE autoload NOT IN (\"no\",\"off\",\"auto-off\")") / 1048576, 2);
$expired     = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name LIKE \"_transient_timeout_%\" AND option_value < " . time());
$revisions   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type = \"revision\"");
$auto_drafts = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_status = \"auto-draft\"");
$spam_coms   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->comments} WHERE comment_approved = \"spam\"");
$orphan_pm   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->postmeta} pm LEFT JOIN {$wpdb->posts} p ON pm.post_id = p.ID WHERE p.ID IS NULL");
$orphan_um   = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->usermeta} um LEFT JOIN {$wpdb->users} u ON um.user_id = u.ID WHERE u.ID IS NULL");
echo "  Autoload size:       {$autoload_mb} MB\n";
echo "  Expired transients:  {$expired}\n";
echo "  Post revisions:      {$revisions}\n";
echo "  Auto-drafts:         {$auto_drafts}\n";
echo "  Spam comments:       {$spam_coms}\n";
echo "  Orphaned post meta:  {$orphan_pm}\n";
echo "  Orphaned user meta:  {$orphan_um}\n";
$wc_products = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type = \"product\" AND post_status = \"publish\"");
echo "  WooCommerce products:{$wc_products}\n";
' --allow-root

echo ""
echo "=== Cleanup complete! ==="
echo ""
echo "Production prevention:"
echo "  wp-config.php: define('WP_POST_REVISIONS', 3);"
echo "  wp-config.php: define('EMPTY_TRASH_DAYS', 7);"
echo "  wp-cron / WP Crontrol: wp transient delete --expired  (schedule daily)"
echo "  wp db optimize                                         (schedule weekly)"
