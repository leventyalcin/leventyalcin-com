terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.53"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 2.25"
    }
  }

  backend "s3" {}
}

provider "aws" {}
provider "cloudflare" {}

locals {
  tags = merge(
    var.tags,
    {
      "owner"    = var.git_user
      "git_info" = var.git_info
      "env"      = "prod"
      "cc"       = "personal-website"
    }
  )
}

module "site" {
  source = "git@github.com:opsgang/terraform-cloudflare-aws-static-website.git?ref=0.0.1"

  domain_name                   = var.domain_name
  cf_allow_tls_1_3              = var.cf_allow_tls_1_3
  cf_always_online              = var.cf_always_online
  cf_always_use_https           = var.cf_always_use_https
  cf_automatic_https_rewrites   = var.cf_automatic_https_rewrites
  cf_block_user_agents          = var.cf_block_user_agents
  cf_blocked_paths              = var.cf_blocked_paths
  cf_brotli                     = var.cf_brotli
  cf_browser_cache_ttl          = var.cf_browser_cache_ttl
  cf_browser_check              = var.cf_browser_check
  cf_cache_level                = var.cf_cache_level
  cf_challenge_ttl              = var.cf_challenge_ttl
  cf_development_mode           = var.cf_development_mode
  cf_email_obfuscation          = var.cf_email_obfuscation
  cf_hotlink_protection         = var.cf_hotlink_protection
  cf_http3                      = var.cf_http3
  cf_ip_geolocation             = var.cf_ip_geolocation
  cf_js_challenge_country_codes = var.cf_js_challenge_country_codes
  cf_jump_start                 = var.cf_jump_start
  cf_min_tls_version            = var.cf_min_tls_version
  cf_minify_css                 = var.cf_minify_css
  cf_minify_html                = var.cf_minify_html
  cf_minify_js                  = var.cf_minify_js
  cf_plan_type                  = var.cf_plan_type
  cf_security_level             = var.cf_security_level
  cf_ssl_encryption_mode        = var.cf_ssl_encryption_mode
  cf_zone_type                  = var.cf_zone_type
  tags                          = local.tags
}
