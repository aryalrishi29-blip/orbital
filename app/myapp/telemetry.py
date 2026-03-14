"""
OpenTelemetry instrumentation for Orbital.

Initialises tracing at process start and auto-instruments:
  - Every Django HTTP request → span with method, route, status
  - Every psycopg2 DB query  → child span with SQL statement
  - Manual spans can be added anywhere via get_tracer()

Traces are exported to an OTEL Collector sidecar (or Jaeger directly)
via gRPC on the OTEL_EXPORTER_OTLP_ENDPOINT env var.

Environment variables (set in K8s secrets or docker-compose.yml):
  OTEL_EXPORTER_OTLP_ENDPOINT  e.g. http://otel-collector:4317
  OTEL_SERVICE_NAME             defaults to "orbital"
  OTEL_ENVIRONMENT              e.g. production / staging / local
  OTEL_ENABLED                  set to "false" to disable (e.g. in tests)

Usage — add a manual span anywhere in the app:
    from myapp.telemetry import get_tracer
    tracer = get_tracer()
    with tracer.start_as_current_span("my-operation") as span:
        span.set_attribute("article.id", article_id)
        result = do_work()
"""
import logging
import os

logger = logging.getLogger(__name__)


def configure_tracing() -> None:
    """Bootstrap OpenTelemetry. Called once from wsgi.py at process start."""

    if os.environ.get("OTEL_ENABLED", "true").lower() == "false":
        logger.info("OpenTelemetry disabled (OTEL_ENABLED=false)")
        return

    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.instrumentation.django import DjangoInstrumentor
        from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.sdk.trace.sampling import ParentBasedTraceIdRatio

        service_name = os.environ.get("OTEL_SERVICE_NAME", "orbital")
        environment  = os.environ.get("OTEL_ENVIRONMENT", "production")
        endpoint     = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")

        # Sample 100% in staging, 10% in production (adjust via env var)
        sample_rate = float(os.environ.get("OTEL_SAMPLE_RATE", "0.1"))

        resource = Resource.create({
            "service.name":        service_name,
            "service.version":     "1.0.0",
            "deployment.environment": environment,
        })

        provider = TracerProvider(
            resource=resource,
            sampler=ParentBasedTraceIdRatio(sample_rate),
        )

        exporter  = OTLPSpanExporter(endpoint=endpoint, insecure=True)
        processor = BatchSpanProcessor(
            exporter,
            max_queue_size=2048,
            max_export_batch_size=512,
            export_timeout_millis=30_000,
        )
        provider.add_span_processor(processor)
        trace.set_tracer_provider(provider)

        # Auto-instrument Django — adds spans for every HTTP request
        DjangoInstrumentor().instrument(
            # Exclude health checks and metrics from tracing (too noisy)
            excluded_urls=r"health/|metrics/",
        )

        # Auto-instrument psycopg2 — adds child spans for every DB query
        Psycopg2Instrumentor().instrument(
            enable_commenter=True,    # adds /*traceparent=...*/ to SQL
            commenter_options={},
        )

        logger.info(
            f"OpenTelemetry configured: service={service_name} "
            f"endpoint={endpoint} sample_rate={sample_rate}"
        )

    except ImportError as exc:
        logger.warning(f"OpenTelemetry packages not installed — tracing disabled: {exc}")
    except Exception as exc:
        logger.error(f"Failed to configure OpenTelemetry: {exc}", exc_info=True)


def get_tracer():
    """Return the global tracer. Safe to call even if OTel not configured."""
    try:
        from opentelemetry import trace
        return trace.get_tracer("orbital")
    except ImportError:
        import contextlib

        class _NoopTracer:
            @contextlib.contextmanager
            def start_as_current_span(self, *a, **kw):
                yield None

        return _NoopTracer()
