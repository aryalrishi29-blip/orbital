"""
Build-time settings — used ONLY by `collectstatic` inside the Dockerfile.
Never loaded at runtime.  Avoids requiring a real database connection during
the image build stage.
"""
from myapp.settings import *  # noqa: F401, F403

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME":   "/tmp/build.db",
    }
}

# Disable manifest storage during build so missing hashes don't fail the step
STATICFILES_STORAGE = "django.contrib.staticfiles.storage.StaticFilesStorage"
