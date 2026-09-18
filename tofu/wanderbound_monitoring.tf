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

resource "sentry_metric_monitor" "wanderbound_media_storage" {
  organization = local.sentry_organization
  project      = data.sentry_project.wanderbound_backend.slug
  name         = "Wanderbound media storage utilization"
  description  = "Logical album media usage relative to MAX_STORAGE_BYTES."
  environment  = "production"

  aggregate           = "max(value,storage.media.utilization,gauge,percent)"
  dataset             = "events_analytics_platform"
  event_types         = ["trace_item_metric"]
  extrapolation_mode  = "unknown"
  query_type          = "performance"
  time_window_seconds = 900

  condition_group = {
    conditions = [
      {
        type             = "gte"
        comparison       = 0.95
        condition_result = 75
      },
      {
        type             = "gte"
        comparison       = 0.8
        condition_result = 50
      },
      {
        type             = "lt"
        comparison       = 0.8
        condition_result = 0
      },
    ]
  }

  issue_detection = {
    type = "static"
  }
}

resource "sentry_metric_monitor" "wanderbound_filesystem_storage" {
  organization = local.sentry_organization
  project      = data.sentry_project.wanderbound_backend.slug
  name         = "Wanderbound filesystem storage utilization"
  description  = "Filesystem utilization for the volume containing the Wanderbound data folder."
  environment  = "production"

  aggregate           = "max(value,storage.filesystem.utilization,gauge,percent)"
  dataset             = "events_analytics_platform"
  event_types         = ["trace_item_metric"]
  extrapolation_mode  = "unknown"
  query_type          = "performance"
  time_window_seconds = 900

  condition_group = {
    conditions = [
      {
        type             = "gte"
        comparison       = 0.9
        condition_result = 75
      },
      {
        type             = "gte"
        comparison       = 0.8
        condition_result = 50
      },
      {
        type             = "lt"
        comparison       = 0.8
        condition_result = 0
      },
    ]
  }

  issue_detection = {
    type = "static"
  }
}

resource "sentry_alert" "wanderbound_storage" {
  organization = local.sentry_organization
  name         = "Send a notification for storage capacity issues"
  environment  = "production"
  monitor_ids = [
    sentry_metric_monitor.wanderbound_media_storage.id,
    sentry_metric_monitor.wanderbound_filesystem_storage.id,
  ]
  frequency_minutes = 30
  enabled           = true

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
    { issue_resolved_trigger = {} },
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
