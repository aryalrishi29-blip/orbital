import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "myapp.settings")

# Initialise OpenTelemetry tracing before the app handles any requests.
# Must be called before get_wsgi_application() so Django is instrumented.
from myapp.telemetry import configure_tracing
configure_tracing()

application = get_wsgi_application()
