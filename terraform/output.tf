output "function_url" {
  description = "デプロイされたCloud FunctionのURL"
  value       = google_cloudfunctions2_function.hello_world_function.url
}

output "bigquery_dataset_id" {
  description = "作成されたBigQueryデータセットのID"
  value       = google_bigquery_dataset.my_dataset.dataset_id
}

output "cloud_build_trigger_id" {
  description = "作成されたCloud BuildトリガーのID"
  value       = google_cloudbuild_trigger.github_trigger.id
}