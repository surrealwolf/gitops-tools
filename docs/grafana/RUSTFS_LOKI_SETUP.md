# RustFS Setup for Loki

This guide describes how to configure RustFS on TrueNAS as S3-compatible object storage for Grafana Loki.

**See also:** [Grafana Stack README](README.md)

## Overview

| Component | RustFS |
|-----------|--------|
| **Storage** | RustFS on TrueNAS (native object storage) |
| **Connectivity** | External (TrueNAS host:port, e.g. 192.168.9.5:30292) |
| **Buckets** | Created manually: `loki-chunks`, `loki-ruler` |
| **Credentials** | Kubernetes secret `loki-rustfs-credentials` |

---

## Prerequisites

- TrueNAS SCALE with Apps (Kubernetes) enabled
- Kubernetes cluster (nprd-apps) with network access to TrueNAS
- Existing Loki stack deployed via Fleet (grafana/overlays/nprd-apps)

---

## Part 1: Install RustFS on TrueNAS

### 1.1 Add RustFS from Apps

1. Log in to TrueNAS SCALE
2. Go to **Apps** → **Discover Apps**
3. Search for **RustFS** (Community train)
4. Click **Install**

### 1.2 Configure RustFS

**RustFS Configuration**

| Setting | Value | Notes |
|---------|-------|-------|
| Deployment Mode | SNSD (Single Node Single Disk) | Simplest; use SNMD/MNMD for HA |
| Access Key | e.g. `loki-access-key` | Choose a value; store securely |
| Secret Key | e.g. `$(openssl rand -base64 32)` | Generate; store securely |

**User and Group**

- Default (568/rustfs) is fine

**Network Configuration**

| Setting | Value | Notes |
|---------|-------|-------|
| API Port | 30292 (default) or 9000 | S3 API; Kubernetes must reach this |
| WebUI Port | 30293 (default) | For bucket management |
| Port Bind Mode | Publish | Required for external access |
| Host IPs | Leave empty or specify | Empty = all interfaces |

**Storage Configuration**

| Setting | Value |
|---------|-------|
| Data Disks | Add ixVolume with dataset name (e.g. `loki-rustfs`) |

**Important:** Note the **Access Key** and **Secret Key**—you will need them for the Loki secret.

### 1.3 Deploy

Click **Deploy**. Wait for RustFS to become healthy.

---

## Part 2: Create Buckets in RustFS

### 2.1 Access RustFS WebUI

- URL: `http://<truenas-ip>:30293` (or your WebUI port)
- Log in with the Access Key and Secret Key (or credentials configured in the app)

### 2.2 Create Buckets

Create these buckets (exact names required by Loki):

1. **loki-chunks** – log chunk storage
2. **loki-ruler** – ruler state storage

In the RustFS WebUI:
- Click **Create Bucket**
- Enter `loki-chunks` → Create
- Repeat for `loki-ruler`

Alternatively, use the MinIO client (`mc`):

```bash
# Configure mc alias
mc alias set rustfs http://<truenas-ip>:30292 <access-key> <secret-key>

# Create buckets
mc mb rustfs/loki-chunks
mc mb rustfs/loki-ruler
```

---

## Part 2.5: Access Key Policy (Optional)

For least-privilege access, attach an IAM policy to the Loki access key restricting it to only the Loki buckets. RustFS uses AWS IAM–compatible policy format.

**Example policy** ([rustfs-loki-policy.example.json](rustfs-loki-policy.example.json)):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LokiChunksAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::loki-chunks",
        "arn:aws:s3:::loki-chunks/*"
      ]
    },
    {
      "Sid": "LokiRulerAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::loki-ruler",
        "arn:aws:s3:::loki-ruler/*"
      ]
    }
  ]
}
```

**Required actions for Loki:**
- `s3:GetObject` – read chunks and indexes
- `s3:PutObject` – write chunks and indexes
- `s3:DeleteObject` – retention/compaction cleanup
- `s3:ListBucket` – list bucket contents

Apply the policy in the RustFS UI (Access Keys → select key → Policy) or via the management API. If using the root/admin key, a policy may not be required.

---

## Part 2.6: Bucket Settings (Object Lock, Versioning, Retention)

When creating or configuring the Loki buckets, avoid enabling features that block Loki's compaction.

| Setting | Recommendation | Reason |
|---------|----------------|--------|
| **Object Lock** | **Disable** | Prevents object deletion. Loki's compactor must delete old chunks to enforce retention. Object Lock would block this and break retention. |
| **Version Control** | **Disable** | Stores multiple object versions, increasing storage and complicating deletion. Loki manages its own chunk lifecycle. |
| **Retention** | **Loki only** | Loki handles retention via `limits.retention_period` (e.g. 14 days). The compactor deletes expired chunks. |

**If RustFS requires Object Lock or versioning for retention features:** Skip RustFS-level retention entirely. Rely on Loki's built-in retention. Enabling Object Lock would prevent Loki from deleting old data and cause storage to grow unbounded.

**Which bucket needs retention?** Only `loki-chunks` stores the bulk of log data. `loki-ruler` holds small ruler state; Loki manages it. Retention is configured in Loki's Helm values, not per-bucket in RustFS.

**Optional:** If RustFS supports plain S3 lifecycle rules (delete objects older than X days) *without* requiring Object Lock or versioning, you could add a safety rule on `loki-chunks` only (e.g. delete after 18 days, longer than Loki's 14-day retention). This is a backup, not required.

---

## Part 3: Kubernetes Secret for Loki

Create a secret in the `grafana` namespace with the RustFS credentials:

```bash
kubectl create secret generic loki-rustfs-credentials \
  --from-literal=accessKeyId='<RUSTFS_ACCESS_KEY>' \
  --from-literal=secretAccessKey='<RUSTFS_SECRET_KEY>' \
  -n grafana
