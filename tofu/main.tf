# --- SSH Key ---

resource "hcloud_ssh_key" "itay" {
  name       = "itay"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# --- Server ---

resource "hcloud_server" "frodo" {
  name        = "frodo"
  server_type = "cax11" # ARM64, 2 vCPU, 4 GB RAM, 40 GB NVMe
  location    = "hel1"  # Helsinki
  image       = "ubuntu-24.04"

  ssh_keys = [hcloud_ssh_key.itay.id]

  firewall_ids = [hcloud_firewall.frodo.id]

  labels = {
    role = "server"
    host = "frodo"
  }

  # Cloud-init is a one-shot bootstrap. Edits to user_data don't re-run on an
  # existing server anyway, so don't let tofu propose server replacements for
  # bootstrap-script edits. Force a fresh bootstrap with `tofu taint`.
  lifecycle {
    ignore_changes = [user_data]
  }

  # Cloud-init: mount the data volume, install Docker + Komodo, and connect
  # cloudflared to the Cloudflare Tunnel defined in cloudflare.tf.
  #
  # All Docker state lives on /mnt/data/docker (the Hetzner volume) so that
  # named volumes survive server replacement. Komodo runs via the upstream
  # ferretdb.compose.yaml with secrets interpolated from tofu state.
  user_data = <<-CLOUDINIT
    #!/bin/bash
    set -euo pipefail

    # --- Mount the Hetzner volume ---
    # Up to 4 minutes of retries. The volume attachment happens via a separate
    # Hetzner API call from tofu in parallel with the server boot, so cloud-init
    # may start before the device node appears.
    for i in $(seq 1 120); do
      VOLUME_DEV=$(ls /dev/disk/by-id/ 2>/dev/null | grep HC_Volume | grep -v part | head -1) && [ -n "$VOLUME_DEV" ] && break
      sleep 2
    done

    if [ -z "$VOLUME_DEV" ]; then
      echo "ERROR: Hetzner volume not found" >&2
      exit 1
    fi

    VOLUME_PATH="/dev/disk/by-id/$VOLUME_DEV"

    if ! blkid -o value -s TYPE "$VOLUME_PATH" | grep -q ext4; then
      mkfs.ext4 -F "$VOLUME_PATH"
    fi

    mkdir -p /mnt/data
    mount "$VOLUME_PATH" /mnt/data
    echo "$VOLUME_PATH /mnt/data ext4 defaults,nofail 0 2" >> /etc/fstab

    # --- Install Docker with data-root on the persistent volume ---
    mkdir -p /mnt/data/docker /etc/docker
    cat > /etc/docker/daemon.json <<'DAEMONJSON'
    {
      "data-root": "/mnt/data/docker"
    }
    DAEMONJSON

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Make sure the daemon is actually up before any compose call.
    systemctl enable --now docker
    for i in $(seq 1 30); do
      docker info >/dev/null 2>&1 && break
      sleep 1
    done

    # --- Pre-create the shared ingress network ---
    # Traefik and every routed stack attach to this as external. Creating it
    # here removes the "Traefik must deploy first" coupling between stacks.
    docker network inspect traefik >/dev/null 2>&1 || docker network create traefik

    # --- Install Komodo (Core + FerretDB + Periphery all-in-one) ---
    mkdir -p /etc/komodo
    curl -fsSL https://raw.githubusercontent.com/moghtech/komodo/main/compose/ferretdb.compose.yaml \
      -o /etc/komodo/compose.yaml

    cat > /etc/komodo/compose.env <<'KOMODOENV'
    COMPOSE_KOMODO_IMAGE_TAG=2
    COMPOSE_KOMODO_BACKUPS_PATH=/etc/komodo/backups
    KOMODO_DATABASE_USERNAME=komodo
    KOMODO_DATABASE_PASSWORD=${random_password.komodo_db.result}
    KOMODO_HOST=https://komodo.raveh.dev
    KOMODO_TITLE=Komodo
    KOMODO_LOCAL_AUTH=true
    KOMODO_DISABLE_USER_REGISTRATION=true
    KOMODO_INIT_ADMIN_USERNAME=admin
    KOMODO_INIT_ADMIN_PASSWORD=${var.komodo_bootstrap_password}
    KOMODO_FIRST_SERVER_NAME=frodo
    KOMODO_WEBHOOK_SECRET=${random_password.komodo_webhook.result}
    KOMODO_JWT_SECRET=${random_password.komodo_jwt.result}
    PERIPHERY_CORE_ADDRESS=ws://core:9120
    PERIPHERY_CONNECT_AS=frodo
    PERIPHERY_ROOT_DIRECTORY=/etc/komodo
    KOMODOENV

    docker compose --env-file /etc/komodo/compose.env -f /etc/komodo/compose.yaml up -d

    # --- Install cloudflared and connect to the tunnel ---
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
      | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/cloudflared.list
    apt-get update
    apt-get install -y cloudflared
    cloudflared service install ${cloudflare_zero_trust_tunnel_cloudflared.frodo.tunnel_token}

  CLOUDINIT
}

# --- Volume ---

resource "hcloud_volume" "data" {
  name     = "frodo-data"
  size     = 20 # GB
  location = "hel1"
  format   = "ext4"
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.frodo.id
  automount = false
}

# --- Wait for cloud-init ---
#
# Blocks `tofu apply` until the user-data script has finished on the server,
# so the panel is actually reachable when apply returns. Re-runs whenever the
# server is replaced (but not on unrelated applies).

resource "null_resource" "wait_cloud_init" {
  triggers = {
    server_id = hcloud_server.frodo.id
  }

  connection {
    type  = "ssh"
    host  = hcloud_server.frodo.ipv4_address
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = ["cloud-init status --wait"]
  }

  depends_on = [hcloud_volume_attachment.data]
}

# --- Firewall ---

resource "hcloud_firewall" "frodo" {
  name = "frodo"

  # SSH — break-glass only. Daily access happens over Cloudflare Access.
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  # 80/443 are intentionally NOT exposed. All HTTP(S) ingress arrives via
  # the Cloudflare Tunnel (outbound-only connection from cloudflared).
}
