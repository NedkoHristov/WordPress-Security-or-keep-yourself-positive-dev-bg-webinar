#!/bin/bash
# scripts/wp-bloat.sh
# Seeds realistic database bloat for the Section 12 DB Hygiene live demo.
# Usage: docker compose exec wordpress wp-bloat.sh

set -e

# Guard: skip if already seeded
ALREADY=$(wp eval 'global $wpdb; echo (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name LIKE \"bloat_defunct_%\"");' --allow-root 2>/dev/null || echo "0")
if [ "$ALREADY" -gt "0" ]; then
    echo "DB bloat already seeded ($ALREADY orphan options found). Run wp-cleanup.sh first to reset."
    exit 0
fi

echo "=== WordPress DB Bloat Seeder ==="
echo "Seeding realistic database bloat for Section 12 demo..."
echo "Estimated time: 30-60 seconds"
echo ""

# [1/7] Expired transients (800)
echo "[1/7] 800 expired transients..."
wp eval '
global $wpdb;
$now  = time();
$vals = [];
for ($i = 1; $i <= 800; $i++) {
    $k   = "bloat_t{$i}";
    $exp = $now - rand(3600, 7776000);
    $v   = bin2hex(random_bytes(40));
    $vals[] = "(\"_transient_timeout_{$k}\", \"{$exp}\", \"no\")";
    $vals[] = "(\"_transient_{$k}\", \"{$v}\", \"no\")";
    if (count($vals) >= 400) {
        $wpdb->query("INSERT IGNORE INTO {$wpdb->options} (option_name, option_value, autoload) VALUES " . implode(",", $vals));
        $vals = [];
    }
}
if ($vals) $wpdb->query("INSERT IGNORE INTO {$wpdb->options} (option_name, option_value, autoload) VALUES " . implode(",", $vals));
echo "  Done.\n";
' --allow-root

# [2/7] Autoloaded orphan plugin options (100 x ~50 KB = ~5 MB autoload bloat)
echo "[2/7] 100 autoloaded orphan plugin options (~50 KB each, ~5 MB total)..."
wp eval '
global $wpdb;
$blob = str_repeat("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789ab", 819); // ~51 KB
for ($i = 1; $i <= 100; $i++) {
    $name = "bloat_defunct_plugin_{$i}_options";
    $val  = addslashes(serialize(["version" => "2.4.1", "license" => "BLOAT-KEY-{$i}", "cache" => $blob]));
    $wpdb->query("INSERT IGNORE INTO {$wpdb->options} (option_name, option_value, autoload) VALUES (\"{$name}\", \"{$val}\", \"on\")");
    if ($i % 25 === 0) echo "  {$i}/100...\n";
}
echo "  Done.\n";
' --allow-root

# [3/7] Orphaned post meta (3,000 rows referencing non-existent post IDs)
echo "[3/7] 3,000 orphaned post meta rows..."
wp eval '
global $wpdb;
$keys = ["_yoast_wpseo_metadesc", "_yoast_wpseo_title", "_edit_last", "_thumbnail_id", "_wp_page_template", "_wp_old_slug"];
$vals = [];
for ($i = 1; $i <= 3000; $i++) {
    $pid    = 99000 + $i;
    $k      = $keys[$i % count($keys)];
    $vals[] = "({$pid}, \"{$k}\", \"bloat_orphan_{$i}\")";
    if (count($vals) >= 500) {
        $wpdb->query("INSERT INTO {$wpdb->postmeta} (post_id, meta_key, meta_value) VALUES " . implode(",", $vals));
        $vals = [];
    }
}
if ($vals) $wpdb->query("INSERT INTO {$wpdb->postmeta} (post_id, meta_key, meta_value) VALUES " . implode(",", $vals));
echo "  Done.\n";
' --allow-root

# [4/7] Orphaned user meta (1,500 rows referencing non-existent user IDs)
echo "[4/7] 1,500 orphaned user meta rows..."
wp eval '
global $wpdb;
$keys = ["session_tokens", "wp_capabilities", "wp_user_level", "last_update", "dismissed_wp_pointers"];
$vals = [];
for ($i = 1; $i <= 1500; $i++) {
    $uid    = 99000 + $i;
    $k      = $keys[$i % count($keys)];
    $vals[] = "({$uid}, \"{$k}\", \"bloat_user_orphan_{$i}\")";
    if (count($vals) >= 500) {
        $wpdb->query("INSERT INTO {$wpdb->usermeta} (user_id, meta_key, meta_value) VALUES " . implode(",", $vals));
        $vals = [];
    }
}
if ($vals) $wpdb->query("INSERT INTO {$wpdb->usermeta} (user_id, meta_key, meta_value) VALUES " . implode(",", $vals));
echo "  Done.\n";
' --allow-root