```

**Do NOT commit** these values to Git. Use Sealed Secrets or External Secrets for production.

---

## Part 4: Loki Helm Chart Configuration

Update `grafana/overlays/nprd-apps/loki-helmchart.yaml` to use RustFS instead of MinIO.

### 4.1 Determine RustFS Endpoint URL

- **Same network:** `http://<truenas-ip>:30292` (or your API port)
- **Hostname:** `http://rustfs.dataknife.net:30292` if you configure DNS
- **HTTPS:** Use `https://` if RustFS is configured with a certificate

Replace `<RUSTFS_ENDPOINT>` below with your URL (e.g. `http://192.168.14.10:30292`).

### 4.2 Chart Configuration

The `loki-helmchart.yaml` overlay uses RustFS and reads credentials from the `loki-rustfs-credentials` secret via `global.extraEnvFrom`. No credentials in values. Create the secret before deploying (see Part 3).

---

## Part 5: Network Connectivity

### 5.1 Verify Reachability

From a pod in the cluster:

```bash
kubectl run curl-test --rm -i --restart=Never -n grafana --image=curlimages/curl -- \
  curl -s -o /dev/null -w "%{http_code}" http://<truenas-ip>:30292/minio/health/live
```

Expected: `200` (RustFS uses MinIO-compatible health endpoint).

### 5.2 Firewall

Ensure the Kubernetes nodes can reach TrueNAS on the RustFS API port (default 30292).

### 5.3 DNS (Optional)

Create a DNS record (e.g. `rustfs.dataknife.net`) pointing to the TrueNAS IP for easier configuration and future flexibility.

---

## Part 6: Migration from MinIO

### 6.1 Data Loss

Switching from MinIO to RustFS means **starting with empty Loki storage**. Existing logs in MinIO will not be migrated automatically.

### 6.2 Migration Steps

1. **Optional:** Reduce log ingestion (Promtail/Vector) to minimize data gap
2. Create the `loki-rustfs-credentials` secret
3. Update `loki-helmchart.yaml` (disable MinIO, point to RustFS)
4. Commit and push; Fleet will sync
5. Delete MinIO StatefulSet and PVCs (they will no longer be recreated):
   ```bash
   kubectl delete statefulset loki-minio -n grafana
   kubectl get pvc -n grafana  # identify MinIO PVCs (e.g. export-*-loki-minio-0), then:
   kubectl delete pvc <pvc-name> -n grafana  # delete each MinIO PVC
   ```
6. Restart Loki components to pick up the new config:
   ```bash
   kubectl rollout restart statefulset -n grafana -l release=loki
   kubectl rollout restart deployment -n grafana -l release=loki
   ```

### 6.3 Verification

- Check Loki distributor/ingester logs for S3 errors
- Push a test log and query in Grafana Explore
- Verify buckets `loki-chunks` and `loki-ruler` show objects in RustFS WebUI

---

## Reference: Loki S3 Config (Complete)

```yaml
loki:
  storage:
    type: s3
    bucketNames:
      chunks: loki-chunks
      ruler: loki-ruler
    s3:
      endpoint: http://<TRUENAS_IP>:30292
      region: us-east-1
      bucketNames:
        chunks: loki-chunks
        ruler: loki-ruler
      accessKeyId: <from-secret>
      secretAccessKey: <from-secret>
      s3ForcePathStyle: true
```

RustFS uses path-style addressing by default, which matches Loki's `s3ForcePathStyle: true`.

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| Connection refused | Firewall, RustFS port, TrueNAS IP |
| 403 Access Denied | Access key, secret key, bucket names |
| Bucket not found | Create `loki-chunks` and `loki-ruler` in RustFS |
| TLS errors | Use `http://` if no cert, or add `insecure_skip_verify` if needed |
| Retention not working / storage growing | Disable Object Lock and versioning on buckets. Loki's compactor must be able to delete objects. |

---

## Related

- [Grafana Stack README](README.md)
- [RustFS Documentation](https://docs.rustfs.com/)
- [TrueNAS RustFS App](https://apps.truenas.com/catalog/rustfs/)
- [Loki S3 Storage](https://grafana.com/docs/loki/latest/configure/storage/)
