terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

#------------------------------------------------
# APIの有効化
#------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com"
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

#------------------------------------------------
# サービスアカウント (SA)
#------------------------------------------------
# 1. Cloud Functionが実行時に使用するSA (Runner SA)
resource "google_service_account" "function_runner_sa" {
  project      = var.project_id
  account_id   = "function-runner-sa"
  display_name = "Service Account for Cloud Function execution"
  depends_on   = [google_project_service.apis]
}

#------------------------------------------------
# ストレージ & BigQuery
#------------------------------------------------
# Cloud Functionのソースコードを置くためのバケット
resource "google_storage_bucket" "function_source_bucket" {
  project                     = var.project_id
  name                        = "${var.project_id}-cf-source-bucket" # プロジェクトIDを含めてユニークな名前に
  location                    = var.region
  uniform_bucket_level_access = true
  depends_on                  = [google_project_service.apis]
}

# Functionが書き込む先のBigQueryデータセット
resource "google_bigquery_dataset" "my_dataset" {
  project     = var.project_id
  dataset_id  = "ci_cd_test_dataset"
  location    = var.region
  description = "Dataset for CI/CD test"
  depends_on  = [google_project_service.apis]
}

#------------------------------------------------
# IAM権限設定
#------------------------------------------------
# Runner SAにBigQueryへの書き込み権限を付与
resource "google_project_iam_member" "runner_sa_bq_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_runner_sa.email}"
}

#------------------------------------------------
# Cloud Function
#------------------------------------------------
# deploy.shが作成したZIPファイルをCloud Storageにアップロード
resource "google_storage_bucket_object" "hello_world_source" {
  name   = "source/hello-world-function.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = "hello-world-function.zip"
}

# サンプルのCloud Function
resource "google_cloudfunctions2_function" "hello_world_function" {
  project     = var.project_id
  name        = "hello-world-function"
  location    = var.region
  description = "A sample function deployed via CI/CD"

  build_config {
    runtime     = "python311"
    entry_point = "hello_world"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.hello_world_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256Mi"
    timeout_seconds       = 60
    service_account_email = google_service_account.function_runner_sa.email
  }

  # ソースコードのZIPファイルが変更されたら、このFunctionを再作成（再デプロイ）する
  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.hello_world_source
    ]
  }

  depends_on = [
    google_project_iam_member.runner_sa_bq_writer
  ]
}

#------------------------------------------------
# Cloud Build (CI/CDパイプライン)
#------------------------------------------------
# Cloud Buildが使用するSA (Builder SA)
# ※注意: このSAには、手動で強力な権限を付与する必要があります
data "google_project" "project" {
  # このデータソースがAPIを必要とするため、API有効化リソースに依存させる
  depends_on = [google_project_service.apis]
}
locals {
  cloudbuild_sa_email = "${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Builder SAに必要な権限を付与
resource "google_project_iam_member" "builder_sa_roles" {
  for_each = toset([
    "roles/run.admin",
    "roles/iam.serviceAccountUser",
    "roles/cloudfunctions.developer",
    "roles/storage.admin"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${local.cloudbuild_sa_email}"
  
  # ★この依存関係を追加！
  # Cloud Build APIが有効化され、SAが作成されるのを待つ
  depends_on = [google_project_service.apis]
}

# GitHubリポジトリと連携するCloud Buildトリガー
resource "google_cloudbuild_trigger" "github_trigger" {
  project = var.project_id
  name    = "trigger-from-github-main"

  github {
    owner = var.github_repo_owner
    name  = var.github_repo_name
    push {
      branch = "^main$"
    }
  }

  # ビルド手順書としてcloudbuild.yamlを指定
  filename = "cloudbuild.yaml"

  # # Cloud Buildが使用するサービスアカウント
  # service_account = "projects/${var.project_id}/serviceAccounts/${local.cloudbuild_sa_email}"

  depends_on = [
    google_project_iam_member.builder_sa_roles
  ]
}