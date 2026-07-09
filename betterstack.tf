// Build the OTEL config fragment that the collector deep-merges on top of its base config.
//
// The collector merges multiple `--config` files: maps merge recursively, but lists are *replaced*.
// So this fragment contributes only NEW map keys -- its own exporter and a new `<signal>/betterstack`
// pipeline per requested signal -- rather than touching the base pipelines. The pipelines reference
// processors (`k8sattributes`, `memory_limiter`, `batch`) and the `otlp` receiver that already exist
// in the collector's base config.
locals {
  // The file name the fragment is mounted as, and the config map data key (collector mounts via subPath).
  betterstack_filename = "betterstack.yaml"

  // Tolerate a pasted URL: strip a leading scheme and trailing slash down to the bare host.
  betterstack_host = trimsuffix(trimprefix(trimprefix(local.betterstack_ingesting_host, "https://"), "http://"), "/")

  betterstack_fragment = {
    exporters = {
      // The otlphttp exporter appends the per-signal path (`/v1/logs`, `/v1/traces`, `/v1/metrics`)
      // to the base endpoint, so a single exporter serves every pipeline.
      "otlphttp/betterstack" = {
        endpoint    = "https://${local.betterstack_host}"
        headers     = { Authorization = "Bearer ${local.betterstack_token}" }
        compression = "gzip"
      }
    }
    service = {
      pipelines = {
        for signal in var.signals : "${signal}/betterstack" => {
          receivers  = ["otlp"]
          processors = ["k8sattributes", "memory_limiter", "batch"]
          exporters  = ["otlphttp/betterstack"]
        }
      }
    }
  }
}

resource "kubernetes_config_map_v1" "betterstack" {
  metadata {
    name      = local.resource_name
    namespace = local.kubernetes_namespace
    labels    = local.k8s_labels
  }

  data = {
    (local.betterstack_filename) = yamlencode(local.betterstack_fragment)
  }
}
