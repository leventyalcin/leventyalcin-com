output "bucket_name" {
  value = module.site.bucket_name
}

output "cf_name_servers" {
  value = module.site.cf_name_servers
}

output "cf_verification_code" {
  value = module.site.cf_verification_code
}

output "git_info" {
  value = var.git_info
}

output "git_user" {
  value = var.git_user
}
