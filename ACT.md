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

---

## Testing daily_export.yml

**Option 1 — From GitHub (easiest)**  
The workflow has `workflow_dispatch`, so you can run it without waiting for the cron:

1. Push your branch and open the repo on GitHub.
2. Go to **Actions** → **Daily Export to S3**.
3. Click **Run workflow**, choose the branch, then **Run workflow**.

It uses the **production** environment (variables and secrets). Ensure `CUSTOMER_ID` is set there; `EXPORT_DATE` is optional (script uses yesterday if empty).

**Option 2 — Locally with act**  
Run the same workflow locally (e.g. against Docker ClickHouse):

1. Start ClickHouse: `docker compose up -d clickhouse`
2. Create `.secrets` from `.secrets.example` with `CLICKHOUSE_HOST=host.docker.internal` and add `CUSTOMER_ID`, `S3_URL`, `S3_KEY`, `S3_ACCESS` if testing full export.
3. Run the daily export workflow by triggering the `schedule` event (act will run the workflow that listens to it):

   ```bash
   act schedule --secret-file .secrets -W .github/workflows/daily_export.yml
   ```

   Or list workflows and run by job name:

   ```bash
   act -l
   act -W .github/workflows/daily_export.yml -j export --secret-file .secrets
   ```

4. If your seed data uses a specific date, set `EXPORT_DATE` in `.secrets` (e.g. `EXPORT_DATE=2024-06-01`) so the query returns rows.
