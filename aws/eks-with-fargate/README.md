# aws/eks-with-fargate

Bare-minimum EKS cluster with a Fargate profile for the `apps` and `kube-system` namespaces. Targets the "small platform, no node ops" sweet spot.

## What's intentionally not here

- VNet/VPC creation — bring your own. Most EKS clusters live in a network owned by another team.
- DNS / certificate management — `external-dns` + `cert-manager` belong in the post-cluster GitOps bundle, not in cluster bootstrap Terraform.
- Add-ons (CSI drivers, Karpenter, etc.) — install via `eksctl create addon` or Argo CD once the cluster is up. Mixing cluster IaC with add-on IaC creates ugly destroy ordering problems.

## Trade-offs to know

- Fargate has **no DaemonSet support**. If your monitoring stack assumes DaemonSets, you'll need a small managed node group alongside.
- Fargate pods can't use **host networking** or **EmptyDir with `medium: Memory` over 1Gi**. Important for some sidecar-heavy patterns.
- Cold-start latency on Fargate is **~30-60s per new pod**. HPA scale-up feels slower than on EC2 node groups.

## Cost ballpark

For a small steady-state workload (5 pods × 0.5 vCPU × 1GiB) in `ap-southeast-2`: roughly USD $60-80/month for the Fargate compute + $73/month for the EKS control plane. EC2 equivalent would be ~$50/month for a single-AZ `t3.medium` + free control plane on a smaller managed group, but with all the node-patching toil.
