"""
management/commands/seed_data.py

Populates the database with realistic demo articles.
Safe to run multiple times — clears existing data first unless
--no-clear is passed.

Usage:
    python manage.py seed_data
    python manage.py seed_data --count 20
    python manage.py seed_data --no-clear
"""
from django.core.management.base import BaseCommand

from myapp.models import Article

SEED_ARTICLES = [
    {
        "title": "Zero-downtime deployments with Docker and GitHub Actions",
        "body": (
            "Deploying without dropping requests requires careful coordination between "
            "your CI/CD pipeline and your container orchestration strategy. In this post "
            "we walk through the stop-pull-start pattern used in this project: run "
            "migrations in a throwaway container, stop the old app container, immediately "
            "start the new one on the same port, then verify /health/ responds before "
            "considering the deploy successful. The entire window where the port is "
            "unbound is typically under 500 ms — acceptable for most applications."
        ),
        "published": True,
    },
    {
        "title": "Multi-stage Docker builds: why your production image should be tiny",
        "body": (
            "A naive Django Dockerfile starts with python:3.11, installs gcc, libpq-dev, "
            "all your pip dependencies, copies your code, and ships the whole thing. "
            "The result is an image over 600 MB with a C compiler in production. "
            "Multi-stage builds solve this: stage 1 (builder) compiles everything into "
            "a prefix directory; stage 2 (production) starts from a fresh slim base, "
            "copies only the compiled packages, and never sees a build tool. "
            "The production image in this project is under 200 MB."
        ),
        "published": True,
    },
    {
        "title": "GitHub Actions: the difference between jobs, steps, and workflows",
        "body": (
            "A workflow is a YAML file in .github/workflows/. It contains one or more "
            "jobs, each running on its own GitHub-hosted runner (a fresh Ubuntu VM). "
            "Jobs run in parallel by default; add `needs: [job_name]` to chain them. "
            "Within a job, steps execute sequentially on the same runner, sharing the "
            "filesystem. This project uses three jobs: test (parallel-safe, runs on "
            "every push), build-and-push (needs test, main branch only), and deploy "
            "(needs build-and-push, gated by a production environment)."
        ),
        "published": True,
    },
    {
        "title": "IAM least-privilege: why your CI/CD user should not be an admin",
        "body": (
            "It's tempting to give your GitHub Actions IAM user AdministratorAccess "
            "and move on. Resist this. A leaked secret key with admin access can "
            "delete your entire AWS account in seconds. The IAM user in this project "
            "has exactly six ECR permissions: GetAuthorizationToken, "
            "BatchCheckLayerAvailability, InitiateLayerUpload, UploadLayerPart, "
            "CompleteLayerUpload, and PutImage. That's the minimum needed to push an "
            "image. The EC2 instance has a separate role with read-only ECR access. "
            "Terraform provisions both so the policy is version-controlled."
        ),
        "published": True,
    },
    {
        "title": "Why 80% test coverage is a floor, not a ceiling",
        "body": (
            "Coverage thresholds in CI pipelines serve as a ratchet: once you reach "
            "80%, the pipeline rejects any PR that drops below it. This prevents "
            "coverage erosion over time. But coverage percentage is a proxy metric — "
            "100% line coverage doesn't mean your tests are good, just that every line "
            "was executed. This project enforces 80% as the minimum and includes tests "
            "for happy paths, error paths (400, 404), and edge cases (invalid JSON, "
            "missing fields) to demonstrate meaningful coverage rather than padding."
        ),
        "published": True,
    },
    {
        "title": "Draft: Terraform remote state and why you need it",
        "body": (
            "By default Terraform stores state in a local terraform.tfstate file. "
            "This works for solo projects but breaks immediately with a team: two "
            "people running terraform apply simultaneously corrupt the state file. "
            "Remote state in S3 with a DynamoDB lock table solves this. The backend "
            "block in main.tf is commented out pending S3 bucket creation — uncomment "
            "it once you've run the bootstrap script."
        ),
        "published": False,  # draft — not visible in the API list endpoint
    },
]


class Command(BaseCommand):
    help = "Seed the database with demo Article records"

    def add_arguments(self, parser):
        parser.add_argument(
            "--count",
            type=int,
            default=len(SEED_ARTICLES),
            help="Number of seed articles to create (default: all)",
        )
        parser.add_argument(
            "--no-clear",
            action="store_true",
            default=False,
            help="Skip clearing existing articles before seeding",
        )

    def handle(self, *args, **options):
        if not options["no_clear"]:
            deleted, _ = Article.objects.all().delete()
            if deleted:
                self.stdout.write(self.style.WARNING(f"  Cleared {deleted} existing articles."))

        count = min(options["count"], len(SEED_ARTICLES))
        created = 0

        for data in SEED_ARTICLES[:count]:
            Article.objects.create(**data)
            created += 1
            status = "published" if data["published"] else "draft"
            self.stdout.write(f"  + [{status}] {data['title'][:60]}")

        self.stdout.write(
            self.style.SUCCESS(f"\n✅ Seeded {created} article(s) successfully.")
        )
