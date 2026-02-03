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

# Final filename: exports/customer_<id>/yyyy/mm/dd/<timestamp>.csv
FILENAME="${EXPORT_PATH}/customer_${CUSTOMER_ID}/${EXPORT_DATE_PATH}/${TIMESTAMP}.csv"

echo "============================================="
echo "Daily Agent Metrics Export"
echo "Customer ID: ${CUSTOMER_ID}"
echo "Export Date (filtering): ${EXPORT_DATE}"
echo "Output File: ${FILENAME}"
echo "============================================="

# Build the query (single line for reliable execution with clickhouse-client)
# Use default.conversations explicitly; s3() uses key=value without spaces per ClickHouse docs
QUERY="INSERT INTO FUNCTION s3('${S3_URL}', '${S3_KEY}', '${S3_ACCESS}' , 'CSV') SELECT agent_id, toDate(call_start) AS report_date, count() AS total_calls, round(avg(call_duration_sec), 2) AS avg_call_duration_sec, round(quantile(0.9)(call_duration_sec), 2) AS p90_call_duration_sec FROM cresta.conversations WHERE customer_id = '${CUSTOMER_ID}' AND toDate(call_start) = toDate('${EXPORT_DATE}') GROUP BY agent_id, toDate(call_start) ORDER BY agent_id"

# Log the query (pretty-printed for readability)
echo "============================================="
echo "🔍 INSERT + SELECT QUERY TO BE EXECUTED"
echo "---------------------------------------------"
echo "INSERT INTO FUNCTION s3('${S3_URL}', '${S3_KEY}', '${S3_ACCESS}' , 'CSV')"
echo "SELECT agent_id, toDate(call_start) AS report_date, count() AS total_calls, round(avg(call_duration_sec), 2) AS avg_call_duration_sec, round(quantile(0.9)(call_duration_sec), 2) AS p90_call_duration_sec FROM cresta.conversations WHERE customer_id = '${CUSTOMER_ID}' AND toDate(call_start) = toDate('${EXPORT_DATE}') GROUP BY agent_id, toDate(call_start) ORDER BY agent_id"
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
echo "File: ${FILENAME}"
echo "============================================="
