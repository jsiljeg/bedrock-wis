# Monitoring Stack Configuration

This directory contains all **static and templated configuration** for the Bedrock‑WIS monitoring stack.  
It is deployed automatically by the Ansible playbook in `../ansible/monitoring.yml`.

---

## Components

| Service | Description | Default Port |
|----------|--------------|--------------|
| **Prometheus** | Core metrics collection | 9090 |
| **Alertmanager** | Handles alerts and sends notifications to Slack | 9093 |
| **Grafana** | Visualization and dashboards | 3000 |
| **Blackbox Exporter** | Endpoint probe checks for HTTP/ICMP | 9115 |

---

## Directory Layout

```
monitoring/
├── .env                     # Environment file (live, generated from template)
├── .env.template             # Example template for local customization
├── docker-compose.yml        # Docker Compose stack definition
│
├── alertmanager/
│   ├── alertmanager.yml.j2   # Jinja2 template used by Ansible
│   └── templates/
│       └── slack.tmpl        # Slack message template
│
├── blackbox/
│   └── blackbox.yml          # Probe targets and configuration
│
├── grafana/
│   ├── dashboards/
│   │   └── bedrock-node-and-uptime.json  # Predefined dashboard
│   └── provisioning/
│       ├── dashboards/dashboards.yaml    # Dashboard provisioning definition
│       └── datasources/datasource.yaml   # Default Prometheus datasource
│
└── prometheus/
    ├── prometheus.yml.j2     # Scrape targets template
    └── rules.yml             # Alerting and recording rules
```

---

## Key Concepts

### Prometheus
- Scrapes metrics from exporters (e.g., node exporter, blackbox exporter).
- Uses `prometheus.yml.j2` to dynamically include VM‑specific or service targets.
- Alerts are defined in `rules.yml` and routed through Alertmanager.

### Alertmanager
- Receives alerts and dispatches notifications to Slack using the `slack.tmpl` template.
- Slack routing and labels are configured in `alertmanager.yml.j2` (rendered by Ansible).

### Grafana
- Auto‑provisions dashboards and datasources via files in `grafana/provisioning`.
- Default admin credentials come from GitHub Secrets (injected by Ansible).

### Blackbox Exporter
- Used for simple external reachability checks.
- Configured via `blackbox/blackbox.yml`.

---

## Local Testing (Optional)

Run the monitoring stack manually (for debugging outside CI/CD):

```bash
cd monitoring
cp .env.template .env
docker compose up -d
```

Then open:
- Prometheus: http://localhost:9090
- Alertmanager: http://localhost:9093
- Grafana: http://localhost:3000 (default creds from `.env`)

---

## Integration with CI/CD

- Deployed by the **Ansible playbook** during `Deploy Monitoring` workflow.
- Post‑deployment health probes are performed by the GitHub Actions job `monitoring_probe`.
- Slack alerting can be validated using the **`Alertmanager Slack Smoke Test`** workflow.

---

## Notes

- All configuration files are **templated** via Ansible using environment‑specific variables.
- Sensitive data (Slack tokens, Grafana passwords) are not stored in this repo — they are injected from **GitHub Secrets**.
- To add new dashboards, drop `.json` files into `grafana/dashboards/` and update `dashboards.yaml` accordingly.
- To add new alerting rules, edit `prometheus/rules.yml`.
