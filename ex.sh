#!/usr/bin/env bash
# Convenience wrapper for the common commands in README.md.
# Run from anywhere — paths are resolved relative to this script's location.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
INVENTORY="$ROOT_DIR/ansible/inventory.ini"
PLAYBOOK="$ROOT_DIR/ansible/playbook.yml"

usage() {
  cat <<'EOF'
Usage: ./ex.sh <command>

Setup
  setup             Copy .example config files to their real (gitignored) names

Terraform (EC2)
  tf-init           terraform init -backend-config=backend.hcl
  tf-apply          terraform apply (refreshes whitelist to your current public IP)
  tf-destroy        terraform destroy
  tf-output         Show terraform outputs (e.g. public_dns for inventory.ini)
  ssh               SSH into the EC2 host (using inventory.ini connection details)

Ansible
  deploy-remote     Run the playbook against the remote EC2 host
  check             Dry run (--check) of the playbook

Backup
  fvtt-sync-up      Mirror /opt/foundrydata/Data up to the S3 backup bucket

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
  echo "Copied .example files. Edit ansible/inventory.ini, ansible/group_vars/webservers/secrets.yml, ansible/group_vars/webservers/vars.yml, terraform/terraform.tfvars and terraform/backend.hcl with your own values."
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

case "${1:-}" in
  setup)            cmd_setup ;;
  tf-init)          cmd_tf_init ;;
  tf-apply)         cmd_tf_apply ;;
  tf-destroy)       cmd_tf_destroy ;;
  tf-output)        cmd_tf_output ;;
  ssh)              cmd_ssh ;;
  deploy-remote)    cmd_deploy_remote ;;
  check)            cmd_check ;;
  fvtt-sync-up)     cmd_fvtt_sync_up ;;
  -h|--help|help|"") usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
