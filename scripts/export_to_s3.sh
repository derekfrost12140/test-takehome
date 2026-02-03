#!/bin/bash
set -e

# =============================================================================
# ClickHouse S3 Export Script
# Exports daily agent metrics (avg and p90 call duration) to S3
# =============================================================================

# Required environment variables
if [ -z "$CUSTOMER_ID" ]; then echo "Error: CUSTOMER_ID is required"; exit 1; fi
if [ -z "$CLICKHOUSE_USER" ]; then echo "Error: CLICKHOUSE_USER is required"; exit 1; fi
if [ -z "$CLICKHOUSE_PASSWORD" ]; then echo "Error: CLICKHOUSE_PASSWORD is required"; exit 1; fi
if [ -z "$S3_URL" ]; then echo "Error: S3_URL is required (bucket base URL, e.g. https://bucket.s3.region.amazonaws.com)"; exit 1; fi
if [ -z "$S3_KEY" ] || [ -z "$S3_ACCESS" ]; then echo "Error: S3_KEY and S3_ACCESS (AWS credentials) are required"; exit 1; fi

# Defaults
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-9000}"
# Use --secure for ClickHouse Cloud (port 9440). Set to 1 when using ClickHouse Cloud.
CLICKHOUSE_SECURE="${CLICKHOUSE_SECURE:-}"
NAMED_COLLECTION="${NAMED_COLLECTION:-aws_production_s3}"
EXPORT_PATH="${EXPORT_PATH:-exports}"
EXPORT_DATE="${EXPORT_DATE:-}"
S3_URL="${S3_URL:-}"
S3_KEY="${S3_KEY:-}"
S3_ACCESS="${S3_ACCESS:-}"

# Date logic (yesterday if not provided)
if [ -z "$EXPORT_DATE" ]; then
    EXPORT_DATE=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
fi

# Timestamp for unique filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Export date as folder path yyyy/mm/dd (e.g. 2026-02-01 -> 2026/02/01)
EXPORT_DATE_PATH="${EXPORT_DATE//-/\/}"

# Final path: exports/customer_<id>/yyyy/mm/dd/<timestamp>.csv
FILE_PATH="${EXPORT_PATH}/customer_${CUSTOMER_ID}/${EXPORT_DATE_PATH}/${TIMESTAMP}.csv"

# Full S3 URL: s3() requires the complete path including filename
# S3_URL is the bucket base (e.g. https://bucket.s3.region.amazonaws.com or https://bucket.s3.region.amazonaws.com/prefix/)
S3_BASE="${S3_URL%/}"
S3_FULL_URL="${S3_BASE}/${FILE_PATH}"

echo "============================================="
echo "Daily Agent Metrics Export"
echo "Customer ID: ${CUSTOMER_ID}"
echo "Export Date (filtering): ${EXPORT_DATE}"
echo "Output File: ${FILE_PATH}"
echo "Full S3 URL: ${S3_FULL_URL}"
echo "============================================="

# Build the query (single line for reliable execution with clickhouse-client)
# s3() requires full URL with path and filename
QUERY="INSERT INTO FUNCTION s3('${S3_FULL_URL}', '${S3_KEY}', '${S3_ACCESS}', 'CSVWithNames') SELECT agent_id, toDate(call_start) AS report_date, count() AS total_calls, round(avg(call_duration_sec), 2) AS avg_call_duration_sec, round(quantile(0.9)(call_duration_sec), 2) AS p90_call_duration_sec FROM cresta.conversations WHERE customer_id = '${CUSTOMER_ID}' AND toDate(call_start) = toDate('${EXPORT_DATE}') GROUP BY agent_id, toDate(call_start) ORDER BY agent_id"

# Log the query (pretty-printed for readability)
echo "============================================="
echo "🔍 INSERT + SELECT QUERY TO BE EXECUTED"
echo "---------------------------------------------"
echo "INSERT INTO FUNCTION s3('${S3_FULL_URL}', '...', '...', 'CSVWithNames')"
echo "SELECT agent_id, toDate(call_start) AS report_date, count() AS total_calls, round(avg(call_duration_sec), 2) AS avg_call_duration_sec, round(quantile(0.9)(call_duration_sec), 2) AS p90_call_duration_sec FROM cresta.conversations WHERE customer_id = '${CUSTOMER_ID}' AND toDate(call_start) = toDate('${EXPORT_DATE}') GROUP BY agent_id, toDate(call_start) ORDER BY agent_id"
echo "File path: ${FILE_PATH}"
echo "---------------------------------------------"
echo "============================================="

# Build clickhouse-client args (--secure required for ClickHouse Cloud on port 9440)
CLICKHOUSE_ARGS=(
  --host "${CLICKHOUSE_HOST}"
  --port "${CLICKHOUSE_PORT}"
  --user "${CLICKHOUSE_USER}"
  --password "${CLICKHOUSE_PASSWORD}"
  --query "${QUERY}"
)
if [ -n "${CLICKHOUSE_SECURE}" ]; then
  CLICKHOUSE_ARGS+=(--secure)
fi

# Execute the query
clickhouse-client "${CLICKHOUSE_ARGS[@]}"

echo "============================================="
echo "✅ Export completed successfully!"
echo "File: ${FILE_PATH}"
echo "============================================="
