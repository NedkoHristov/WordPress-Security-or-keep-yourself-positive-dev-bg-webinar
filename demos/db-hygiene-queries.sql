-- ============================================
-- DB Hygiene Demo Queries
-- Run these against the WordPress database
-- ============================================

-- 1. Find bloated autoloaded options (biggest performance killer)
SELECT option_name, LENGTH(option_value) as size_bytes,
       ROUND(LENGTH(option_value)/1024, 2) as size_kb
FROM wp_options
WHERE autoload = 'yes'
ORDER BY LENGTH(option_value) DESC
LIMIT 20;

-- 2. Total autoloaded data size
SELECT ROUND(SUM(LENGTH(option_value))/1024/1024, 2) as total_autoload_mb
FROM wp_options
WHERE autoload = 'yes';

-- 3. Find expired transients (cleanup candidates)
SELECT COUNT(*) as expired_transients
FROM wp_options
WHERE option_name LIKE '_transient_timeout_%'
AND option_value < UNIX_TIMESTAMP();

-- 4. Count post revisions
SELECT COUNT(*) as total_revisions
FROM wp_posts
WHERE post_type = 'revision';

-- 5. Find orphaned postmeta
SELECT COUNT(*) as orphaned_meta
FROM wp_postmeta
WHERE post_id NOT IN (SELECT ID FROM wp_posts);

-- 6. Find spam/trash comments
SELECT comment_approved, COUNT(*) as count
FROM wp_comments
GROUP BY comment_approved;

-- 7. Table sizes
SELECT table_name,
       ROUND(data_length/1024/1024, 2) as data_mb,
       ROUND(index_length/1024/1024, 2) as index_mb,
       table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY data_length DESC;

-- ============================================
-- CLEANUP COMMANDS (use with caution!)
-- ============================================

-- Delete expired transients
-- DELETE FROM wp_options WHERE option_name LIKE '_transient_timeout_%' AND option_value < UNIX_TIMESTAMP();
-- DELETE FROM wp_options WHERE option_name LIKE '_transient_%' AND option_name NOT LIKE '_transient_timeout_%'
--   AND REPLACE(option_name, '_transient_', '_transient_timeout_') IN
--   (SELECT option_name FROM (SELECT option_name FROM wp_options WHERE option_value < UNIX_TIMESTAMP()) as t);

-- Limit revisions (add to wp-config.php):
-- define('WP_POST_REVISIONS', 3);

-- Delete old revisions:
-- DELETE FROM wp_posts WHERE post_type = 'revision' AND post_date < DATE_SUB(NOW(), INTERVAL 30 DAY);
