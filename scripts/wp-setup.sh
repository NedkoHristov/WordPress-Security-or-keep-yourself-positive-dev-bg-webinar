#!/bin/bash
set -e

echo "=== WordPress Demo Setup ==="

# Wait for wp-config.php to exist (created by WordPress entrypoint)
echo "Waiting for WordPress files..."
until [ -f /var/www/html/wp-config.php ]; do
    echo "  wp-config.php not found yet, retrying in 2s..."
    sleep 2
done
echo "WordPress files are ready!"

# Wait for database to be reachable via PHP
echo "Waiting for database connection..."
until php -r "
  mysqli_report(MYSQLI_REPORT_OFF);
  try {
    \$c = new mysqli(
      getenv('WORDPRESS_DB_HOST') ?: 'db',
      getenv('WORDPRESS_DB_USER') ?: 'wpuser',
      getenv('WORDPRESS_DB_PASSWORD') ?: 'wppassword',
      getenv('WORDPRESS_DB_NAME') ?: 'wordpress'
    );
    exit(\$c->connect_error ? 1 : 0);
  } catch (Exception \$e) {
    exit(1);
  }
" 2>/dev/null; do
    echo "  DB not ready yet, retrying in 3s..."
    sleep 3
done
echo "Database is ready!"

# Install WordPress (idempotent — safe to re-run)
wp core install \
    --url="http://localhost:8080" \
    --title="WP Security Demo" \
    --admin_user=admin \
    --admin_password=admin123 \
    --admin_email=admin@demo.local \
    --allow-root \
    --skip-email || true

# Create some test users for enumeration demos
wp user create editor editor@demo.local --role=editor --user_pass=editor123 --allow-root || true
wp user create author author@demo.local --role=author --user_pass=author123 --allow-root || true
wp user create subscriber subscriber@demo.local --role=subscriber --user_pass=Pass1234! --allow-root || true

# Activate the vulnerable demo plugin
wp plugin activate wp-vuln-demo --allow-root || true

# Install WooCommerce (pre-installed for Section 12 WooCommerce bloat demo)
wp plugin install woocommerce --activate --allow-root || true

# Install and enable Redis object cache (Section 11 Redis perf demo)
wp plugin install redis-cache --activate --allow-root || true
wp redis enable --allow-root || true

# Create demo content
wp post create --post_title="Welcome to the Security Demo" --post_content="This is a demonstration site for WordPress security testing." --post_status=publish --allow-root || true
wp post create --post_title="Confidential Data" --post_content="Secret API Key: sk-demo-12345-fake-key. Internal notes: This should not be public." --post_status=draft --allow-root || true

# Seed revision bloat demo post (for Section 12.3 DB Hygiene demo)
# Creates a draft post with 150 revisions to illustrate unchecked revision growth
wp eval '
$existing = get_posts(["post_type"=>"post","post_status"=>"draft","title"=>"Revision Bloat Demo","numberposts"=>1]);
if (!empty($existing)) { echo "Revision Bloat Demo post already exists, skipping.\n"; return; }
$post_id = wp_insert_post(["post_title"=>"Revision Bloat Demo","post_content"=>"Initial content.","post_status"=>"draft","post_author"=>1]);
for ($i = 1; $i <= 150; $i++) {
    wp_update_post(["ID"=>$post_id,"post_content"=>"Revision $i — ".str_repeat("Lorem ipsum dolor sit amet. ",10)]);
}
echo "Created Revision Bloat Demo post (ID: $post_id) with 150 revisions.\n";
' --allow-root || true

# Set permalink structure
wp rewrite structure '/%postname%/' --allow-root || true
wp rewrite flush --allow-root || true

# Fix uploads directory ownership for file upload demo
chown -R www-data:www-data /var/www/html/wp-content/uploads/ 2>/dev/null || true

echo "=== WordPress Demo Setup Complete ==="
echo ""
echo "  URL:      http://localhost:8080"
echo "  Admin:    http://localhost:8080/wp-admin"
echo "  User:     admin"
echo "  Password: admin123"
echo ""
