# aws/glue-athena-etl

Reference Terraform for an S3-based data lake with Glue + Athena. Matches the cloud-data-migration project on my CV and portfolio.

## What this gives you

- An encrypted, versioned S3 bucket with the standard `raw/` → `curated/` zones
- Lifecycle rules that move raw partitions to Glacier-IR after 90 days
- A Glue crawler that auto-detects schema from `raw/` every 6 hours
- A Glue ETL job slot pointing at `scripts/etl.py` in the same bucket
- An Athena workgroup with KMS-encrypted query results and a 10 GiB per-query cap (kills runaway queries before they get expensive)

## What this deliberately doesn't include

- **The ETL script itself.** Keep job logic in a separate repo with its own tests, upload to `s3://${bucket}/scripts/etl.py` from CI. Terraform shouldn't ship Python.
- **Source connectors / Lambda triggers.** Whoever owns the raw data drops it in `s3://${bucket}/raw/<source>/year=YYYY/month=MM/day=DD/...` — that contract is more durable than Terraform-managed event wiring.
- **Lake Formation tag-based access control.** Worth adding for multi-team setups but adds significant complexity; out of scope for a starter example.

## Cost notes

- Glue jobs bill per DPU-hour. G.1X × 5 workers × 60-min cap ≈ USD $2.20 per run worst-case.
- Athena bills per TB scanned. The 10 GiB-per-query cap is a hard guard against forgotten queries — bump it deliberately, not by accident.
- S3 KMS adds ~$0.03 per 10k requests on top of standard S3. Negligible for analytics workloads.

## Pairs well with

- [`cicd-pipeline-templates`](https://github.com/shohrabniaz/cicd-pipeline-templates) for the ETL-script repo's CI (lint + unit test + S3 upload on tag).
