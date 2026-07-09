variable "signals" {
  type        = list(string)
  default     = ["logs", "traces", "metrics"]
  description = <<EOF
Which telemetry signals to forward to Better Stack. Any subset of `logs`, `traces`, `metrics`.
A `<signal>/betterstack` pipeline is created for each entry.
EOF

  validation {
    condition     = length(var.signals) > 0 && alltrue([for s in var.signals : contains(["logs", "traces", "metrics"], s)])
    error_message = "signals must be a non-empty subset of [\"logs\", \"traces\", \"metrics\"]."
  }
}
