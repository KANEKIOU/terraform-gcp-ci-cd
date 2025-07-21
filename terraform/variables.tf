variable "project_id" {
  description = "Google Cloud PlatformのプロジェクトID"
  type        = string
}

variable "region" {
  description = "デプロイ先のリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "github_repo_owner" {
  description = "連携するGitHubリポジトリのオーナー名"
  type        = string
  default     = "KANEKIOU"
}

variable "github_repo_name" {
  description = "連携するGitHubリポジトリ名"
  type        = string
  default     = "terraform-gcp-ci-cd"
}