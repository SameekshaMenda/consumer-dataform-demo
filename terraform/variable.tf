variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "bq_location" {
  type    = string
  default = "US"
}

variable "github_repo_url" {
  type = string
}

variable "github_default_branch" {
  type    = string
  default = "main"
}

variable "github_pat" {
  type      = string
  sensitive = true
}