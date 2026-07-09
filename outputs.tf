output "collector-config-maps" {
  value = [
    {
      filename      = local.betterstack_filename
      configMapName = kubernetes_config_map_v1.betterstack.metadata[0].name
    },
  ]
  description = "list(object({ filename = string, configMapName = string })) ||| The OTEL config fragments, delivered as ConfigMaps, to mount and merge into the collector at runtime. Consumed by mount-based collectors (e.g. gcp-gke-otel-collector) via their `extender` connection."
}

output "collector-config-fragments" {
  value = [
    local.betterstack_fragment,
  ]
  // The fragment embeds the resolved source token in the Authorization header, so the whole
  // output is sensitive. Nullstone connections deliver sensitive outputs like any other.
  sensitive   = true
  description = "list(any) ||| The OTEL config fragments as structured objects, to be deep-merged into the collector's spec.config in Terraform. Consumed by merge-based collectors (e.g. aws-eks-otel-adot) via their `extender` connection."
}

output "kubernetes_namespace" {
  value       = local.kubernetes_namespace
  description = "string ||| The namespace (from the shared cluster-namespace) where the config maps were created. The collector validates this matches its own namespace."
}
