#!/usr/bin/env bash
# Convenience wrapper for the common commands in README.md.
# Run from anywhere — paths are resolved relative to this script's location.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
INVENTORY="$ROOT_DIR/ansible/inventory.ini"
PLAYBOOK="$ROOT_DIR/ansible/playbook.yml"
VARS_FILE="$ROOT_DIR/ansible/group_vars/webservers/vars.yml"
LOCAL_IMAGE="fvtt:local"
LOCAL_CONTAINER="fvtt-local"
LOCAL_ENV_FILE="$ROOT_DIR/local/local.env"

usage() {
  cat <<'EOF'
Usage: ./ex.sh <command>

Setup
  setup             Copy .example config files to their real (gitignored) names
  up                tf-apply + tf-sync + deploy-remote — spin up a fresh deployment end to end
  down              fvtt-sync-up + tf-destroy — back up your data, then tear everything down

Terraform (EC2)
  tf-init           terraform init -backend-config=backend.hcl
  tf-apply          terraform apply (refreshes whitelist to your current public IP)
  tf-destroy        terraform destroy
  tf-output         Show terraform outputs (e.g. public_dns for inventory.ini)
  tf-sync           Fill in inventory.ini and vars.yml from terraform outputs
  ssh               SSH into the EC2 host (using inventory.ini connection details)

Ansible
  deploy-remote     Run the playbook against the remote EC2 host
  check             Dry run (--check) of the playbook

Backup
  fvtt-sync-up      Mirror /opt/foundrydata/Data up to the S3 backup bucket

Local (container)
  local-up          Build image (if needed) + start container, syncs world data from S3 first
  local-down        Sync world data to S3, then stop and remove the container
  local-sync-up     Mirror world data to S3 without stopping the container
  local-build       Build the container image (fvtt:local)
  local-shell       Open a shell in the running local container

EOF
}

require_file() {
  local path="$1" example_hint="$2"
  if [[ ! -f "$path" ]]; then
    echo "Missing $path — $example_hint" >&2
    exit 1
  fi
}

cmd_setup() {
  cp -n "$ROOT_DIR/ansible/inventory.ini.example" "$INVENTORY"
  cp -n "$ROOT_DIR/ansible/group_vars/webservers/secrets.yml.example" "$ROOT_DIR/ansible/group_vars/webservers/secrets.yml"
  cp -n "$ROOT_DIR/ansible/group_vars/webservers/vars.yml.example" "$ROOT_DIR/ansible/group_vars/webservers/vars.yml"
  cp -n "$TF_DIR/terraform.tfvars.example" "$TF_DIR/terraform.tfvars"
  cp -n "$TF_DIR/backend.hcl.example" "$TF_DIR/backend.hcl"
  cp -n "$ROOT_DIR/local/local.env.example" "$LOCAL_ENV_FILE"
  echo "Copied .example files. Edit ansible/inventory.ini, ansible/group_vars/webservers/secrets.yml, ansible/group_vars/webservers/vars.yml, terraform/terraform.tfvars, terraform/backend.hcl, and local/local.env with your own values."
}

cmd_up() {
  cmd_tf_apply
  cmd_tf_sync
  cmd_deploy_remote
}

cmd_down() {
  cmd_fvtt_sync_up
  cmd_tf_destroy
}

cmd_tf_init() {
  require_file "$TF_DIR/backend.hcl" "run './ex.sh setup' first"
  terraform -chdir="$TF_DIR" init -backend-config=backend.hcl
}

cmd_tf_apply() {
  require_file "$TF_DIR/terraform.tfvars" "run './ex.sh setup' first"
  terraform -chdir="$TF_DIR" apply -var="whitelist=$(curl -s ifconfig.me)/32"
}

cmd_tf_destroy() {
  terraform -chdir="$TF_DIR" destroy
}

cmd_tf_output() {
  terraform -chdir="$TF_DIR" output
}

