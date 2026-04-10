# Random secrets the user never sees. Persisted in encrypted state.

resource "random_password" "komodo_webhook" {
  length  = 48
  special = false
}

resource "random_password" "komodo_jwt" {
  length  = 48
  special = false
}

resource "random_password" "komodo_db" {
  length  = 32
  special = false
}
