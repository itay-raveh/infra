resource "cloudflare_ruleset" "redirect_apex_to_itay" {
  depends_on = [cloudflare_workers_route.root]

  zone_id     = var.zone_id
  name        = "default"
  description = "Canonical hostname redirects"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [{
    ref         = "redirect_apex_to_itay"
    description = "Redirect raveh.dev to itay.raveh.dev"
    expression  = "http.host eq \"raveh.dev\" and not http.request.uri.path in {\"/privacy\" \"/privacy/\" \"/privacy.html\" \"/ads.txt\"}"
    action      = "redirect"
    action_parameters = {
      from_value = {
        target_url = {
          expression = "concat(\"https://itay.raveh.dev\", http.request.uri.path)"
        }
        status_code           = 301
        preserve_query_string = true
      }
    }
  }]
}

resource "cloudflare_worker" "root" {
  account_id = var.account_id
  name       = "raveh-root"
  subdomain = {
    enabled          = false
    previews_enabled = false
  }
}

resource "cloudflare_worker_version" "root" {
  account_id         = var.account_id
  worker_id          = cloudflare_worker.root.id
  compatibility_date = "2026-09-04"
  main_module        = "index.js"
  modules = [
    for name in ["index.js", "privacy.html", "ads.txt"] : {
      name         = name
      content_type = name == "index.js" ? "application/javascript+module" : "text/plain"
      content_file = "${var.root_worker_source_dir}/${name}"
    }
  ]
}

resource "cloudflare_workers_deployment" "root" {
  account_id  = var.account_id
  script_name = cloudflare_worker.root.name
  strategy    = "percentage"
  versions = [{
    percentage = 100
    version_id = cloudflare_worker_version.root.id
  }]
}

resource "cloudflare_workers_route" "root" {
  zone_id = var.zone_id
  pattern = "raveh.dev/*"
  script  = cloudflare_workers_deployment.root.script_name
}

resource "cloudflare_workers_custom_domain" "quizmon" {
  account_id = var.account_id
  hostname   = "quizmon.raveh.dev"
  service    = "quizmon"
  zone_id    = var.zone_id
}

resource "cloudflare_workers_custom_domain" "itay" {
  account_id = var.account_id
  hostname   = "itay.raveh.dev"
  service    = "itay"
  zone_id    = var.zone_id
}
