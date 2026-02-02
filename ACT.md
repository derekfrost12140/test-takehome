# Running the export workflow with act

[act](https://github.com/nektos/act) runs GitHub Actions locally. To get **data in the CSV** when using act:

## 1. Pass `export_date` so the query returns rows

Seed data in `init.sql` is for **2026-02-01**. The script defaults to "yesterday", which may not match when the runner’s date differs.

- Use `event.json` with `export_date` (already set to `2026-02-01`), or  
- When triggering manually: pass `-i` / workflow_dispatch input `export_date: "2026-02-01"`.

The workflow now reads `export_date` from inputs and sets `EXPORT_DATE` for the script.

## 2. Use a secrets file in .env format

act loads secrets from a file in **.env format** (`KEY=value`, one per line). Colons (`KEY: value`) are not supported.

- Copy `.secrets.example` to `.secrets` and fill in values, or  
- Ensure your `.secrets` looks like:
  ```
  CLICKHOUSE_HOST=...
  CLICKHOUSE_PORT=9000
  CLICKHOUSE_USER=exporter
  CLICKHOUSE_PASSWORD=test
  ```

Run act with: `act --secret-file .secrets`

## 3. Let the act runner reach ClickHouse

The act job runs inside a Docker container. `CLICKHOUSE_HOST=127.0.0.1` points at the container, not your host where ClickHouse runs.

- Start ClickHouse on the host, e.g. `docker compose up -d clickhouse`
- Use host gateway so the runner can reach the host:
  ```bash
  act --secret-file .secrets -s CLICKHOUSE_HOST=host.docker.internal
  ```
  or put `CLICKHOUSE_HOST=host.docker.internal` in `.secrets` when using act.

On Linux you may need:
  ```bash
  act --secret-file .secrets -s CLICKHOUSE_HOST=host.docker.internal --container-args "--add-host=host.docker.internal:host-gateway"
  ```

## Example

```bash
# ClickHouse running on host (e.g. docker compose up -d clickhouse)
# .secrets in KEY=value format; for act use CLICKHOUSE_HOST=host.docker.internal

# Use -e (event file), NOT --input. --input is for .env-style input files.
act workflow_dispatch -e event.json --secret-file .secrets
```

`event.json` includes `inputs.customer_id` and `inputs.export_date: "2026-02-01"`. Passing it with **`-e event.json`** makes act set `github.event.inputs` so the workflow gets CUSTOMER_ID and EXPORT_DATE. Using `--input event.json` would treat the file as key=value inputs and leave CUSTOMER_ID empty.