# [5/7] Spam comments (750)
echo "[5/7] 750 spam comments..."
wp eval '
global $wpdb;
$now    = current_time("mysql");
$names  = ["Bot McBotface", "Cheap Meds 4U", "Crypto Winner", "SEO Expert", "Free Gifts Now"];
$emails = ["bot@spam.invalid", "meds@pharma.invalid", "winner@crypto.invalid", "seo@rank.invalid", "gift@free.invalid"];
$cols   = "comment_post_ID, comment_author, comment_author_email, comment_author_url, comment_author_IP, comment_date, comment_date_gmt, comment_content, comment_karma, comment_approved, comment_agent, comment_type, comment_parent, user_id";
$vals   = [];
for ($i = 1; $i <= 750; $i++) {
    $idx    = $i % 5;
    $name   = $names[$idx];
    $em     = $emails[$idx];
    $url    = "http://spam-{$i}.invalid";
    $ip     = rand(1,254).".".rand(1,254).".".rand(1,254).".".rand(1,254);
    $body   = addslashes("Buy now! Amazing deals #{$i}. Limited time offer at {$url}");
    $vals[] = "(1, \"{$name}\", \"{$em}\", \"{$url}\", \"{$ip}\", \"{$now}\", \"{$now}\", \"{$body}\", 0, \"spam\", \"Mozilla/5.0\", \"comment\", 0, 0)";
    if (count($vals) >= 250) {
        $wpdb->query("INSERT INTO {$wpdb->comments} ({$cols}) VALUES " . implode(",", $vals));
        $vals = [];
    }
}
if ($vals) $wpdb->query("INSERT INTO {$wpdb->comments} ({$cols}) VALUES " . implode(",", $vals));
echo "  Done.\n";
' --allow-root

# [6/7] Auto-draft leftovers (250)
echo "[6/7] 250 auto-draft posts..."
wp eval '
global $wpdb;
$now  = current_time("mysql");
$cols = "post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt, post_status, comment_status, ping_status, post_password, post_name, to_ping, pinged, post_modified, post_modified_gmt, post_content_filtered, post_parent, guid, menu_order, post_type, post_mime_type, comment_count";
$vals = [];
for ($i = 1; $i <= 250; $i++) {
    $vals[] = "(1, \"{$now}\", \"{$now}\", \"\", \"\", \"\", \"auto-draft\", \"open\", \"open\", \"\", \"\", \"\", \"\", \"{$now}\", \"{$now}\", \"\", 0, \"\", 0, \"post\", \"\", 0)";
    if (count($vals) >= 50) {
        $wpdb->query("INSERT INTO {$wpdb->posts} ({$cols}) VALUES " . implode(",", $vals));
        $vals = [];
    }
}
if ($vals) $wpdb->query("INSERT INTO {$wpdb->posts} ({$cols}) VALUES " . implode(",", $vals));
echo "  Done.\n";
' --allow-root

# [7/8] 200 posts x 100 revisions = 20,000 revision rows (direct SQL — fast)
echo "[7/8] 200 posts with 100 revisions each (20,000 revision rows)..."
wp eval '
global $wpdb;
$now  = current_time("mysql");
$cols = "post_author, post_date, post_date_gmt, post_content, post_title, post_excerpt, post_status, comment_status, ping_status, post_password, post_name, to_ping, pinged, post_modified, post_modified_gmt, post_content_filtered, post_parent, guid, menu_order, post_type, post_mime_type, comment_count";

// Create 200 published posts
$post_vals = [];
for ($i = 1; $i <= 200; $i++) {
    $title      = "Bloat Post {$i}";
    $slug       = "bloat-post-{$i}";
    $body       = addslashes(str_repeat("Lorem ipsum dolor sit amet. ", 30));
    $post_vals[] = "(1, \"{$now}\", \"{$now}\", \"{$body}\", \"{$title}\", \"\", \"publish\", \"open\", \"open\", \"\", \"{$slug}\", \"\", \"\", \"{$now}\", \"{$now}\", \"\", 0, \"\", 0, \"post\", \"\", 0)";
}
foreach (array_chunk($post_vals, 50) as $chunk) {
    $wpdb->query("INSERT IGNORE INTO {$wpdb->posts} ({$cols}) VALUES " . implode(",", $chunk));
}

