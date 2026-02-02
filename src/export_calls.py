import csv
import os
from datetime import datetime
from clickhouse_driver import Client
import boto3
from config import CLICKHOUSE_HOST, CLICKHOUSE_PORT, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, S3_BUCKET, EXPORT_FOLDER, AWS_REGION

# Connect ClickHouse
client = Client(
    host=CLICKHOUSE_HOST,
    port=CLICKHOUSE_PORT,
    user=CLICKHOUSE_USER,
    password=CLICKHOUSE_PASSWORD
)

# Query metrics
rows = client.execute("""
SELECT 
    agent_id,
    AVG(call_duration_sec) AS avg_call_length,
    quantile(0.9)(call_duration_sec) AS p90_call_length
FROM conversations
GROUP BY agent_id
""")

today = datetime.now().strftime("%Y-%m-%d")
file_name = f"daily_export_{today}.csv"
file_path = f"./{file_name}"

# Write CSV
with open(file_path, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["agent_id", "avg_call_length", "p90_call_length"])
    for row in rows:
        writer.writerow(row)

print(f"CSV created: {file_path}")

# Upload to S3 (LocalStack)
s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:4566",
    region_name=AWS_REGION,
    aws_access_key_id="test",
    aws_secret_access_key="test",
)

# Create bucket if not exists
try:
    s3.create_bucket(Bucket=S3_BUCKET)
except:
    pass

# Upload
s3.upload_file(file_path, S3_BUCKET, f"{EXPORT_FOLDER}/{file_name}")

print(f"Uploaded to S3: s3://{S3_BUCKET}/{EXPORT_FOLDER}/{file_name}")

