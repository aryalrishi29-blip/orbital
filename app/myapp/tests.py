"""
Test suite for the orbital application.

Run locally:
    python manage.py test myapp --verbosity=2

With coverage:
    coverage run manage.py test myapp && coverage report --min-coverage=80
"""
import json

from django.test import Client, TestCase

from .models import Article


# ─────────────────────────────────────────────────────────────────────────────
# Health & routing
# ─────────────────────────────────────────────────────────────────────────────
class HealthCheckTests(TestCase):
    def setUp(self):
        self.client = Client()

    def test_returns_200(self):
        self.assertEqual(self.client.get("/health/").status_code, 200)

    def test_status_is_healthy(self):
        data = json.loads(self.client.get("/health/").content)
        self.assertEqual(data["status"], "healthy")

    def test_includes_service_and_version(self):
        data = json.loads(self.client.get("/health/").content)
        self.assertIn("service", data)
        self.assertIn("version", data)


class HomeViewTests(TestCase):
    def setUp(self):
        self.client = Client()

    def test_returns_200(self):
        self.assertEqual(self.client.get("/").status_code, 200)

    def test_lists_endpoints(self):
        data = json.loads(self.client.get("/").content)
        self.assertIn("endpoints", data)
        self.assertIn("health", data["endpoints"])
        self.assertIn("articles", data["endpoints"])


# ─────────────────────────────────────────────────────────────────────────────
# Article model
# ─────────────────────────────────────────────────────────────────────────────
class ArticleModelTests(TestCase):
    def setUp(self):
        self.article = Article.objects.create(
            title="CI/CD Best Practices",
            body="Always test before deploying.",
        )

    def test_defaults_to_unpublished(self):
        self.assertFalse(self.article.published)

    def test_str_returns_title(self):
        self.assertEqual(str(self.article), "CI/CD Best Practices")

    def test_publish_sets_flag(self):
        self.article.publish()
        self.article.refresh_from_db()
        self.assertTrue(self.article.published)

    def test_title_max_length(self):
        self.assertEqual(Article._meta.get_field("title").max_length, 200)

    def test_ordering_is_newest_first(self):
        second = Article.objects.create(title="Second Article", body="Body.")
        articles = list(Article.objects.all())
        # second was created later so it should appear first
        self.assertEqual(articles[0].pk, second.pk)


# ─────────────────────────────────────────────────────────────────────────────
# Article API — list & create
# ─────────────────────────────────────────────────────────────────────────────
class ArticleListViewTests(TestCase):
    def setUp(self):
        self.client = Client()
        self.published = Article.objects.create(
            title="Published", body="Visible.", published=True
        )
        self.draft = Article.objects.create(
            title="Draft", body="Hidden."
        )

    def test_get_returns_only_published(self):
        data = json.loads(self.client.get("/api/articles/").content)
        ids = [a["id"] for a in data["articles"]]
        self.assertIn(self.published.pk, ids)
        self.assertNotIn(self.draft.pk, ids)

    def test_post_creates_article(self):
        payload = json.dumps({"title": "New Post", "body": "Content here."})
        response = self.client.post(
            "/api/articles/",
            data=payload,
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 201)
        data = json.loads(response.content)
        self.assertEqual(data["title"], "New Post")
        self.assertFalse(data["published"])

    def test_post_missing_title_returns_400(self):
        payload = json.dumps({"body": "No title."})
        response = self.client.post(
            "/api/articles/",
            data=payload,
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)

    def test_post_invalid_json_returns_400(self):
        response = self.client.post(
            "/api/articles/",
            data="not-json",
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)


# ─────────────────────────────────────────────────────────────────────────────
# Article API — detail, publish, delete
# ─────────────────────────────────────────────────────────────────────────────
class ArticleDetailViewTests(TestCase):
    def setUp(self):
        self.client = Client()
        self.article = Article.objects.create(title="Detail Test", body="Body.")

    def test_get_existing_article(self):
        response = self.client.get(f"/api/articles/{self.article.pk}/")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertEqual(data["title"], "Detail Test")

    def test_get_missing_article_returns_404(self):
        response = self.client.get("/api/articles/99999/")
        self.assertEqual(response.status_code, 404)

    def test_patch_publishes_article(self):
        response = self.client.patch(f"/api/articles/{self.article.pk}/")
        self.assertEqual(response.status_code, 200)
        self.article.refresh_from_db()
        self.assertTrue(self.article.published)

    def test_delete_removes_article(self):
        pk = self.article.pk
        self.client.delete(f"/api/articles/{pk}/")
        self.assertFalse(Article.objects.filter(pk=pk).exists())
