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
