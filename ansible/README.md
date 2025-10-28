# Ansible Playbook — Monitoring Deployment

This directory contains the **Ansible playbook** used to deploy the full monitoring stack for the Bedrock‑WIS project.

It is executed automatically from the GitHub Actions workflow [`deploy-monitoring-ansible.yml`](../.github/workflows/deploy-monitoring-ansible.yml) and is responsible for configuring Prometheus, Alertmanager, Grafana, and related exporters via Docker Compose on the target VM.

---

## Directory Structure

```
ansible/
├── inventory.ini            # (Optional) Host inventory, usually passed inline from GitHub Actions
├── monitoring.yml           # Main Ansible playbook
│
└── roles/
    └── monitoring/
        ├── tasks/
        │   └── main.yml    # Main task file — installs Docker, renders templates, starts monitoring stack
        │
        └── templates/      # Jinja2 templates rendered on target host
            ├── .env.j2
            ├── alertmanager.yml.j2
            ├── docker-compose.yml.j2
            └── monitoring.env.j2
```

---

## Purpose and Scope

This playbook provisions and configures the **Bedrock‑WIS Monitoring Stack**, composed of:
- **Prometheus** — metrics collection
- **Alertmanager** — alert routing and Slack integration
- **Grafana** — dashboards and visualization
- **Blackbox Exporter** — endpoint reachability probes

The playbook is **idempotent** and can safely be re‑run. It installs Docker, deploys the containers, and configures them with templates rendered from GitHub Action environment variables.

---

## Execution Flow

### 1. Invoked by GitHub Actions

The workflow sets up Ansible and runs the playbook remotely via SSH:

```bash
ansible-playbook -i "${GCE_HOST}," -u "${GCE_USER}" ansible/monitoring.yml   --private-key ~/.ssh/id_rsa
```

### 2. Task Flow

1. Install and verify **Docker** is available.  
2. Create a working directory (default `/opt/monitoring` or as defined in vars).  
3. Render templates from `roles/monitoring/templates`:
   - `.env.j2` — environment variables shared across services  
   - `docker-compose.yml.j2` — service definitions  
   - `alertmanager.yml.j2` — Slack routes and receiver configuration  
   - `monitoring.env.j2` — Grafana and exporter environment variables  
4. Start or update the monitoring containers with Docker Compose.  
5. (Optional) Perform local service checks (Prometheus `/-/ready`, Grafana `/login`).

---

## Secrets and Variables

All secrets are injected by **GitHub Actions** as environment variables — no Ansible Vault is required.

| Variable | Purpose |
|-----------|----------|
| `SLACK_WEBHOOK_URL` | Slack webhook for Alertmanager |
| `SLACK_CHANNEL` | Slack destination channel |
| `GF_ADMIN_USER` | Grafana admin username |
| `GF_ADMIN_PASSWORD` | Grafana admin password |
| `GCE_HOST`, `GCE_USER` | SSH connection details |
| `GCE_DEPLOY_PATH` | Target path for deployment |

---

## Manual Usage (Optional)

To run manually from your local environment:

```bash
export GCE_HOST=34.xx.xx.xx
export GCE_USER=jure

ansible-playbook -i "${GCE_HOST}," -u "${GCE_USER}"   --private-key ~/.ssh/id_rsa ansible/monitoring.yml
```

After completion, the following services should be running:

| Service | URL | Purpose |
|----------|-----|----------|
| Prometheus | http://<host>:9090 | Metrics collection |
| Alertmanager | http://<host>:9093 | Alert routing to Slack |
| Grafana | http://<host>:3000 | Dashboards |
| Blackbox Exporter | http://<host>:9115 | Endpoint probing |

---

## Outputs and Verification

To verify deployment on the VM:

```bash
curl -fsS http://127.0.0.1:9090/-/ready        # Prometheus
curl -fsS http://127.0.0.1:9093/-/ready        # Alertmanager
curl -I    http://127.0.0.1:3000/login | head  # Grafana
```

To validate Slack notifications, trigger the **Alertmanager Slack Smoke Test** workflow (`monitoring-smoke-test.yml`).

---

## Notes

- The playbook assumes a **Docker‑based** monitoring deployment (no system packages installed).  
- All configuration files are **templated** using Jinja2; re‑running the playbook updates live configs seamlessly.  
- No credentials are stored in this repository — all sensitive values originate from **GitHub Secrets**.  
- The structure is compatible with multiple environments (dev/staging/prod) by adjusting inventory and vars.  
