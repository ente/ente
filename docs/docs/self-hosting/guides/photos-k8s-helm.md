---
title: Kubernetes Helm Chart - Self-hosting
description: Deploying Ente Photos on Kubernetes using community Helm chart
---

# Kubernetes Helm Chart

Running Ente Photos on Kubernetes? There is an Helm chart that makes it easy.

If you're not familiar - [Kubernetes](https://kubernetes.io/) (K8S) handles container orchestration, [Helm](https://helm.sh/) is basically a package manager that saves you from writing tons of YAML.

This guide walks you through deploying Ente Photos using a community-maintained Helm chart.

**Chart resources:**

- [ArtifactHub](https://artifacthub.io/packages/helm/l4g/ente-photos) - helm-chart package reference
- [GitHub](https://github.com/l4gdev/helm-charts/tree/main/charts/ente-photos) - helm-chart source code

## Prerequisites

Before proceeding, ensure you have:

1. **Kubernetes cluster:**

    A running Kubernetes cluster (v1.23+) with `kubectl` configured

2. **Helm:**

    Helm 3.8+ installed on your local machine

3. **PostgreSQL database:**

    An external PostgreSQL database (v14+ recommended).

    Options include:
    - [CloudNativePG](https://cloudnative-pg.io/) (recommended for Kubernetes)
    - [Zalando PostgreSQL Operator](https://github.com/zalando/postgres-operator)
    - Managed PostgreSQL (AWS RDS, Google Cloud SQL, Azure Database, etc.)

4. **S3-compatible storage:**

    Object storage for photos and files.

    Options include:
    - AWS S3
    - Wasabi
    - Backblaze B2
    - Scaleway Object Storage
    - [Garage](https://garagehq.deuxfleurs.fr/) (self-hosted, lightweight)
    - Any S3-compatible provider

5. **Ingress controller:** (optional)

    For external access, you'll need an ingress controller such as NGINX Ingress or Traefik

6. **TLS certificates:** (recommended)

    cert-manager or pre-provisioned certificates for HTTPS

## Step 1: Add the Helm repository

Add the Helm chart repository and update:

```sh
helm repo add l4g https://l4gdev.github.io/helm-charts
helm repo update
```

Verify the repository is available:

```sh
helm search repo l4g/ente-photos
```

## Step 2: Create a values file

Visit [ArtifactHub](https://artifacthub.io/packages/helm/l4g/ente-photos) to view the chart documentation and default values. You can copy the default `values.yaml` from there and customize it for your deployment.

At minimum, you need to configure the database and S3 storage.

#### Minimal configuration

```yaml
# External PostgreSQL database (required)
externalDatabase:
    host: "your-postgres-host"
    port: 5432
    database: "ente_db"
    user: "ente"
    password: "your-secure-password"

# S3 storage configuration (required)
credentials:
    s3:
        primary:
            key: "your-s3-access-key"
            secret: "your-s3-secret-key"
            endpoint: "https://s3.your-region.amazonaws.com"
            region: "your-region"
            bucket: "your-bucket-name"
```

#### Self-hosted S3 configuration

> [!WARNING]
>
> MinIO has dropped open-source support and is no longer recommended for new deployments. Consider using [Garage](https://garagehq.deuxfleurs.fr/) or a managed S3-compatible service instead.

If you're using a self-hosted S3-compatible storage (MinIO, Garage, etc.), enable path-style URLs:

```yaml
museum:
    config:
        s3:
            areLocalBuckets: true
            usePathStyleUrls: true

credentials:
    s3:
        primary:
            key: "your-access-key"
            secret: "your-secret-key"
            endpoint: "https://s3.example.com"
            region: "us-east-1"
            bucket: "ente-photos"
            areLocalBuckets: true
```

#### CloudNativePG database

If using CloudNativePG, you can reference the generated secret:

```yaml
externalDatabase:
    host: "ente-db-rw.database.svc.cluster.local"
    port: 5432
    database: "ente_db"
    user: "ente"
    existingSecret:
        enabled: true
        secretName: "ente-db-app"
        passwordKey: "password"
```

## Step 3: Configure ingress (optional)

For external access, configure ingress for each component.

> [!TIP]
>
> **Automate certificate and DNS management**
>
> If you have [cert-manager](https://cert-manager.io/) installed, it can automatically provision TLS certificates from Let's Encrypt (or other issuers) using ingress annotations.
>
> Similarly, [external-dns](https://github.com/kubernetes-sigs/external-dns) can automatically create DNS records for your ingress hosts - no manual DNS configuration needed.
>
> Both are **highly recommended** for production Kubernetes deployments.

```yaml
# Museum API server
museum:
  ingress:
    enabled: true
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/proxy-body-size: "50g"
    hosts:
      - host: api.photos.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: ente-api-tls
        hosts:
          - api.photos.example.com

# Configure app endpoints to match your ingress
museum:
  config:
    apps:
      publicAlbums: "https://albums.photos.example.com"
      accounts: "https://accounts.photos.example.com"
      cast: "https://cast.photos.example.com"

# Photos web app
web:
  photos:
    ingress:
      enabled: true
      className: nginx
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
      hosts:
        - host: photos.example.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: ente-photos-tls
          hosts:
            - photos.example.com

  # Auth web app
  auth:
    ingress:
      enabled: true
      className: nginx
      hosts:
        - host: auth.photos.example.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: ente-auth-tls
          hosts:
            - auth.photos.example.com

  # Accounts web app
  accounts:
    ingress:
      enabled: true
      className: nginx
      hosts:
        - host: accounts.photos.example.com
          paths:
            - path: /
              pathType: Prefix
      tls:
        - secretName: ente-accounts-tls
          hosts:
            - accounts.photos.example.com
```

## Step 4: Configure email (optional)

For sending verification codes via email instead of checking logs:

```yaml
credentials:
    smtp:
        enabled: true
        host: "smtp.example.com"
        port: 587
        username: "your-smtp-username"
        password: "your-smtp-password"
        from: "noreply@example.com"
```

## Step 5: Install the chart

Create a namespace and install the chart:

```sh
kubectl create namespace ente-photos

helm install ente-photos l4g/ente-photos \
  --namespace ente-photos \
  --values values.yaml
```

Monitor the deployment:

```sh
kubectl get pods -n ente-photos -w
```

Wait for all pods to be in `Running` state.

## Step 6: Verify the installation

Check that Museum (the API server) is healthy:

```sh
kubectl exec -it deploy/ente-photos-museum -n ente-photos -- wget -qO- http://localhost:8080/ping
```

If ingress is configured, verify external access:

```sh
curl https://api.photos.example.com/ping
```

## Step 7: Create your first user

Open the Photos web app in your browser (e.g., `https://photos.example.com`).

Select **Don't have an account?** to create a new user and follow the prompts.

> [!TIP]
>
> If you haven't configured SMTP, retrieve the verification code from the Museum logs:
>
> ```sh
> kubectl logs deploy/ente-photos-museum -n ente-photos | grep -i "ott"
> ```

## Configuration reference

For a complete list of all configuration options, see the [default values on ArtifactHub](https://artifacthub.io/packages/helm/l4g/ente-photos?modal=values).

### Encryption keys

The chart automatically generates encryption keys if not provided. For production use, you should generate and store these securely:

```sh
# Generate keys using openssl
# Encryption key (32 bytes, base64 encoded)
openssl rand 32 | base64

# Hash key (64 bytes, base64 encoded)
openssl rand 64 | base64

# JWT secret (32 bytes, base64 encoded)
openssl rand 32 | base64
```

Configure in your values file:

```yaml
credentials:
    encryption:
        key: "your-generated-encryption-key"
        hash: "your-generated-hash-key"
    jwt:
        secret: "your-generated-jwt-secret"
```

> [!WARNING]
>
> If you don't provide these keys, they will be regenerated on each Helm upgrade, which will invalidate encryption keys making existing data not-accessible.
>
> **Always set explicit keys for production deployments. Remember to save them securely**

### Using existing secrets

For production deployments, store sensitive values in Kubernetes secrets:

```yaml
credentials:
    existingSecret: "my-ente-credentials"

externalDatabase:
    host: "your-postgres-host"
    existingSecret:
        enabled: true
        secretName: "my-postgres-credentials"
        passwordKey: "password"
```

The credentials secret should contain a `credentials.yaml` key with the complete credentials configuration.

### Disabling web frontends

If you only need the API server (e.g., for mobile apps only):

```yaml
web:
    photos:
        enabled: false
    auth:
        enabled: false
    accounts:
        enabled: false
    share:
        enabled: false
```

### Resource limits

Configure resource requests and limits for production:

```yaml
museum:
    resources:
        requests:
            cpu: 200m
            memory: 256Mi
        limits:
            cpu: 1000m
            memory: 1Gi

web:
    photos:
        resources:
            requests:
                cpu: 50m
                memory: 64Mi
            limits:
                cpu: 200m
                memory: 256Mi
```

## Upgrading

To upgrade to a new chart version:

```sh
helm repo update
helm upgrade ente-photos l4g/ente-photos \
  --namespace ente-photos \
  --values values.yaml
```

## Uninstalling

To remove the deployment:

```sh
helm uninstall ente-photos --namespace ente-photos
```

> [!WARNING]
>
> This does not delete persistent data in your database or S3 storage.
>
> Clean up those resources manually if needed.

## Troubleshooting

### Database connection issues

Check PostgreSQL connectivity:

```sh
kubectl exec -it deploy/ente-photos-museum -n ente-photos -- \
  sh -c 'wget -qO- "http://localhost:8080/ping"'
```

View Museum logs for database errors:

```sh
kubectl logs deploy/ente-photos-museum -n ente-photos | grep -i "database\|postgres"
```

### S3 connection issues

Verify S3 credentials and endpoint:

```sh
kubectl logs deploy/ente-photos-museum -n ente-photos | grep -i "s3\|bucket"
```

### Pod startup failures

Check pod events and logs:

```sh
kubectl describe pod -l app.kubernetes.io/name=ente-photos -n ente-photos
kubectl logs -l app.kubernetes.io/name=ente-photos -n ente-photos --all-containers
```

## What next?

After installation, you may want to:

- [Configure apps](/self-hosting/installation/post-install/#step-6-configure-apps-to-use-your-server) to connect mobile apps to your server
- [Configure object storage](/self-hosting/administration/object-storage) for advanced S3 settings and CORS configuration
- [Manage users](/self-hosting/administration/users) to configure admin access and user management
