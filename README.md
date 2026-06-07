# FVTT-setup

Deploys [FoundryVTT](https://foundryvtt.com/) to a remote EC2 host (via Terraform + Ansible) or a local Podman/Docker container (via Ansible).

## 1. Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install) (for the EC2 host)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html), plus the `community.docker` collection:
  ```bash
  ansible-galaxy collection install community.docker
  ```
- An AWS account with credentials configured (e.g. `~/.aws/credentials`)
- An S3 bucket to hold Terraform state (created once, see [backend.hcl.example](terraform/backend.hcl.example))
- An SSH key pair (default: `~/.ssh/id_ed25519` / `~/.ssh/id_ed25519.pub`)
- A FoundryVTT Linux release zip placed in `files/` (e.g. `files/FoundryVTT-Linux-14.363.zip`)
- Podman or Docker, only if deploying to a local container instead of EC2

## 2. Setup

Copy the example config files and fill in your own values — the real copies are gitignored so your host details, IP and key paths never get committed:

```bash
cp ansible/inventory.ini.example ansible/inventory.ini
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp terraform/backend.hcl.example terraform/backend.hcl
```

Then edit each file:

- **`ansible/inventory.ini`** — under `[webservers]`, set your EC2 hostname (filled in after `terraform apply`, step 3 below) and SSH key path; under `[containers]`, set your local container name
- **`terraform/terraform.tfvars`** — set `whitelist` to your public IP in CIDR form (e.g. `1.2.3.4/32`, get it with `curl -s ifconfig.me`), and `ssh_public_key_path` if your key isn't the default
- **`terraform/backend.hcl`** — set your S3 bucket name/region for Terraform state

Or just run `./ex.sh setup` to copy all three at once.

## 3. Run it

### Option A — Deploy to a remote EC2 host

```bash
./ex.sh tf-init      # one-time: terraform init -backend-config=backend.hcl
./ex.sh tf-apply     # creates the EC2 instance
./ex.sh tf-output    # copy the public_dns value into ansible/inventory.ini under [webservers]
./ex.sh deploy-remote
```

FoundryVTT will be running at `http://<public_dns>:30000`.

When you're done:

```bash
./ex.sh tf-destroy
```

### Option B — Deploy to a local Podman/Docker container

```bash
podman run -d --name testbox ubuntu:24.04 sleep infinity
./ex.sh deploy-container
```

Check it started:

```bash
podman exec testbox cat /var/log/foundryvtt.log
```

Tear down:

```bash
podman rm -f testbox
```

### Other useful commands

```bash
./ex.sh check                              # dry run (--check) of the playbook
./ex.sh                                    # list all ex.sh subcommands
```

To deploy a different FoundryVTT version, override `fvtt_version` (the zip must exist in `files/`):

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --limit webservers -e fvtt_version=14.363
```
