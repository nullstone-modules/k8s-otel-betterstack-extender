// Better Stack credentials come from a connected `betterstack` datastore (e.g. aws-betterstack),
// which owns the `ingesting_host` and stores the source token in the cloud's secret manager.
//
// Better Stack OTLP ingestion authenticates with `Authorization: Bearer <source_token>`. The
// collector only injects `--config` files (it can't set env vars on its pod), so the header must be
// a resolved literal baked into the fragment -- we read the secret to its plaintext value here and
// use it directly in `betterstack.tf`.
//
// The contract is provider-wildcarded to match the cluster-namespace connection: today only
// aws-betterstack exists (secret in AWS Secrets Manager); a future gcp-betterstack exposing the
// same outputs (with the secret in GCP Secret Manager) plugs into the GCP branch below.
data "ns_connection" "betterstack" {
  name     = "betterstack"
  contract = "datastore/*/betterstack"
}

locals {
  betterstack_ingesting_host = data.ns_connection.betterstack.outputs.ingesting_host
  source_token_secret_id     = data.ns_connection.betterstack.outputs.source_token_secret_id
}

// --- GCP (GKE): read the source token from Google Secret Manager ---
data "google_secret_manager_secret_version" "source_token" {
  count  = local.is_gcp ? 1 : 0
  secret = local.source_token_secret_id
}

// --- AWS (EKS): read the source token from AWS Secrets Manager ---
data "aws_secretsmanager_secret_version" "source_token" {
  count     = local.is_aws ? 1 : 0
  secret_id = local.source_token_secret_id
}

locals {
  // Plaintext source token, read from the secret manager of the connected cloud.
  betterstack_token = (
    local.is_aws ? data.aws_secretsmanager_secret_version.source_token[0].secret_string :
    data.google_secret_manager_secret_version.source_token[0].secret_data
  )
}