$post_ids = $wpdb->get_col("SELECT ID FROM {$wpdb->posts} WHERE post_name LIKE \"bloat-post-%\" ORDER BY ID");
echo "  Created/found " . count($post_ids) . " posts. Inserting revisions...\n";

// Insert 100 revisions per post in batches of 1000
$rev_vals = [];
$total    = 0;
foreach ($post_ids as $pid) {
    for ($r = 1; $r <= 100; $r++) {
        $slug       = "{$pid}-revision-v{$r}";
        $body       = addslashes("Revision {$r} for post {$pid}: " . str_repeat("edited content ", 15));
        $rev_vals[] = "(1, \"{$now}\", \"{$now}\", \"{$body}\", \"Bloat Post\", \"\", \"inherit\", \"closed\", \"closed\", \"\", \"{$slug}\", \"\", \"\", \"{$now}\", \"{$now}\", \"\", {$pid}, \"\", 0, \"revision\", \"\", 0)";
        $total++;
        if (count($rev_vals) >= 1000) {
            $wpdb->query("INSERT INTO {$wpdb->posts} ({$cols}) VALUES " . implode(",", $rev_vals));
            $rev_vals = [];
            echo "  {$total} revisions...\n";
        }
    }
}
if ($rev_vals) $wpdb->query("INSERT INTO {$wpdb->posts} ({$cols}) VALUES " . implode(",", $rev_vals));
echo "  Done. {$total} revisions for " . count($post_ids) . " posts.\n";
' --allow-root

# [8/8] WooCommerce: 10 GD placeholder images + 1,000 products + meta + 5 revisions each
echo "[8/8] WooCommerce: 10 product images + 1,000 products + 5 revisions each..."
wp eval '
if (!class_exists("WooCommerce")) { echo "  WooCommerce not active — skipping.\n"; return; }
global $wpdb;
$now = current_time("mysql");

// 8a: Generate 10 placeholder images with PHP GD (400x400 coloured JPEGs)
echo "  8a: Generating 10 product images via PHP GD...\n";
$upload_dir = wp_upload_dir();
$bloat_dir  = $upload_dir["basedir"] . "/bloat-products";
if (!is_dir($bloat_dir)) mkdir($bloat_dir, 0755, true);
$colors = [
    [255,80,80,"red"],[80,200,80,"green"],[80,80,255,"blue"],
    [255,160,40,"orange"],[180,80,255,"purple"],[80,220,220,"cyan"],
    [255,230,40,"yellow"],[255,80,180,"pink"],[80,180,255,"sky"],[160,230,80,"lime"],
];
$attachment_ids = [];
foreach ($colors as [$r,$g,$b,$label]) {
    $img  = imagecreatetruecolor(400, 400);
    $bg   = imagecolorallocate($img, $r, $g, $b);
    $fg   = imagecolorallocate($img, 255, 255, 255);
    imagefill($img, 0, 0, $bg);
    imagestring($img, 5, 155, 190, "PRODUCT", $fg);
    imagestring($img, 5, 160, 210, strtoupper($label), $fg);
    $filename = "bloat-product-{$label}.jpg";
    $filepath = "{$bloat_dir}/{$filename}";
    imagejpeg($img, $filepath, 80);
    imagedestroy($img);
    $att_id = wp_insert_attachment([
        "post_mime_type" => "image/jpeg",
        "post_title"     => "Bloat Product Image — " . ucfirst($label),
        "post_status"    => "inherit",
        "post_content"   => "",
    ], $filepath);
    update_post_meta($att_id, "_wp_attached_file", "bloat-products/{$filename}");
    update_post_meta($att_id, "_wp_attachment_metadata", serialize(["width"=>400,"height"=>400,"file"=>"bloat-products/{$filename}","sizes"=>[]]));
    update_post_meta($att_id, "_bloat_product_image", "1");
    $attachment_ids[] = $att_id;
}
echo "  " . count($attachment_ids) . " attachments created (no thumbnail generation — fast path).\n";

