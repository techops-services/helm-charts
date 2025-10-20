# Discourse Helm Chart

This chart deploys the [Discourse](https://www.discourse.org/) application together with optional PostgreSQL and Redis dependencies. It ships with opinionated defaults for both a cost-conscious staging environment and a highly-available production setup that integrates with managed AWS services.

## Features

- Discourse web and Sidekiq deployments based on the official `discourse/discourse:beta` image
- Optional single-instance PostgreSQL (StatefulSet) and Redis (Deployment) for staging
- External RDS and ElastiCache integration for production
- Configurable Ingress for NGINX and AWS Load Balancer Controller
- S3-based uploads configuration with separate backup bucket
- Horizontal Pod Autoscaler for production web tier
- Network policies and PodDisruptionBudgets (opt-in)

## Repository Layout

```
discourse/
├── Chart.yaml
├── README.md
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── configmap.yaml
    ├── secret.yaml
    ├── deployment-web.yaml
    ├── deployment-sidekiq.yaml
    ├── service-web.yaml
    ├── ingress.yaml
    ├── hpa-web.yaml
    ├── serviceaccount.yaml
    ├── networkpolicy.yaml
    ├── pdb-*.yaml
    ├── postgresql-*.yaml
    └── redis-*.yaml
```

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- AWS CLI configured with access to the target account (for S3/RDS/ElastiCache/ALB management)
- Existing ACM certificate in the target region for production ingress
- Container registry access to pull `discourse/discourse:beta`

## Configuration

Base settings live in `values.yaml` and are shared between environments. Key sections include:

- `config.*`: Hostname, database, Redis, S3, and SMTP settings exposed to the web and Sidekiq pods.
- `secrets.*`: Sensitive values that are rendered into a Kubernetes Secret. **Do not commit real credentials.**
- `postgresql.*` / `redis.*`: Toggle embedded services and persistence options.
- `web.*` / `sidekiq.*`: Pod-level settings, resources, probes, and autoscaling.
- `ingress.*`: Ingress class, annotations, hosts, and TLS.
- `networkPolicy.*`: Optional traffic controls per component.
- `podDisruptionBudget.*`: Optional hardening controls.


## Deploying Staging (All-In-Cluster)

1. Create (and version) copies of `values.yaml` with real secrets, or supply them at install time via `--set-file` / `--set`.
2. Ensure the target namespace exists:

   ```bash
   kubectl create namespace discourse-staging
   ```

3. Deploy the chart:

   ```bash
   helm upgrade --install discourse-staging ./discourse \
     --namespace discourse-staging \
     -f discourse/values.yaml \
     -f discourse/values-staging.yaml
   ```

4. Run database migrations once pods are healthy:

   ```bash
   kubectl exec deployment/discourse-staging-web -n discourse-staging -- \
     bundle exec rake db:migrate
   ```

5. Seed an admin account if required:

   ```bash
   kubectl exec deployment/discourse-staging-web -n discourse-staging -- \
     bundle exec rake admin:create
   ```

## Deploying Production (AWS Managed Services)

1. Provision AWS resources:
   - **RDS PostgreSQL 14+** (Multi-AZ) and note the cluster endpoint, username, and password.
   - **ElastiCache Redis** (Multi-AZ) and note the primary endpoint and password if enabled.
   - **S3 buckets** for uploads and backups with the desired storage classes.
   - **ACM certificate** in the same region as the EKS cluster.

2. Update `values-production.yaml` with the endpoints, bucket names, SMTP settings, and secrets.

3. Deploy:

   ```bash
   kubectl create namespace discourse-prod

   helm upgrade --install discourse-prod ./discourse \
     --namespace discourse-prod \
     -f discourse/values.yaml \
     -f discourse/values-production.yaml
   ```

4. After deployment, run migrations and reseed admins as shown in the staging section (adjust the namespace).

## Operations

- **Upgrades**: Update the image tag in your values file and rerun `helm upgrade`. Always follow up with `kubectl rollout status` for both deployments.
- **Backups**: Staging relies on EBS snapshots for PostgreSQL/Redis PVCs. Production uses managed RDS/ElastiCache backups and S3 versioning. Establish recurring cross-account exports as needed.
- **Restarts**: Use `kubectl rollout restart deployment/discourse-prod-web` (and `-sidekiq`) to pick up config changes.
- **Log collection**: Stream logs via `kubectl logs -f deployment/discourse-prod-web` or forward them to CloudWatch/ELK using your preferred DaemonSet.
- **Metrics**: Integrate with Prometheus by enabling scraping annotations or sidecar exporters. Web HPA thresholds default to 65% CPU.
- **Secrets rotation**: Update the relevant entries under `secrets.*` and run `helm upgrade`. Redis/PostgreSQL pods will recycle automatically when the secret hash changes.

## Migration Checklist

- [ ] Confirm EKS cluster nodes provide sufficient CPU/memory (see `resources` requests).
- [ ] Validate DNS records point to the ingress controller/ALB once deployed.
- [ ] Upload site settings (`app.yml`) into environment variables or the UI post-migration.
- [ ] Reconfigure SSO providers and email once the new hostname resolves.
- [ ] Test large uploads to verify S3 credentials and bucket policies.
- [ ] Exercise backup and rollback procedures before cutover.

## TLS/Certificate Configuration

### Using cert-manager

If you have cert-manager installed in your cluster, you can automatically provision TLS certificates:

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: forum.example.com
      paths:
        - path: /
          pathType: Prefix
  certManager:
    enabled: true
    issuerName: letsencrypt-prod
    issuerKind: ClusterIssuer
    # secretName: forum-tls  # Optional, defaults to <release>-discourse-tls
    duration: 2160h  # 90 days
    renewBefore: 720h  # 30 days
```

### Using existing TLS secret

If you already have a TLS secret:

```yaml
ingress:
  enabled: true
  tls:
    - secretName: existing-tls-secret
      hosts:
        - forum.example.com
```

## Environment Variables Configuration

The chart supports flexible environment variable configuration with multiple sourcing options:

### Variable Types

1. **kv (Key-Value)**: Hardcoded values directly in values.yaml
2. **parameterStore**: AWS Parameter Store via External Secrets Operator
3. **secret**: Reference to existing Kubernetes Secret
4. **configmapRef**: Reference to existing ConfigMap

### Examples

```yaml
externalSecrets:
  clusterSecretStoreName: aws-parameter-store
  refreshInterval: 1m

env:
  # Hardcoded value
  DISCOURSE_SMTP_DOMAIN:
    type: kv
    value: example.com

  # From AWS Parameter Store
  DISCOURSE_SECRET_KEY_BASE:
    type: parameterStore
    name: secret-key-base
    parameter_name: /discourse/prod/secret-key-base

  # From existing Kubernetes Secret
  API_KEY:
    type: secret
    name: discourse-api-keys
    key: api-key

  # From existing ConfigMap
  CUSTOM_CONFIG:
    type: configmapRef
    name: discourse-custom-config
    key: custom-value
```

### Prerequisites for parameterStore type

- External Secrets Operator must be installed
- ClusterSecretStore must be configured
- IAM permissions for accessing Parameter Store

## IRSA Configuration for S3 Access

Instead of using static AWS credentials, you can configure IAM Roles for Service Accounts (IRSA) to grant Discourse pods access to S3 buckets.

### Prerequisites

1. Create an IAM role with appropriate S3 permissions
2. Configure the trust policy to allow your EKS service account to assume the role
3. Ensure your EKS cluster has an OIDC provider configured

### Configuration

Add the IAM role ARN to your values file:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME

config:
  discourseS3Bucket: your-bucket-name
  discourseS3BackupBucket: your-bucket-name  # Can be the same bucket with different prefix
  discourseS3UploadsPrefix: uploads/
  discourseS3BackupsPrefix: backups/

# When using IRSA, S3 credentials are not required
secrets:
  s3AccessKeyId: ""
  s3SecretAccessKey: ""
```

### Example for Staging

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::068992353948:role/eks-forum-staging-discourse-s3

config:
  discourseS3Bucket: forum-staging.sky.money
  discourseS3BackupBucket: forum-staging.sky.money
  discourseS3UploadsPrefix: uploads/
  discourseS3BackupsPrefix: backups/
```

## Development Notes

- The rendered manifests assume Kubernetes DNS is available (`kube-dns` / `CoreDNS`).
- When using IRSA for S3 access, the `secrets.s3AccessKeyId` and `secrets.s3SecretAccessKey` values can be left empty.
- Enable `networkPolicy.*` and `podDisruptionBudget.*` only after verifying HPA and replica counts satisfy availability goals.

## Removing the Stack

```bash
helm uninstall discourse-staging -n discourse-staging
kubectl delete namespace discourse-staging
```

Repeat for production after ensuring traffic has already switched off the cluster.
