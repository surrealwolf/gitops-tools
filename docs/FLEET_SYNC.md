# Fleet Sync Guide

Troubleshooting and reference for Rancher Fleet agent registration and bundle sync.

## Quick Reference

| Fleet cluster ID | Display name | kubectl context |
|------------------|--------------|-----------------|
| c-wnfsj | nprd-apps | nprd-apps |
| c-ps6zm | prd-apps | prd-apps |
| c-k7zls | poc-apps | poc-apps |

## Issue 1: TLS Certificate Verification Failure

### Symptoms

- Fleet agent cannot register with Rancher Manager
- Cluster shows `WaitCheckIn` or bundles stuck in `NotReady`
- Agent logs: `tls: failed to verify certificate: x509: certificate signed by unknown authority`
- `fleet-agent` secret does not exist

### Root Cause

The `fleet-agent-bootstrap` secret has **empty `apiServerCA`**. Rancher's import token does not populate this when the API is exposed via external ingress (e.g. Let's Encrypt) instead of the cluster CA.

### Fix

Patch the bootstrap secret with the CA that signs the Rancher ingress certificate:

```bash
# Extract Let's Encrypt R12 intermediate CA from rancher.dataknife.net
echo | openssl s_client -connect rancher.dataknife.net:443 -servername rancher.dataknife.net -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > /tmp/chain.pem
csplit -s -f /tmp/cert- /tmp/chain.pem '/-----BEGIN CERTIFICATE-----/' '{*}'
R12_CA=$(cat /tmp/cert-02)
NEW_CA=$(echo -n "$R12_CA" | base64 -w0)

# Patch (replace CONTEXT with cluster context)
kubectl config use-context CONTEXT
kubectl get secret fleet-agent-bootstrap -n cattle-fleet-system -o json \
  | jq --arg ca "$NEW_CA" '.data.apiServerCA = $ca' | kubectl apply -f -

kubectl rollout restart deployment/fleet-agent -n cattle-fleet-system
```

---

## Issue 2: Registration Unauthorized (After TLS Fix)

### Symptoms

- Agent logs: `Post ".../clusterregistrations": Unauthorized`
- TLS verification passes

### Root Cause

Cluster registration token is invalid or expired.

### Fix

1. Rancher UI → **Cluster Management** → select cluster → **Registration** → generate new import token
2. Re-import or update the cluster's bootstrap configuration
3. Re-apply the apiServerCA patch if a new bootstrap secret is created

---

## Issue 3: Helm Namespace Adoption Failure

### Symptoms

- Bundle stuck: `Namespace "grafana" exists and cannot be imported: invalid ownership metadata`

### Fix

Add Helm metadata so Helm can adopt the existing namespace:

```bash
kubectl annotate namespace grafana \
  meta.helm.sh/release-name=gitops-tools-nprd-apps-grafana-overlays-nprd-apps \
  meta.helm.sh/release-namespace=grafana --overwrite
kubectl label namespace grafana app.kubernetes.io/managed-by=Helm --overwrite
```

---

## Issue 4: Helm ClusterRole Adoption Failure

### Symptoms

- `ClusterRole "loki-clusterrole" exists and cannot be imported` (or grafana, promtail)

### Fix

**Option A – Adopt:** Patch annotations so Helm can adopt:
```bash
kubectl annotate clusterrole loki-clusterrole \
  meta.helm.sh/release-name=loki meta.helm.sh/release-namespace=grafana --overwrite
# Repeat for loki-clusterrolebinding, grafana-clusterrole, grafana-clusterrolebinding, promtail (role + binding)
kubectl delete job -n grafana helm-install-loki helm-install-grafana helm-install-promtail
```

**Option B – Delete orphaned resources:**
```bash
kubectl delete clusterrole loki-clusterrole grafana-clusterrole promtail
kubectl delete clusterrolebinding loki-clusterrolebinding grafana-clusterrolebinding promtail
kubectl delete job -n grafana helm-install-loki helm-install-grafana helm-install-promtail
```

Do **not** delete ClusterRoles from other tools you still use.

---

## Issue 5: Bundle Status Stale

### Fix

1. Restart fleet-agent: `kubectl rollout restart deployment/fleet-agent -n cattle-fleet-system`
2. Bump forceSyncGeneration: `kubectl patch bundledeployment <NAME> -n <NS> --type=merge -p '{"spec":{"options":{"forceSyncGeneration":'$(date +%s)'}}}'`
3. Wait 1–2 minutes for agent to report back

---

## Related

- [FLEET_STRUCTURE.md](FLEET_STRUCTURE.md) – GitOps paths and overlay pattern
- [docs/grafana/README.md](grafana/README.md) – Grafana Fleet troubleshooting
