from django.contrib import admin
from django.urls import path, include

from .views import ArticleDetailView, ArticleListView, HealthCheckView, HomeView

urlpatterns = [
    path("admin/",                    admin.site.urls),
    path("",                          include("django_prometheus.urls")),  # exposes /metrics/
    path("health/",                   HealthCheckView.as_view(),  name="health-check"),
    path("",                          HomeView.as_view(),          name="home"),
    path("api/articles/",             ArticleListView.as_view(),   name="article-list"),
    path("api/articles/<int:pk>/",    ArticleDetailView.as_view(), name="article-detail"),
]
