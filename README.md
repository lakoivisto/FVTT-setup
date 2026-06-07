# FVTT-setup

Deploys [FoundryVTT](https://foundryvtt.com/) to a remote EC2 host via Terraform + Ansible.

## 1. Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install) (for the EC2 host)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html)
- An AWS account with credentials configured (e.g. `~/.aws/credentials`)
- An S3 bucket to hold Terraform state (created once, see [backend.hcl.example](terraform/backend.hcl.example))
- An SSH key pair (default: `~/.ssh/id_ed25519` / `~/.ssh/id_ed25519.pub`)
- A FoundryVTT Linux release zip placed in `files/` (e.g. `files/FoundryVTT-Linux-14.363.zip`)
- Two S3 buckets — see [S3 setup](#s3-setup) below

## 2. Setup

Just run `./ex.sh setup` to copy all .example files at once. Then edit each file:

- **`terraform/backend.hcl`** — set your S3 bucket name/region for Terraform state

### S3 setup

Two separate S3 buckets are used:

- **Asset storage** — lets FoundryVTT serve large media (maps, tokens, music, etc.) straight from S3 instead of the instance disk. Follow FoundryVTT's own [Configuring AWS S3 guide](https://foundryvtt.com/article/aws-s3/) to create the bucket, CORS policy and an IAM user, then put that user's access key/secret into `ansible/group_vars/webservers/secrets.yml` (`fvtt_s3_access_key_id` / `fvtt_s3_secret_access_key`).
- **Data backup** — a plain bucket the EC2 instance mirrors `/opt/foundrydata/Data` to/from via `./ex.sh fvtt-sync-up` and on every service start (see [fvtt-sync-up.sh.j2](ansible/templates/fvtt-sync-up.sh.j2) / [fvtt-sync-down.sh.j2](ansible/templates/fvtt-sync-down.sh.j2)). Create it manually — it's intentionally not managed by Terraform so it persists across instance recreation — and set its name as `fvtt_backup_bucket` in `ansible/group_vars/webservers/vars.yml`. The instance reaches it via its IAM instance profile, so no keys are needed for this one.

### Optional: pre-seed FoundryVTT data files

Drop these into `files/` before deploying and the playbook will install them automatically, sparing you the first-run setup wizard:

- **`license.json`** — a previously-activated license blob (the file FoundryVTT writes to `Config/license.json` after you enter your license key and it signs successfully against foundryvtt.com). Note the signature appears to be bound to the activating machine, so a file copied from elsewhere may still need to re-activate online once deployed.
- **`admin.txt`** — the hashed admin password FoundryVTT writes to `Config/admin.txt` after you set one through the UI. Copy it from an existing instance to carry your admin password over to a fresh deployment.

Both are deployed by the [playbook](ansible/playbook.yml) (`Pre-seed FoundryVTT license...` / `Set FoundryVTT administrator password` tasks) with `mode: "0600"` since they contain credentials.

## 3. Run it

```bash
./ex.sh tf-init      # one-time: terraform init -backend-config=backend.hcl
./ex.sh up           # tf-apply + tf-sync + deploy-remote, end to end
```

Or run each step yourself if you want more control:

```bash
./ex.sh tf-apply     # creates the EC2 instance
./ex.sh tf-sync      # fills in inventory.ini and vars.yml from the terraform outputs
./ex.sh deploy-remote
```

FoundryVTT will be running at sslip_hostname e.g. fvtt.XX-XX-XXX-XXX.sslip.io



When you're done:

```bash
./ex.sh fvtt-sync-up
./ex.sh tf-destroy
```

Or just:

```bash
./ex.sh down         # fvtt-sync-up + tf-destroy, backs up your data before tearing down
```


This will destroy your Elastic IP too (so you dont pay for it), but it means you get a new IP each time you set up again after destroying it.

### Other useful commands

```bash
./ex.sh check                              # dry run (--check) of the playbook
./ex.sh                                    # list all ex.sh subcommands
```

To deploy a different FoundryVTT version, override `fvtt_version` (the zip must exist in `files/`):

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --limit webservers -e fvtt_version=14.363
```
