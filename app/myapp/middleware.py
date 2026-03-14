"""
Custom middleware for the orbital project.

RequestLoggingMiddleware  — structured JSON log line for every request
RateLimitMiddleware       — simple in-process rate limiter (for demo purposes;
                            use Redis-backed throttling in high-traffic production)
"""
import json
import logging
import time
from collections import defaultdict, deque
from threading import Lock

logger = logging.getLogger("myapp.requests")


class RequestLoggingMiddleware:
    """
    Emits one structured JSON log line per request:

        {"method": "GET", "path": "/api/articles/", "status": 200,
         "duration_ms": 12, "ip": "1.2.3.4"}

    This makes logs easy to parse by CloudWatch, Datadog, or any
    log aggregation system that ingests JSON.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        start = time.monotonic()
        response = self.get_response(request)
        duration_ms = round((time.monotonic() - start) * 1000, 1)

        # Skip health-check spam unless it's an error
        if request.path == "/health/" and response.status_code < 400:
            return response

        logger.info(
            json.dumps(
                {
                    "method":      request.method,
                    "path":        request.path,
                    "status":      response.status_code,
                    "duration_ms": duration_ms,
                    "ip":          self._get_client_ip(request),
                }
            )
        )
        return response

    @staticmethod
    def _get_client_ip(request) -> str:
        forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()
        return request.META.get("REMOTE_ADDR", "unknown")


class RateLimitMiddleware:
    """
    Sliding-window rate limiter: max 60 requests per IP per 60 seconds.
    Returns HTTP 429 when exceeded.

    NOTE: This is an in-process demo implementation. In production use
    django-ratelimit with a Redis backend so limits are shared across
    all Gunicorn workers and server instances.
    """

    LIMIT   = 60    # requests
    WINDOW  = 60    # seconds

    def __init__(self, get_response):
        self.get_response = get_response
        self._requests: dict[str, deque] = defaultdict(deque)
        self._lock = Lock()

    def __call__(self, request):
        ip = self._get_client_ip(request)

        if self._is_rate_limited(ip):
            from django.http import JsonResponse
            return JsonResponse(
                {"error": "Too many requests. Slow down and try again shortly."},
                status=429,
            )

        return self.get_response(request)

    def _is_rate_limited(self, ip: str) -> bool:
        now = time.monotonic()
        cutoff = now - self.WINDOW

        with self._lock:
            timestamps = self._requests[ip]
            # Drop timestamps outside the sliding window
            while timestamps and timestamps[0] < cutoff:
                timestamps.popleft()

            if len(timestamps) >= self.LIMIT:
                return True

            timestamps.append(now)
            return False

    @staticmethod
    def _get_client_ip(request) -> str:
        forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()
        return request.META.get("REMOTE_ADDR", "unknown")
