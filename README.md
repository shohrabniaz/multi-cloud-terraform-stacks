# multi-cloud-iac

Side-by-side Terraform examples for the three big clouds. Each is a small, runnable example — not a production module — meant to illustrate "what does the minimum sensible footprint look like on this provider?"

For the production AKS module, see [`aks-terraform-module`](https://github.com/shohrabniaz/aks-terraform-module). The Azure example here consumes it.

## Layout

```
multi-cloud-terraform-stacks/
├── aws/
│   ├── eks-with-fargate/         managed K8s + Fargate profile
│   ├── ecs-fargate-service/      ALB + ECS Fargate, no Kubernetes
│   └── glue-athena-etl/          S3 data lake + Glue + Athena
├── azure/
│   ├── aks-cluster/              consumes the AKS module
│   └── app-service-with-keyvault/   App Service + KV secret references
└── gcp/
    └── gke-autopilot/            managed K8s, GCP's serverless-K8s mode
```

## How to read each example

Each leaf folder has a `main.tf` you can `terraform plan` against (with appropriate provider auth + a couple of input variables). They're deliberately small: one or two responsibilities each, so the point of the example is obvious from a single file.

## Why this repo exists

CV claims like "multi-cloud experience across AWS / Azure / GCP" are weightless without code to back them. This repo is the artefact behind those claims — small, but real and reviewable.

| Folder | CV claim it maps to |
|---|---|
| `aws/glue-athena-etl/` | "Cloud Data Management & Migration (AWS Glue / Athena)" portfolio item |
| `aws/eks-with-fargate/` | "Multi-cloud experience including AWS EKS" |
| `aws/ecs-fargate-service/` | "Containerised workloads on AWS Fargate behind ALB" |
| `azure/aks-cluster/` | "Production AKS migrations" (consumes the standalone module) |
| `azure/app-service-with-keyvault/` | "Azure App Service with Key Vault integration" |
| `gcp/gke-autopilot/` | "Multi-cloud experience including GCP GKE" |

## What's missing (deliberately)

- **Networking primitives** (VPCs, VNets, subnets). Each cloud has different opinions and any real platform owns its network separately. The examples take subnet IDs / network names as inputs.
- **DNS / TLS termination**. Cloudflare or `external-dns` + `cert-manager` are post-deploy concerns.
- **State backend config.** Each example assumes you'll configure your own remote state.

## Pairs with

- [`aks-terraform-module`](https://github.com/shohrabniaz/aks-terraform-module) — production AKS module consumed by `azure/aks-cluster/`
- [`k8s-production-patterns`](https://github.com/shohrabniaz/k8s-production-patterns) — workloads to run on any of the K8s examples here
- [`cicd-pipeline-templates`](https://github.com/shohrabniaz/cicd-pipeline-templates) — pipelines to deploy them
