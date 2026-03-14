from django.db import models
from django.utils import timezone


class Article(models.Model):
    """A simple blog article — used to demonstrate ORM, migrations, and views."""

    title      = models.CharField(max_length=200)
    body       = models.TextField()
    published  = models.BooleanField(default=False)
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.title

    def publish(self) -> None:
        """Mark the article as published and persist only the changed fields."""
        self.published = True
        self.save(update_fields=["published", "updated_at"])
