# Terraform Infrastructure Overview

This directory defines the complete infrastructure-as-code stack for the **Bedrock‑WIS** project.  
It follows a modular, layered structure designed for clarity and reusability across environments.

```
terraform/
├── environments/
│   └── development/
│       ├── terraform-state-infra/   → Remote state backend (GCS + SA)
│       ├── environment/             → Common network & IAM setup
│       └── bedrock-wis/             → Application VM and startup bootstrap
└── modules/
    ├── terraform-state/             → Reusable module for remote state infra
    ├── environment/                 → Reusable network/IAM module
    └── bedrock/                     → Reusable module for Bedrock VM
```

---

## Layered Overview

### 1️⃣ Terraform State Infrastructure
**Path:** `environments/development/terraform-state-infra`  
**Module:** [`modules/terraform-state`](../../modules/terraform-state)

Responsible for creating and configuring the **remote state backend** and **service account**.

- Provisions a **GCS bucket** for Terraform state (`google_storage_bucket.tfstate`).
- Optionally creates a **dedicated service account** (`google_service_account.tfstate_sa`).
- Grants `objectAdmin` / `viewer` roles to the service account.
- Outputs the bucket name, URL, and service account email.

**Inputs**
- `project_id` — Target GCP project ID.
- `bucket_name` — Globally unique name for the state bucket.
- `location` — Region (e.g., `EUROPE-NORTH1`).
- Optional: `create_service_account`, `sa_account_id`.

---

### 2️⃣ Environment Layer
**Path:** `environments/development/environment`  
**Module:** [`modules/environment`](../../modules/environment)

Defines shared **networking, subnets, and IAM** resources used by applications.

- Creates:
  - VPC network (`google_compute_network.vpc`)
  - Subnet (`google_compute_subnetwork.subnet`)
  - Service account for compute workloads
  - Simple firewall allowing SSH/HTTP/HTTPS
- Outputs:
  - `network_self_link`
  - `subnet_self_link`
  - `service_account_email`

**Inputs**
- `project_id`, `project_prefix`, `region`.

This layer must be applied **before** application-specific layers so they can reference its outputs.

---

### 3️⃣ Application Layer (Bedrock‑WIS)
**Path:** `environments/development/bedrock-wis`  
**Module:** [`modules/bedrock`](../../modules/bedrock)

Deploys the **application VM** hosting Bedrock WordPress with a custom startup script.  
It consumes outputs from the environment layer through a `terraform_remote_state` data source.

- Creates:
  - Static external IP
  - Compute instance with startup script
  - Firewall rules for SSH and web
- Configures the VM to auto‑install Bedrock via `startup_script.sh`
- Outputs:
  - `vm_public_ip` — used in CI/CD for health checks
  - `deploy_path` — `/var/www/bedrock`
  - `ssh_user`
  - `healthcheck_url`

**Inputs**
- `project_id`, `region`, `zone`
- `network_self_link`, `subnet_self_link`, `service_account_email`
- `instance_type`
- `ssh_public_key_path` (points to `keys/bedrock-wis.pub`)
- Optional: `web_source_ranges`, `ssh_source_ranges`

---

## Module Summaries

### `modules/terraform-state`
Reusable state‑backend module for other environments.

Creates:
- GCS bucket for remote state.
- Optional service account for CI/CD pipelines.

### `modules/environment`
Reusable network + IAM module.

Creates:
- VPC, subnet, service account, and firewall.
- Supports multi‑environment deployment (development/staging/production).

### `modules/bedrock`
Application deployment module.

Creates:
- GCE VM + static IP.
- Configures Bedrock + WordPress stack via `startup_script`.
- Returns connection info and healthcheck endpoints for CI/CD workflows.

---

## Usage Flow

1. **Bootstrap remote state**
   ```bash
   cd environments/development/terraform-state-infra
   terraform init
   terraform apply
   ```

2. **Provision networking layer**
   ```bash
   cd ../environment
   terraform init
   terraform apply
   ```

3. **Deploy application VM**
   ```bash
   cd ../bedrock-wis
   terraform init
   terraform apply
   ```

Each layer depends on outputs from the previous one, stored in remote state.

---

## Outputs Consumed by CI/CD

The GitHub Actions pipeline (`.github/workflows/deploy.yml`) reads the following Terraform outputs from the Bedrock layer:

| Output | Used for |
|---------|----------|
| `vm_public_ip` | SSH and health checks |
| `ssh_user` | VM login during deploy |
| `deploy_path` | Target path for rsync + releases |
| `healthcheck_url` | CI health probe after deploy |

---

## Notes

- All state files are stored remotely in the GCS bucket created by `terraform-state-infra`.
- Environment and Bedrock layers use **data sources** (`terraform_remote_state`) to pull dependencies.
- Each module is **standalone** and version‑locked to Terraform ≥ 1.5 and Google provider ≥ 5.0.
- CI/CD relies on Terraform outputs — do not rename or remove them without adjusting workflows.
- To extend for staging/production: copy `environments/development/` and adjust `terraform.tfvars` and backend configs.