// 8b: Create 1,000 products via direct SQL in batches of 100
echo "  8b: Creating 1,000 products via direct SQL...\n";
$pcols = "post_author,post_date,post_date_gmt,post_content,post_title,post_excerpt,post_status,comment_status,ping_status,post_password,post_name,to_ping,pinged,post_modified,post_modified_gmt,post_content_filtered,post_parent,guid,menu_order,post_type,post_mime_type,comment_count";
$cats  = ["Electronics","Clothing","Books","Home & Garden","Toys","Sports","Beauty","Automotive","Food","Tools"];
$pvals = [];
for ($i = 1; $i <= 1000; $i++) {
    $cat   = $cats[$i % 10];
    $title = addslashes("Bloat Product {$i} — {$cat}");
    $desc  = addslashes("Detailed description for product {$i}. " . str_repeat("Sample product content for the {$cat} category. ", 5));
    $exc   = addslashes("Short description for {$cat} item #{$i}.");
    $slug  = "bloat-product-{$i}";
    $pvals[] = "(1,\"{$now}\",\"{$now}\",\"{$desc}\",\"{$title}\",\"{$exc}\",\"publish\",\"closed\",\"closed\",\"\",\"{$slug}\",\"\",\"\",\"{$now}\",\"{$now}\",\"\",0,\"\",{$i},\"product\",\"\",0)";
    if (count($pvals) >= 100) {
        $wpdb->query("INSERT IGNORE INTO {$wpdb->posts} ({$pcols}) VALUES " . implode(",", $pvals));
        $pvals = [];
        echo "    {$i}/1000...\n";
    }
}
if ($pvals) $wpdb->query("INSERT IGNORE INTO {$wpdb->posts} ({$pcols}) VALUES " . implode(",", $pvals));
echo "  1,000 products inserted.\n";

// 8c: Bulk-insert ~12 meta rows per product (~12,000 total)
echo "  8c: Bulk-inserting ~12,000 product meta rows...\n";
$product_ids = $wpdb->get_col("SELECT ID FROM {$wpdb->posts} WHERE post_name LIKE \"bloat-product-%\" AND post_type=\"product\" ORDER BY ID");
$att_count   = count($attachment_ids);
$mvals       = [];
foreach ($product_ids as $idx => $pid) {
    $price  = rand(5, 999);
    $sku    = "BLOAT-" . str_pad($idx + 1, 5, "0", STR_PAD_LEFT);
    $stock  = rand(0, 500);
    $weight = number_format(rand(1, 200) / 10, 1);
    $img_id = $attachment_ids[$idx % $att_count];
    foreach ([
        ["_price",$price],["_regular_price",$price],["_sku",$sku],
        ["_stock",$stock],["_stock_status",$stock>0?"instock":"outofstock"],
        ["_weight",$weight],["_manage_stock","yes"],["_visibility","visible"],
        ["_wc_average_rating",number_format(rand(30,50)/10,1)],
        ["_wc_review_count",rand(0,200)],
        ["_thumbnail_id",$img_id],["_bloat_product","1"],
    ] as [$mk,$mv]) {
        $mvals[] = "({$pid},\"" . addslashes($mk) . "\",\"" . addslashes($mv) . "\")";
    }
    if (count($mvals) >= 1200) {
        $wpdb->query("INSERT INTO {$wpdb->postmeta} (post_id,meta_key,meta_value) VALUES " . implode(",", $mvals));
        $mvals = [];
    }
}
if ($mvals) $wpdb->query("INSERT INTO {$wpdb->postmeta} (post_id,meta_key,meta_value) VALUES " . implode(",", $mvals));
echo "  Product meta done (" . (count($product_ids) * 12) . " rows).\n";

// 8d: 5 revisions per product via direct SQL (5,000 rows)
echo "  8d: Adding 5 revisions per product (5,000 rows)...\n";
$rvals = []; $total = 0;
foreach ($product_ids as $pid) {
    for ($r = 1; $r <= 5; $r++) {
        $slug   = "{$pid}-revision-v{$r}";
        $body   = addslashes("Revision {$r} for product {$pid}");
        $rvals[] = "(1,\"{$now}\",\"{$now}\",\"{$body}\",\"Bloat Product\",\"\",\"inherit\",\"closed\",\"closed\",\"\",\"{$slug}\",\"\",\"\",\"{$now}\",\"{$now}\",\"\",{$pid},\"\",0,\"revision\",\"\",0)";
        $total++;
        if (count($rvals) >= 500) {
            $wpdb->query("INSERT INTO {$wpdb->posts} ({$pcols}) VALUES " . implode(",", $rvals));
            $rvals = [];
        }
    }
}
if ($rvals) $wpdb->query("INSERT INTO {$wpdb->posts} ({$pcols}) VALUES " . implode(",", $rvals));
echo "  {$total} product revision rows done.\n";
echo "  WooCommerce seeding complete.\n";
' --allow-root

echo ""
echo "=== Bloat seeding complete! ==="
echo "Run the Section 12 queries to see the impact, then wp-cleanup.sh for the live fix."