cmd_tf_sync() {
  require_file "$INVENTORY" "run './ex.sh setup' first"
  require_file "$VARS_FILE" "run './ex.sh setup' first"
  local public_dns sslip_hostname
  public_dns="$(terraform -chdir="$TF_DIR" output -raw public_dns)"
  sslip_hostname="$(terraform -chdir="$TF_DIR" output -raw sslip_hostname)"

  # Replace just the hostname (first field) on the [webservers] host line, keeping ansible_* args intact
  sed -i "/^\[webservers\]/{n; s|^[^ ]*|$public_dns|}" "$INVENTORY"
  sed -i "s|^fvtt_hostname:.*|fvtt_hostname: \"$sslip_hostname\"|" "$VARS_FILE"

  echo "inventory.ini [webservers] host -> $public_dns"
  echo "vars.yml fvtt_hostname          -> $sslip_hostname"
}

cmd_ssh() {
  require_file "$INVENTORY" "run './ex.sh setup' first"
  local line host user key
  line="$(awk '/^\[webservers\]/{getline; print; exit}' "$INVENTORY")"
  host="$(awk '{print $1}' <<<"$line")"
  user="$(grep -oP 'ansible_user=\K\S+' <<<"$line")"
  key="$(grep -oP 'ansible_ssh_private_key_file=\K\S+' <<<"$line")"
  exec ssh -i "${key/#\~/$HOME}" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null "$user@$host"
}

cmd_deploy_remote() {
  require_file "$INVENTORY" "run './ex.sh setup' first"
  ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --limit webservers
}

cmd_check() {
  require_file "$INVENTORY" "run './ex.sh setup' first"
  ansible-playbook -i "$INVENTORY" "$PLAYBOOK" --check
}

cmd_fvtt_sync_up() {
  require_file "$INVENTORY" "run './ex.sh setup' first"
  ansible -i "$INVENTORY" webservers --become -m command -a /usr/local/bin/fvtt-sync-up.sh
}

cmd_local_build() {
  podman build -f "$ROOT_DIR/local/Containerfile" -t "$LOCAL_IMAGE" "$ROOT_DIR"
}

cmd_local_up() {
  require_file "$LOCAL_ENV_FILE" "copy local/local.env.example to local/local.env and fill in values"
  # Reuse a leftover container (e.g. stopped by a reboot) instead of removing it:
  # its data dir may hold changes that were never synced up to S3.
  if podman container exists "$LOCAL_CONTAINER"; then
    podman start "$LOCAL_CONTAINER"
    echo "FoundryVTT running at http://localhost:30000 (existing container restarted)"
    return
  fi
  if ! podman image exists "$LOCAL_IMAGE" 2>/dev/null; then
    cmd_local_build
  fi
  podman run -d \
    --name "$LOCAL_CONTAINER" \
    --env-file "$LOCAL_ENV_FILE" \
    -v "${HOME}/.aws:/root/.aws:ro" \
    -p 30000:30000 \
    "$LOCAL_IMAGE"
  echo "FoundryVTT running at http://localhost:30000"
}

cmd_local_sync_up() {
  podman exec "$LOCAL_CONTAINER" /usr/local/bin/fvtt-sync-up.sh
}

cmd_local_down() {
  cmd_local_sync_up
  podman stop "$LOCAL_CONTAINER"
  podman rm "$LOCAL_CONTAINER"
}

cmd_local_shell() {
  podman exec -it "$LOCAL_CONTAINER" bash
}

case "${1:-}" in
  setup)            cmd_setup ;;
  up)               cmd_up ;;
  down)             cmd_down ;;
  tf-init)          cmd_tf_init ;;
  tf-apply)         cmd_tf_apply ;;
  tf-destroy)       cmd_tf_destroy ;;
  tf-output)        cmd_tf_output ;;
  tf-sync)          cmd_tf_sync ;;
  ssh)              cmd_ssh ;;
  deploy-remote)    cmd_deploy_remote ;;
  check)            cmd_check ;;
  fvtt-sync-up)     cmd_fvtt_sync_up ;;
  local-build)      cmd_local_build ;;
  local-up)         cmd_local_up ;;
  local-down)       cmd_local_down ;;
  local-sync-up)    cmd_local_sync_up ;;
  local-shell)      cmd_local_shell ;;
  -h|--help|help|"") usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
