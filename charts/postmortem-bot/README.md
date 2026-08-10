# Postmortem Bot Helm Chart

This Helm chart deploys the Postmortem Automation Bot to your Kubernetes cluster, including both the webhook server and Discord bot.

## Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.x
- Docker image built and pushed to container registry

## Installation

### Quick Install

```bash
helm install postmortem-bot ./helm/postmortem-bot
```

### Install with Custom Values

```bash
helm install postmortem-bot ./helm/postmortem-bot \
  --set webhook.image.repository=ghcr.io/techops-services/postmortem-automation \
  --set webhook.image.tag=v1.0.0 \
  --set discordbot.image.repository=ghcr.io/techops-services/postmortem-automation \
  --set discordbot.image.tag=v1.0.0
```

### Install with Values File

Create a `custom-values.yaml`:

```yaml
webhook:
  enabled: true
  replicaCount: 2
  image:
    repository: ghcr.io/techops-services/postmortem-automation
    tag: v1.0.0
  env:
    - name: PAGERDUTY_API_KEY
      valueFrom:
        secretKeyRef:
          name: postmortem-secrets
          key: pagerduty-api-key
    - name: DISCORD_WEBHOOK_URL
      valueFrom:
        secretKeyRef:
          name: postmortem-secrets
          key: discord-webhook-url

discordbot:
  enabled: true
  replicaCount: 1
  image:
    repository: ghcr.io/techops-services/postmortem-automation
    tag: v1.0.0
  env:
    - name: DISCORD_BOT_TOKEN
      valueFrom:
        secretKeyRef:
          name: postmortem-secrets
          key: discord-bot-token
```

Then install:

```bash
helm install postmortem-bot ./helm/postmortem-bot -f custom-values.yaml
```

## Configuration

### Webhook Server Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `webhook.enabled` | Enable webhook deployment | `true` |
| `webhook.replicaCount` | Number of replicas | `1` |
| `webhook.image.repository` | Image repository | `ghcr.io/techops-services/postmortem-automation` |
| `webhook.image.tag` | Image tag | `latest` |
| `webhook.service.type` | Service type | `ClusterIP` |
| `webhook.service.port` | Service port | `8080` |
| `webhook.resources` | Resource limits/requests | See values.yaml |
| `webhook.env` | Environment variables | `[]` |

### Discord Bot Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `discordbot.enabled` | Enable Discord bot deployment | `true` |
| `discordbot.replicaCount` | Number of replicas | `1` |
| `discordbot.image.repository` | Image repository | `ghcr.io/techops-services/postmortem-automation` |
| `discordbot.image.tag` | Image tag | `latest` |
| `discordbot.service.type` | Service type | `ClusterIP` |
| `discordbot.service.port` | Service port | `8081` |
| `discordbot.resources` | Resource limits/requests | See values.yaml |
| `discordbot.env` | Environment variables | `[]` |

## Creating Secrets

Before deploying, create a Kubernetes secret with your credentials:

```bash
kubectl create secret generic postmortem-secrets \
  --from-literal=pagerduty-api-key=YOUR_PAGERDUTY_KEY \
  --from-literal=discord-webhook-url=YOUR_DISCORD_WEBHOOK \
  --from-literal=discord-bot-token=YOUR_DISCORD_BOT_TOKEN \
  --from-literal=google-drive-folder-id=YOUR_FOLDER_ID
```

## Upgrading

```bash
helm upgrade postmortem-bot ./helm/postmortem-bot -f custom-values.yaml
```

## Uninstalling

```bash
helm uninstall postmortem-bot
```

## Examples

### Deploy Only Webhook Server

```bash
helm install postmortem-bot ./helm/postmortem-bot \
  --set discordbot.enabled=false
```

### Deploy Only Discord Bot

```bash
helm install postmortem-bot ./helm/postmortem-bot \
  --set webhook.enabled=false
```

### Scale Webhook Replicas

```bash
helm upgrade postmortem-bot ./helm/postmortem-bot \
  --set webhook.replicaCount=3
```
