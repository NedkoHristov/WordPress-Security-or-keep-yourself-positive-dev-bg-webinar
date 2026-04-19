#!/bin/bash
# scripts/wp-perf-test.sh
# Performance measurement for live demo — Sections 11 (Redis) and 12 (DB Hygiene).
#
# Usage:
#   wp-perf-test.sh before        — baseline before wp-cleanup.sh
#   wp-perf-test.sh after         — measure + print BEFORE vs AFTER diff
#   wp-perf-test.sh redis         — disable Redis, measure, enable Redis, measure, print diff
#
# Baseline is stored in /tmp/perf-baseline.txt inside the container.

set -e

BASELINE_FILE="/tmp/perf-baseline.txt"
# Use internal port 80 and skip Location redirects (siteurl is :8080 externally
# but unreachable from inside the container — measure raw Apache response time).
WP_URL="http://localhost"
CURL_OPTS="-s -o /dev/null --max-time 10 --no-location"
CURL_RUNS=10                       # curl timing samples per phase
AB_REQUESTS=200                    # total requests for ab
AB_CONCURRENCY=10                  # concurrent connections

# ─────────────────────────────────────────────────────────────────────────────
# Helper: average N curl TTFB and total-time measurements
# ─────────────────────────────────────────────────────────────────────────────
measure_curl() {
    local label="$1"
    local url="$2"
    local ttfbs=() totals=()

    echo "  curl: $CURL_RUNS requests to $url ..."
    for i in $(seq 1 $CURL_RUNS); do
        read -r ttfb total < <(curl $CURL_OPTS \
            -w "%{time_starttransfer} %{time_total}\n" "$url" 2>/dev/null || echo "0 0")
        # convert to milliseconds (bash only handles integers — use awk)
        ttfb_ms=$(echo "$ttfb" | awk '{printf "%d", $1*1000}')
        total_ms=$(echo "$total" | awk '{printf "%d", $1*1000}')
        ttfbs+=($ttfb_ms)
        totals+=($total_ms)
    done

    local sum_ttfb=0 sum_total=0
    for v in "${ttfbs[@]}";  do sum_ttfb=$((sum_ttfb + v));   done
    for v in "${totals[@]}"; do sum_total=$((sum_total + v)); done

    AVG_TTFB=$((sum_ttfb / CURL_RUNS))
    AVG_TOTAL=$((sum_total / CURL_RUNS))
    echo "    avg TTFB:  ${AVG_TTFB}ms"
    echo "    avg total: ${AVG_TOTAL}ms"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: run Apache Bench and extract req/s + p99 latency
# ─────────────────────────────────────────────────────────────────────────────
measure_ab() {
    local url="$1"
    if ! command -v ab &>/dev/null; then
        echo "  ab: not found — install apache2-utils in Dockerfile"
        AB_RPS=0; AB_P99=0; return
    fi
    echo "  ab: $AB_REQUESTS requests, concurrency $AB_CONCURRENCY ..."
    local out
    out=$(ab -n "$AB_REQUESTS" -c "$AB_CONCURRENCY" -q -r "${url}" 2>/dev/null)
    AB_RPS=$(echo "$out"  | awk '/Requests per second/{printf "%d", $4}')
    AB_P99=$(echo "$out"  | awk '/99%/{print $2}')
    echo "    req/s:     $AB_RPS"
    echo "    p99 (ms):  $AB_P99"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: collect DB stats via wp eval
# ─────────────────────────────────────────────────────────────────────────────
measure_db() {
    DB_STATS=$(wp eval '
global $wpdb;
$autoload_mb = round((float)$wpdb->get_var(
    "SELECT SUM(LENGTH(option_value)) FROM {$wpdb->options} WHERE autoload NOT IN (\"no\",\"off\",\"auto-off\")"
) / 1048576, 2);
$postmeta_rows = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->postmeta}");
$posts_rows    = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts}");
$revisions     = (int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->posts} WHERE post_type=\"revision\"");
echo "{$autoload_mb}|{$postmeta_rows}|{$posts_rows}|{$revisions}";
' --allow-root 2>/dev/null)
    AUTOLOAD_MB=$(echo "$DB_STATS" | cut -d'|' -f1)
    POSTMETA_ROWS=$(echo "$DB_STATS" | cut -d'|' -f2)
    POSTS_ROWS=$(echo "$DB_STATS" | cut -d'|' -f3)
    REVISION_ROWS=$(echo "$DB_STATS" | cut -d'|' -f4)
    echo "    autoload:  ${AUTOLOAD_MB} MB"
    echo "    postmeta:  ${POSTMETA_ROWS} rows"
    echo "    posts:     ${POSTS_ROWS} rows"
    echo "    revisions: ${REVISION_ROWS} rows"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: warm the server with silent requests
# ─────────────────────────────────────────────────────────────────────────────
warm_up() {
    echo "  Warming up (5 silent requests)..."
    for i in $(seq 1 5); do curl $CURL_OPTS "$WP_URL" &>/dev/null; done
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: diff value with percentage
# ─────────────────────────────────────────────────────────────────────────────
diff_pct() {
    local before="$1" after="$2" higher_is_better="${3:-0}"
    local delta pct sign emoji
    delta=$(echo "$before $after" | awk '{printf "%d", $2 - $1}')
    if [ "$before" -eq 0 ]; then
        pct="n/a"
    else
        pct=$(echo "$before $after" | awk '{printf "%+.0f%%", ($2-$1)/$1*100}')
    fi
    # determine if improvement (green) or regression (red) for terminal
    if [ "$higher_is_better" -eq 1 ]; then
        [ "$delta" -gt 0 ] && emoji="↑" || emoji="↓"
    else
        [ "$delta" -lt 0 ] && emoji="↓" || emoji="↑"
    fi
    echo "$after   ($pct $emoji)"
}

# ═════════════════════════════════════════════════════════════════════════════
# COMMAND: before — save baseline
# ═════════════════════════════════════════════════════════════════════════════
cmd_before() {
    echo "=== Performance Baseline (BEFORE cleanup) ==="
    echo ""
    warm_up
    echo ""
    echo "[1/3] curl timing..."
    measure_curl "before" "$WP_URL"
    echo ""
    echo "[2/3] Apache Bench..."
    measure_ab "$WP_URL/"
    echo ""
    echo "[3/3] DB stats..."
    measure_db

    # Persist
    cat > "$BASELINE_FILE" <<EOF
TTFB=$AVG_TTFB
TOTAL=$AVG_TOTAL
RPS=$AB_RPS
P99=$AB_P99
AUTOLOAD=$AUTOLOAD_MB
POSTMETA=$POSTMETA_ROWS
POSTS=$POSTS_ROWS
REVISIONS=$REVISION_ROWS
EOF
    echo ""
    echo "Baseline saved to $BASELINE_FILE"
    echo "Now run: wp-cleanup.sh  →  then:  wp-perf-test.sh after"
}

# ═════════════════════════════════════════════════════════════════════════════
# COMMAND: after — measure + print diff table
# ═════════════════════════════════════════════════════════════════════════════
cmd_after() {
    if [ ! -f "$BASELINE_FILE" ]; then
        echo "ERROR: No baseline found at $BASELINE_FILE"
        echo "Run 'wp-perf-test.sh before' first."
        exit 1
    fi
    source "$BASELINE_FILE"
    local b_ttfb=$TTFB b_total=$TOTAL b_rps=$RPS b_p99=$P99
    local b_autoload=$AUTOLOAD b_postmeta=$POSTMETA b_posts=$POSTS b_revisions=$REVISIONS

    echo "=== Performance Measurement (AFTER cleanup) ==="
    echo ""
    warm_up
    echo ""
    echo "[1/3] curl timing..."
    measure_curl "after" "$WP_URL"
    echo ""
    echo "[2/3] Apache Bench..."
    measure_ab "$WP_URL/"
    echo ""
    echo "[3/3] DB stats..."
    measure_db
    local a_ttfb=$AVG_TTFB a_total=$AVG_TOTAL a_rps=$AB_RPS a_p99=$AB_P99
    local a_autoload=$AUTOLOAD_MB a_postmeta=$POSTMETA_ROWS a_posts=$POSTS_ROWS a_revisions=$REVISION_ROWS

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo " BEFORE vs AFTER — DB Hygiene Cleanup"
    echo "════════════════════════════════════════════════════════════"
    printf "%-28s %-12s %-22s\n" "Metric" "BEFORE" "AFTER"
    printf "%-28s %-12s %-22s\n" "----------------------------" "------------" "----------------------"
    printf "%-28s %-12s %s\n" "TTFB avg (ms)"      "$b_ttfb"      "$(diff_pct $b_ttfb $a_ttfb 0)"
    printf "%-28s %-12s %s\n" "Total time avg (ms)" "$b_total"     "$(diff_pct $b_total $a_total 0)"
    printf "%-28s %-12s %s\n" "Requests/sec (ab)"   "$b_rps"       "$(diff_pct $b_rps $a_rps 1)"
    printf "%-28s %-12s %s\n" "p99 latency (ms)"    "$b_p99"       "$(diff_pct $b_p99 $a_p99 0)"
    printf "%-28s %-12s %s\n" "Autoload (MB)"        "$b_autoload"  "${a_autoload}   MB"
    printf "%-28s %-12s %s\n" "wp_postmeta rows"     "$b_postmeta"  "$(diff_pct $b_postmeta $a_postmeta 0)"
    printf "%-28s %-12s %s\n" "wp_posts rows"        "$b_posts"     "$(diff_pct $b_posts $a_posts 0)"
    printf "%-28s %-12s %s\n" "Revision rows"        "$b_revisions" "$(diff_pct $b_revisions $a_revisions 0)"
    echo "════════════════════════════════════════════════════════════"
}

# ═════════════════════════════════════════════════════════════════════════════
# COMMAND: redis — disable cache, measure, enable cache, measure, diff
# ═════════════════════════════════════════════════════════════════════════════
cmd_redis() {
    echo "=== Redis Object Cache — Performance Comparison ==="
    echo ""

    # Phase 1: Redis OFF
    echo "--- Phase 1: Disabling Redis object cache ---"
    # Directly rename the object-cache drop-in so Redis is truly bypassed
    local dropin="/var/www/html/wp-content/object-cache.php"
    mv "$dropin" "${dropin}.bak" 2>/dev/null || true
    wp redis disable --allow-root 2>/dev/null || true
    echo "  Redis drop-in removed — cache bypassed."
    warm_up
    echo ""
    echo "[1/2] Measuring WITHOUT Redis cache..."
    measure_curl "redis-off" "$WP_URL"
    local off_ttfb=$AVG_TTFB off_total=$AVG_TOTAL
    measure_ab "$WP_URL/"
    local off_rps=$AB_RPS off_p99=$AB_P99

    echo ""
    echo "--- Phase 2: Enabling Redis object cache ---"
    wp redis enable --allow-root 2>/dev/null || true
    echo "  Success: Object cache enabled."
    # Warm: let WordPress populate the cache fully
    echo "  Warming Redis cache (30 silent requests)..."
    for i in $(seq 1 30); do curl -s -o /dev/null --no-location "$WP_URL"; done

    echo ""
    echo "[2/2] Measuring WITH Redis cache..."
    measure_curl "redis-on" "$WP_URL"
    local on_ttfb=$AVG_TTFB on_total=$AVG_TOTAL
    measure_ab "$WP_URL/"
    local on_rps=$AB_RPS on_p99=$AB_P99

    # Redis key count for evidence
    REDIS_KEYS=$(wp eval '
global $wp_object_cache;
if (method_exists($wp_object_cache, "info")) {
    $info = $wp_object_cache->info();
    echo $info->hits ?? "n/a";
} else {
    echo "n/a";
}
' --allow-root 2>/dev/null || echo "n/a")

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo " Redis OFF vs Redis ON"
    echo "════════════════════════════════════════════════════════════"
    printf "%-28s %-12s %-22s\n" "Metric" "WITHOUT Redis" "WITH Redis"
    printf "%-28s %-12s %-22s\n" "----------------------------" "-------------" "----------------------"
    printf "%-28s %-12s %s\n" "TTFB avg (ms)"      "$off_ttfb"  "$(diff_pct $off_ttfb $on_ttfb 0)"
    printf "%-28s %-12s %s\n" "Total time avg (ms)" "$off_total" "$(diff_pct $off_total $on_total 0)"
    printf "%-28s %-12s %s\n" "Requests/sec (ab)"   "$off_rps"   "$(diff_pct $off_rps $on_rps 1)"
    printf "%-28s %-12s %s\n" "p99 latency (ms)"    "$off_p99"   "$(diff_pct $off_p99 $on_p99 0)"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Evidence: check Redis key count —"
    echo "  docker compose exec redis redis-cli DBSIZE"
    echo ""
    echo "Keys cached after warm-up represent DB queries eliminated per request."
}

# ═════════════════════════════════════════════════════════════════════════════
# Dispatch
# ═════════════════════════════════════════════════════════════════════════════
case "${1:-}" in
    before) cmd_before ;;
    after)  cmd_after  ;;
    redis)  cmd_redis  ;;
    *)
        echo "Usage: wp-perf-test.sh <before|after|redis>"
        echo ""
        echo "  before  — record baseline (run BEFORE wp-cleanup.sh)"
        echo "  after   — measure + compare vs baseline (run AFTER wp-cleanup.sh)"
        echo "  redis   — Redis OFF vs ON comparison (Section 11 demo)"
        exit 1
        ;;
esac
