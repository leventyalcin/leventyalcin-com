domain_name = "leventyalcin.com"

cf_allow_tls_1_3            = "on"
cf_always_online            = "on"
cf_always_use_https         = "on"
cf_automatic_https_rewrites = "on"

cf_block_user_agents = [
  "AhrefsBot",
  "Dataprovider.com",
  "SemrushBot",
  "BLEXBot",
  "PetalBot",
  "Go-http-client",
  "Nmap",
  "python",
  "WinHttpClient",
  "masscan",
  "CensysInspect",
]

cf_blocked_paths = [
  ".php",
  ".asp",
  "/wp-"
]

cf_brotli             = "on"
cf_browser_cache_ttl  = 432000
cf_browser_check      = "on"
cf_cache_level        = "aggressive"
cf_challenge_ttl      = 3600
cf_development_mode   = "off"
cf_email_obfuscation  = "on"
cf_hotlink_protection = "on"
cf_http3              = "on"
cf_ip_geolocation     = "on"

cf_js_challenge_country_codes = [
  "CN",
  "IN",
  "RU",
]

cf_jump_start          = true
cf_min_tls_version     = "1.2"
cf_minify_css          = "on"
cf_minify_html         = "on"
cf_minify_js           = "on"
cf_plan_type           = "free"
cf_security_level      = "high"
cf_ssl_encryption_mode = "flexible"
cf_zone_type           = "full"
