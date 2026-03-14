import json

from django.http import JsonResponse
from django.views import View
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

from .models import Article


class HealthCheckView(View):
    """
    GET /health/
    Used by the load balancer and the deploy script to verify the container
    started correctly.  Must return 200 within a few seconds.
    """

    def get(self, request):
        return JsonResponse(
            {
                "status":  "healthy",
                "service": "orbital",
                "version": "1.0.0",
            }
        )


class HomeView(View):
    """
    GET /
    API root — lists available endpoints.
    """

    def get(self, request):
        return JsonResponse(
            {
                "message": "Orbital Platform API",
                "endpoints": {
                    "health":   "/health/",
                    "articles": "/api/articles/",
                },
            }
        )


@method_decorator(csrf_exempt, name="dispatch")
class ArticleListView(View):
    """
    GET  /api/articles/         → list all published articles
    POST /api/articles/         → create a new article
    """

    def get(self, request):
        articles = Article.objects.filter(published=True).values(
            "id", "title", "body", "created_at"
        )
        return JsonResponse({"articles": list(articles)})

    def post(self, request):
        try:
            data = json.loads(request.body)
        except json.JSONDecodeError:
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        title = data.get("title", "").strip()
        body  = data.get("body",  "").strip()

        if not title or not body:
            return JsonResponse({"error": "title and body are required"}, status=400)

        article = Article.objects.create(title=title, body=body)
        return JsonResponse(
            {
                "id":         article.id,
                "title":      article.title,
                "body":       article.body,
                "published":  article.published,
                "created_at": article.created_at.isoformat(),
            },
            status=201,
        )


@method_decorator(csrf_exempt, name="dispatch")
class ArticleDetailView(View):
    """
    GET    /api/articles/<id>/   → retrieve an article
    PATCH  /api/articles/<id>/   → publish an article
    DELETE /api/articles/<id>/   → delete an article
    """

    def _get_article(self, pk):
        try:
            return Article.objects.get(pk=pk)
        except Article.DoesNotExist:
            return None

    def get(self, request, pk):
        article = self._get_article(pk)
        if not article:
            return JsonResponse({"error": "Not found"}, status=404)
        return JsonResponse(
            {
                "id":         article.id,
                "title":      article.title,
                "body":       article.body,
                "published":  article.published,
                "created_at": article.created_at.isoformat(),
                "updated_at": article.updated_at.isoformat(),
            }
        )

    def patch(self, request, pk):
        article = self._get_article(pk)
        if not article:
            return JsonResponse({"error": "Not found"}, status=404)
        article.publish()
        return JsonResponse({"id": article.id, "published": True})

    def delete(self, request, pk):
        article = self._get_article(pk)
        if not article:
            return JsonResponse({"error": "Not found"}, status=404)
        article.delete()
        return JsonResponse({}, status=204)
