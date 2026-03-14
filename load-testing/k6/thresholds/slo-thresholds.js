/**
 * Orbital Platform — SLO Threshold Definitions
 *
 * Single source of truth for all k6 SLO thresholds.
 * Import into any test script to keep SLOs consistent:
 *
 *   import { SLO_THRESHOLDS } from "../thresholds/slo-thresholds.js";
 *   export const options = { thresholds: SLO_THRESHOLDS };
 *
 * Matches the PrometheusRules in observability/prometheus/alert-rules.yaml
 * so CI load tests and production alerts enforce the same SLOs.
 */

export const SLO_THRESHOLDS = {
  // Availability SLO: 99.5% of requests succeed
  "http_req_failed": ["rate<0.005"],
  "error_rate":      ["rate<0.005"],

  // Latency SLO: p95 < 500ms, p99 < 1500ms (all endpoints)
  "http_req_duration": [
    "p(95)<500",
    "p(99)<1500",
  ],

  // Tighter SLO for health check — must always be < 200ms
  "http_req_duration{name:health}": ["p(99)<200"],

  // Read endpoints — faster budget
  "http_req_duration{name:list}":   ["p(95)<300", "p(99)<800"],
  "http_req_duration{name:detail}": ["p(95)<300", "p(99)<800"],

  // Write endpoints — slightly more budget
  "http_req_duration{name:create}":  ["p(95)<500", "p(99)<1500"],
  "http_req_duration{name:publish}": ["p(95)<500", "p(99)<1500"],
};

// Environment-specific overrides
// Staging has looser thresholds — smaller instances, less tuning
export const STAGING_THRESHOLDS = {
  ...SLO_THRESHOLDS,
  "http_req_duration": ["p(95)<1000", "p(99)<3000"],
};

// Smoke test: just verify the system is alive
export const SMOKE_THRESHOLDS = {
  "http_req_failed":   ["rate<0.05"],
  "http_req_duration": ["p(99)<2000"],
};
