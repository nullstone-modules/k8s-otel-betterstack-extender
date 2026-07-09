// This extender creates its config maps in the SAME cluster-namespace the OpenTelemetry collector
// deploys into, so the collector can mount each fragment. The collector enforces the namespace match
// at plan time (it compares its namespace to this module's `kubernetes_namespace` output).
//
// The connection contract is provider-wildcarded so this single module works against both a GKE
// cluster-namespace (`cluster-namespace/gcp/k8s:gke`) and an EKS one (`cluster-namespace/aws/k8s:eks`).
data "ns_connection" "cluster_namespace" {
  name     = "cluster-namespace"
  contract = "cluster-namespace/*/k8s:*"
}

locals {
  // EKS cluster-namespaces expose `cluster_arn`/`cluster_name`; GKE ones do not. Use that to branch.
  is_aws = try(data.ns_connection.cluster_namespace.outputs.cluster_arn, null) != null
  is_gcp = !local.is_aws

  kubernetes_namespace   = data.ns_connection.cluster_namespace.outputs.kubernetes_namespace
  cluster_endpoint       = data.ns_connection.cluster_namespace.outputs.cluster_endpoint
  cluster_ca_certificate = data.ns_connection.cluster_namespace.outputs.cluster_ca_certificate
  cluster_name           = try(data.ns_connection.cluster_namespace.outputs.cluster_name, "")
}

// GKE authenticates the kubernetes provider with a short-lived OAuth2 access token.
// See https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config
data "google_client_config" "provider" {
  count = local.is_gcp ? 1 : 0
}

// EKS authenticates the kubernetes provider with an ephemeral cluster auth token.
ephemeral "aws_eks_cluster_auth" "cluster" {
  count = local.is_aws ? 1 : 0

  name = local.cluster_name
}

locals {
  // GKE reports a bare host; the provider needs an https:// scheme. EKS already includes it.
  k8s_host  = local.is_aws ? local.cluster_endpoint : "https://${local.cluster_endpoint}"
  k8s_token = local.is_aws ? ephemeral.aws_eks_cluster_auth.cluster[0].token : data.google_client_config.provider[0].access_token
}

provider "kubernetes" {
  host                   = local.k8s_host
  token                  = local.k8s_token
  cluster_ca_certificate = base64decode(local.cluster_ca_certificate)
}
