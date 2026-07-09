# k8s-otel-betterstack-extender

Extends an OpenTelemetry collector to export logs, traces, and metrics to
[Better Stack](https://betterstack.com/docs/logs/open-telemetry/) **without forking the collector module**.

This module is an **otel-extender**: it creates a Kubernetes config map holding an OTEL config
fragment (a Better Stack `otlphttp` exporter plus a `<signal>/betterstack` pipeline per signal) and
reports it through its outputs. A collector that supports the `extender` connection consumes it in
one of two ways:

- **Mount-based** (e.g. `gcp-gke-otel-collector`): mounts the config map and passes it as an
  additional `--config` (uses the `collector-config-maps` output).
- **Merge-based** (e.g. `aws-eks-otel-adot`): deep-merges the structured fragment into the
  collector CRD's `spec.config` in Terraform (uses the `collector-config-fragments` output).

When this extender is connected, Better Stack receives a copy of the telemetry while the collector's
existing destinations (Cloud Trace, X-Ray, CloudWatch, etc.) keep receiving everything.

## Connections

| Name                | Contract                       | Required | Purpose                                                       |
|---------------------|--------------------------------|----------|---------------------------------------------------------------|
| `cluster-namespace` | `cluster-namespace/*/k8s:*`    | yes      | The cluster + namespace to create the config map in.          |
| `betterstack`       | `datastore/*/betterstack`      | yes      | The Better Stack credentials (ingesting host + source token). |

**Wire this to the SAME `cluster-namespace` block as the collector.** The collector reads the config
from its own namespace, so both blocks must target the same namespace. The collector enforces this
at plan time (it compares its namespace to this module's `kubernetes_namespace` output) and fails with
a clear message otherwise.

The connection contract is provider-wildcarded, so the module works against a GKE
(`cluster-namespace/gcp/k8s:gke`) or EKS (`cluster-namespace/aws/k8s:eks`) cluster-namespace. The
kubernetes provider and secret resolution branch automatically on the connected cloud.

## Credentials

Credentials come from the connected **betterstack datastore** (e.g. `aws-betterstack`), which owns
the ingesting host and stores the source token in the cloud's secret manager (AWS Secrets Manager
today). This module reads the token from the secret exported by the datastore's
`source_token_secret_id` output.

Every export is authenticated with `Authorization: Bearer <source_token>`. Because the collector
only injects `--config` files (it cannot set env vars on its pod), the module reads the secret at
apply time and writes the token straight into the `Authorization` header in the config map.

## Variables

| Name             | Default                          | Description                                                                                    |
|------------------|----------------------------------|------------------------------------------------------------------------------------------------|
| `signals`        | `["logs", "traces", "metrics"]`  | Which signals to forward. Any non-empty subset of `logs`, `traces`, `metrics`.                 |

## Generated fragment

```yaml
exporters:
  otlphttp/betterstack:
    endpoint: https://s123456.eu-nbg-2.betterstackdata.com   # /v1/{logs,traces,metrics} appended per signal
    compression: gzip
    headers:
      Authorization: "Bearer <source_token>"
service:
  pipelines:
    logs/betterstack:                 # NEW pipeline keys -> merge cleanly, no list conflict
      receivers: [otlp]               # shares the base otlp receiver by reference
      processors: [k8sattributes, memory_limiter, batch]
      exporters: [otlphttp/betterstack]
    traces/betterstack:
      receivers: [otlp]
      processors: [k8sattributes, memory_limiter, batch]
      exporters: [otlphttp/betterstack]
    metrics/betterstack:
      receivers: [otlp]
      processors: [k8sattributes, memory_limiter, batch]
      exporters: [otlphttp/betterstack]
```

The `otlphttp` exporter automatically appends the per-signal path (`/v1/logs`, `/v1/traces`,
`/v1/metrics`) to the base endpoint, so a single exporter serves every pipeline — matching Better
Stack's documented endpoints.

## Outputs

| Name                         | Description                                                                                          |
|------------------------------|------------------------------------------------------------------------------------------------------|
| `collector-config-maps`      | `list(object({ filename, configMapName }))` — the fragments for mount-based collectors to mount.     |
| `collector-config-fragments` | `list(any)` — the fragments as structured objects for merge-based collectors to deep-merge.          |
| `kubernetes_namespace`       | The namespace the config map was created in (validated against the collector).                       |
