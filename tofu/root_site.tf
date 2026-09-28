resource "cloudflare_ruleset" "redirect_apex_to_itay" {
  depends_on = [cloudflare_workers_route.root]

  zone_id     = local.cloudflare_zone_id
  name        = "default"
  description = "Canonical hostname and Quizmon maintenance redirects"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [
    {
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
    },
    {
      ref         = "quizmon_maintenance"
      description = "Temporarily redirect Quizmon page visits during maintenance"
      expression  = "http.host eq \"quizmon.raveh.dev\" and http.request.method eq \"GET\" and http.request.uri.path ne \"/maintenance\" and http.request.uri.path ne \"/maintenance.html\" and any(http.request.headers[\"accept\"][*] contains \"text/html\")"
      action      = "redirect"
      enabled     = false
      action_parameters = {
        from_value = {
          target_url = {
            value = "https://quizmon.raveh.dev/maintenance"
          }
          status_code           = 302
          preserve_query_string = false
        }
      }
    },
  ]

  lifecycle {
    # The local maintenance command owns this rule's temporary enabled state.
    ignore_changes = [rules[1].enabled]
  }
}

resource "cloudflare_worker" "root" {
  account_id = local.cloudflare_account_id
  name       = "raveh-root"
  subdomain = {
    enabled          = false
    previews_enabled = false
  }
}

resource "cloudflare_worker_version" "root" {
  account_id         = local.cloudflare_account_id
  worker_id          = cloudflare_worker.root.id
  compatibility_date = "2026-09-04"
  main_module        = "index.js"
  modules = [
    for name in ["index.js", "privacy.html", "ads.txt"] : {
      name         = name
      content_type = name == "index.js" ? "application/javascript+module" : "text/plain"
      content_file = "${path.module}/../workers/root/${name}"
    }
  ]
}

resource "cloudflare_workers_deployment" "root" {
  account_id  = local.cloudflare_account_id
  script_name = cloudflare_worker.root.name
  strategy    = "percentage"
  versions = [{
    percentage = 100
    version_id = cloudflare_worker_version.root.id
  }]
}

resource "cloudflare_workers_route" "root" {
  zone_id = local.cloudflare_zone_id
  pattern = "raveh.dev/*"
  script  = cloudflare_workers_deployment.root.script_name
}
