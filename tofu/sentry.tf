locals {
  sentry_organization = "ravehdev"
}

data "sentry_project" "wanderbound_backend" {
  organization = local.sentry_organization
  slug         = "wanderbound-be"
}

data "sentry_project" "wanderbound_frontend" {
  organization = local.sentry_organization
  slug         = "wanderbound-fe"
}

data "sentry_project_issue_stream_monitor" "wanderbound_backend" {
  organization = local.sentry_organization
  project      = data.sentry_project.wanderbound_backend.slug
}

data "sentry_project_issue_stream_monitor" "wanderbound_frontend" {
  organization = local.sentry_organization
  project      = data.sentry_project.wanderbound_frontend.slug
}

resource "sentry_uptime_monitor" "wanderbound_health" {
  organization = local.sentry_organization
  project      = data.sentry_project.wanderbound_backend.slug
  name         = "Wanderbound Health"
  environment  = "production"
  url          = "https://wanderbound.raveh.dev/api/v1/health"
  method       = "GET"

  interval_seconds   = 60
  timeout_ms         = 10000
  downtime_threshold = 3
  recovery_threshold = 1
  enabled            = true

  assertion_json = provider::sentry::assertion(
    provider::sentry::op_and(
      provider::sentry::op_status_code_check("equals", 200),
    )
  )
}

resource "sentry_alert" "wanderbound_backend_high_priority" {
  organization      = local.sentry_organization
  name              = "Send a notification for high priority issues"
  monitor_ids       = [data.sentry_project_issue_stream_monitor.wanderbound_backend.id]
  frequency_minutes = 30
  enabled           = true

  legacy_trigger_conditions = [
    "new_high_priority_issue",
    "existing_high_priority_issue",
  ]

  action_filters = [{
    logic_type = "all"
    actions = [{
      email = {
        target_type      = "issue_owners"
        fallthrough_type = "ActiveMembers"
      }
    }]
  }]
}

resource "sentry_alert" "wanderbound_frontend_high_priority" {
  organization      = local.sentry_organization
  name              = "Send a notification for high priority issues"
  monitor_ids       = [data.sentry_project_issue_stream_monitor.wanderbound_frontend.id]
  frequency_minutes = 30
  enabled           = true

  legacy_trigger_conditions = [
    "new_high_priority_issue",
    "existing_high_priority_issue",
  ]

  action_filters = [{
    logic_type = "all"
    actions = [{
      email = {
        target_type      = "issue_owners"
        fallthrough_type = "ActiveMembers"
      }
    }]
  }]
}
