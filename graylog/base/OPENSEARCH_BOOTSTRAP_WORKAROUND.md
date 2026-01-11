# OpenSearch Bootstrap Password Workaround

## Problem

The OpenSearch Kubernetes Operator (v2.8.0) has a limitation where bootstrap pods don't inherit environment variables from `nodePools`. This causes bootstrap pods to fail with OpenSearch 2.12+ which requires `OPENSEARCH_INITIAL_ADMIN_PASSWORD`.

**Error:** `No custom admin password found. Please provide a password via the environment variable OPENSEARCH_INITIAL_ADMIN_PASSWORD.`

**References:**
- [Issue #409](https://github.com/opensearch-project/opensearch-k8s-operator/issues/409)
- [Issue #867](https://github.com/opensearch-project/opensearch-k8s-operator/issues/867)

## Recommended Solution: MutatingAdmissionWebhook

A MutatingAdmissionWebhook automatically injects `OPENSEARCH_INITIAL_ADMIN_PASSWORD` into bootstrap pods when they are created. This is the most GitOps-friendly approach.

### Architecture

```
Bootstrap Pod Creation Request
    ↓
MutatingAdmissionWebhook (intercepts)
    ↓
Webhook Server (reads secret, creates JSON patch)
    ↓
Pod Created with OPENSEARCH_INITIAL_ADMIN_PASSWORD injected
```

### Prerequisites

1. **Webhook server deployment** (see implementation options below)
2. **TLS certificate** for webhook server
   - Certificate for: `opensearch-bootstrap-webhook.managed-tools.svc`
   - Can use cert-manager or manual certificate

### Implementation Options

#### Option 1: Simple Python Webhook Server (Recommended for GitOps)

Create a simple Flask-based webhook server that:
- Listens for pod creation requests
- Identifies bootstrap pods (name ends with `-bootstrap-0`)
- Reads password from `graylog-opensearch-admin-password` secret
- Returns JSON patch to inject environment variable

**Files:**
- `opensearch-bootstrap-webhook-server.yaml` - Deployment, Service, RBAC
- `opensearch-bootstrap-webhook.yaml` - MutatingWebhookConfiguration

**Note:** For production, consider using a more robust webhook server implementation or existing tools.

#### Option 2: Kyverno Policy (Simpler if Kyverno is available)

If Kyverno is installed in the cluster, use a MutatingPolicy:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: opensearch-bootstrap-password
spec:
  rules:
    - name: inject-opensearch-password
      match:
        resources:
          kinds:
            - Pod
          namespaces:
            - managed-tools
          name: "*-bootstrap-0"
      mutate:
        patchStrategicMerge:
          spec:
            containers:
              - (name): "opensearch"
                env:
                  - name: OPENSEARCH_INITIAL_ADMIN_PASSWORD
                    valueFrom:
                      secretKeyRef:
                        name: graylog-opensearch-admin-password
                        key: password
```

#### Option 3: Custom Controller (Most flexible but complex)

Create a custom Kubernetes controller that:
- Watches for bootstrap pods
- Patches them to inject the environment variable
- Can be deployed via GitOps

### Deployment Steps (Option 1: Webhook)

1. **Deploy webhook server:**
   ```bash
   kubectl apply -f graylog/base/opensearch-bootstrap-webhook-server.yaml
   ```

2. **Create TLS certificate:**
   
   **Using cert-manager (recommended):**
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: opensearch-bootstrap-webhook-cert
     namespace: managed-tools
   spec:
     secretName: opensearch-bootstrap-webhook-cert
     issuerRef:
       name: selfsigned-issuer
       kind: ClusterIssuer
     dnsNames:
       - opensearch-bootstrap-webhook.managed-tools.svc
   ```
   
   **Manual certificate:**
   ```bash
   # Generate certificate (example using openssl)
   openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes \
     -subj "/CN=opensearch-bootstrap-webhook.managed-tools.svc"
   
   # Create secret
   kubectl create secret tls opensearch-bootstrap-webhook-cert \
     --cert=cert.pem --key=key.pem -n managed-tools
   ```

3. **Update MutatingWebhookConfiguration with CA bundle:**
   ```bash
   # Extract CA bundle
   CA_BUNDLE=$(kubectl get secret opensearch-bootstrap-webhook-cert -n managed-tools \
     -o jsonpath='{.data.ca\.crt}')
   
   # Patch webhook config
   kubectl patch mutatingwebhookconfiguration opensearch-bootstrap-password-webhook \
     --type='json' -p="[{\"op\": \"replace\", \"path\": \"/webhooks/0/clientConfig/caBundle\", \"value\": \"${CA_BUNDLE}\"}]"
   ```

4. **Deploy webhook configuration:**
   ```bash
   kubectl apply -f graylog/base/opensearch-bootstrap-webhook.yaml
   ```

### Testing

1. **Delete bootstrap pod to trigger recreation:**
   ```bash
   kubectl delete pod graylog-opensearch-bootstrap-0 -n managed-tools
   ```

2. **Verify environment variable is injected:**
   ```bash
   kubectl describe pod graylog-opensearch-bootstrap-0 -n managed-tools | grep -A 15 "Environment:"
   ```

3. **Check pod logs:**
   ```bash
   kubectl logs graylog-opensearch-bootstrap-0 -n managed-tools
   ```

4. **Verify pod starts successfully:**
   ```bash
   kubectl get pod graylog-opensearch-bootstrap-0 -n managed-tools
   ```

### GitOps Integration

All components can be managed via Fleet/GitOps:

**Add to `graylog/base/kustomization.yaml`:**
```yaml
resources:
  - opensearch-bootstrap-webhook-server.yaml
  - opensearch-bootstrap-webhook.yaml
```

**Note:** The `caBundle` in MutatingWebhookConfiguration needs to be updated after certificate creation. This can be automated with:
- cert-manager webhook certificate injection
- Kustomize patches
- Post-render hooks in Fleet

### Limitations

1. **TLS Required:** MutatingAdmissionWebhooks require valid TLS certificates
2. **Certificate Management:** Need to manage certificate rotation
3. **Webhook Server:** Additional component to maintain (but simple)
4. **Performance:** Adds small latency to pod creation (typically <100ms)
5. **Webhook Server Deployment:** Requires deployment and service

### Alternative: Temporary Manual Patch (Not GitOps)

As a temporary workaround, you can manually patch the bootstrap pod after creation:

```bash
# Get password from secret
PASSWORD=$(kubectl get secret graylog-opensearch-admin-password -n managed-tools \
  -o jsonpath='{.data.password}' | base64 -d)

# Patch pod
kubectl patch pod graylog-opensearch-bootstrap-0 -n managed-tools --type='json' \
  -p="[{\"op\": \"add\", \"path\": \"/spec/containers/0/env/-\", \"value\": {\"name\": \"OPENSEARCH_INITIAL_ADMIN_PASSWORD\", \"value\": \"${PASSWORD}\"}}]"
```

**Warning:** This patch will be lost if the pod is recreated by the operator. The webhook approach is required for a permanent solution.

### Future

This workaround should be removed once the OpenSearch Kubernetes Operator supports injecting environment variables into bootstrap pods.

Monitor these issues for updates:
- [Issue #409](https://github.com/opensearch-project/opensearch-k8s-operator/issues/409)
- [Issue #867](https://github.com/opensearch-project/opensearch-k8s-operator/issues/867)
