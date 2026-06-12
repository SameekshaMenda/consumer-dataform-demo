terraform {
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 5.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# 1. Enable required APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "dataform.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# 2. BigQuery datasets — Medallion layers (Bronze / Silver / Gold)
# ---------------------------------------------------------------------------
resource "google_bigquery_dataset" "bronze" {
  dataset_id = "consumer_bronze"
  project    = var.project_id
  location   = var.bq_location
}

resource "google_bigquery_dataset" "silver" {
  dataset_id = "consumer_silver"
  project    = var.project_id
  location   = var.bq_location
}

resource "google_bigquery_dataset" "gold" {
  dataset_id = "consumer_gold"
  project    = var.project_id
  location   = var.bq_location
}

# ---------------------------------------------------------------------------
# 3. Service Account for Dataform execution
# ---------------------------------------------------------------------------
resource "google_service_account" "dataform_runner" {
  account_id   = "dataform-runner"
  display_name = "Dataform Runner SA"
  project      = var.project_id
}

resource "google_project_iam_member" "bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_service_account.dataform_runner.member
}

resource "google_project_iam_member" "bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.dataform_runner.member
}

# ---------------------------------------------------------------------------
# 4. Dataform repository — linked to GitHub
# ---------------------------------------------------------------------------
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_secret_manager_secret" "github_token" {
  secret_id = "dataform-github-token"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "github_token_version" {
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.github_pat
}

resource "google_secret_manager_secret_iam_member" "dataform_sa_secret_access" {
  secret_id = google_secret_manager_secret.github_token.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

resource "google_dataform_repository" "consumer_repo" {
  provider = google-beta

  name         = "consumer_dataform_repo"
  display_name = "consumer_dataform_repo"
  project      = var.project_id
  region       = var.region

  service_account = google_service_account.dataform_runner.email

  git_remote_settings {
    url                                 = var.github_repo_url
    default_branch                      = var.github_default_branch
    authentication_token_secret_version = google_secret_manager_secret_version.github_token_version.id
  }

  workspace_compilation_overrides {
    default_database = var.project_id
  }

  depends_on = [google_project_service.apis]
}