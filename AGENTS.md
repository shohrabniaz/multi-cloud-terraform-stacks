# AGENTS.md

## Cursor Cloud specific instructions

This is a **Terraform IaC portfolio repository** — there is no running application server or database. The development workflow is purely validation-based.

### Tool requirement

- **Terraform >= 1.6.0 and < 1.8.0** (installed at `/usr/local/bin/terraform`). Versions 1.8+ reject the comma-separated single-line variable syntax used in 3 of the 6 example files.

### Validation commands

Each leaf directory under `aws/`, `azure/`, `gcp/` is an independent Terraform root module. To validate:

```bash
cd <example-dir>
terraform init -backend=false
terraform validate
```

### Known pre-existing issues

Three files use invalid HCL2 comma syntax in single-line variable blocks (e.g. `{ type = number, default = 8080 }`):
- `aws/ecs-fargate-service/main.tf`
- `azure/aks-cluster/main.tf`
- `azure/app-service-with-keyvault/main.tf`

These fail `terraform init` on ANY Terraform version (HCL2 has never supported commas between block attributes). The other 3 examples (`aws/eks-with-fargate`, `aws/glue-athena-etl`, `gcp/gke-autopilot`) init and validate cleanly.

### Lint

```bash
terraform fmt -check -recursive .
```

Note: exits non-zero if files need formatting. Will also error on the 3 files with invalid syntax. The 3 valid examples show minor alignment diffs only.

### No cloud credentials needed for local validation

`terraform init -backend=false` + `terraform validate` works without cloud provider credentials. `terraform plan` / `terraform apply` require real AWS / Azure / GCP accounts and would provision billable resources.

### azure/aks-cluster note

This example downloads a module from GitHub (`git::https://github.com/shohrabniaz/aks-terraform-module.git`). `terraform init` requires network access. It will also fail due to the comma syntax issue in `main.tf`.
