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

  # Cloud-init: mount the data volume and install Dokploy.
  user_data = <<-CLOUDINIT
    #!/bin/bash
    set -euo pipefail

    # --- Mount the Hetzner volume ---
    for i in $(seq 1 30); do
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

    # --- Install Dokploy ---
    curl -sSL https://dokploy.com/install.sh | sh

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

# --- Firewall ---

resource "hcloud_firewall" "frodo" {
  name = "frodo"

  # SSH
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  # HTTP
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  # HTTPS
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  # Port 3000 (Dokploy UI) is intentionally NOT exposed.
  # Access the panel via SSH tunnel: mise run tunnel
}
