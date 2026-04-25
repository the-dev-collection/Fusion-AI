# Model Serving with Helm Charts

Deploy KServe-based LLM model serving on Red Hat OpenShift AI using Helm charts. This guide focuses on Helm-specific deployment steps and configuration.

For general information about model serving, prerequisites, and other deployment methods, see the [main documentation](../../Main_Readme.md).

## Overview

The Fusion Model Serving Helm chart provides:
- Pre-configured model presets for popular open-source LLMs
- Flexible custom model deployment
- Multi-model support in the same namespace
- Declarative GPU and memory resource management

---

## Prerequisites

Ensure you have:
- Red Hat OpenShift AI installed with KServe enabled
- Helm 3.x installed
- GPU-enabled worker nodes (for LLM serving)
- `oc` CLI authenticated to your cluster

For detailed prerequisites, see [Main Documentation - Prerequisites](../../Main_Readme.md#prerequisites).

### Install Helm

If Helm is not installed:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify installation:
```bash
helm version
```

---

## Available Model Presets

Pre-configured values files in [`values/`](./values/):

| Model | Values File | Description |
|-------|-------------|-------------|
| **IBM Granite 3.2 8B Instruct** | [`values/granite.yaml`](./values/granite.yaml) | Enterprise-focused instruction-tuned model |
| **Qwen 2.5 7B Instruct** | [`values/qwen.yaml`](./values/qwen.yaml) | High-performance multilingual model |
| **Ministral 3 8B Instruct** | [`values/mistral.yaml`](./values/mistral.yaml) | Efficient instruction-following model |

---

## Quick Start

### Deploy a Pre-configured Model

Deploy IBM Granite 3.2 8B Instruct:

```bash
helm install granite-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  --create-namespace \
  -f ./fusion-model-serving/deploy/helm/values/granite.yaml
```

Deploy Qwen 2.5 7B Instruct:

```bash
helm install qwen-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  --create-namespace \
  -f ./fusion-model-serving/deploy/helm/values/qwen.yaml
```

Deploy Ministral 3 8B Instruct:

```bash
helm install mistral-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  --create-namespace \
  -f ./fusion-model-serving/deploy/helm/values/mistral.yaml
```

---

## Deploying Multiple Models

Deploy multiple models in the same namespace using different release names:

```bash
# Deploy Granite
helm install granite-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  --create-namespace \
  -f ./fusion-model-serving/deploy/helm/values/granite.yaml

# Deploy Qwen
helm install qwen-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  -f ./fusion-model-serving/deploy/helm/values/qwen.yaml

# Deploy Mistral
helm install mistral-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  -f ./fusion-model-serving/deploy/helm/values/mistral.yaml
```

Each release creates an independent InferenceService with dedicated resources.

---

## Deploying a Custom Model

### 1. Create Custom Values File

```bash
cp ./fusion-model-serving/deploy/helm/values.yaml ./my-custom-model.yaml
```

### 2. Configure Model Parameters

Edit `my-custom-model.yaml`:

```yaml
labels:
  appName: "my-custom-model"

model:
  name: "my-custom-model"
  label: "custom"
  repository: "organization/model-name"  # Hugging Face model ID
  extraArgs: []

resources:
  limits:
    nvidia.com/gpu: "1"
    memory: "16Gi"
  requests:
    nvidia.com/gpu: "1"
    memory: "16Gi"
```

**Key Fields:**
- **`model.repository`**: Hugging Face model path (e.g., `meta-llama/Llama-2-7b-chat-hf`)
- **`model.extraArgs`**: Additional vLLM arguments (e.g., `["--max-model-len=4096"]`)
- **`resources`**: GPU and memory allocation

### 3. Deploy

```bash
helm install my-model-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  --create-namespace \
  -f ./my-custom-model.yaml
```

---

## Managing Deployments

### Upgrade a Model

```bash
helm upgrade qwen-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  -f ./fusion-model-serving/deploy/helm/values/qwen.yaml
```

### Override Values at Runtime

```bash
helm upgrade --install qwen-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  -f ./fusion-model-serving/deploy/helm/values/qwen.yaml \
  --set resources.limits."nvidia\.com/gpu"="2" \
  --set resources.requests."nvidia\.com/gpu"="2" \
  --set resources.limits.memory="32Gi"
```

---

## Monitoring

### Check Release Status

```bash
helm list -n model-serving
```

### Monitor InferenceService

```bash
oc get inferenceservice -n model-serving
```

### Watch Pods

```bash
oc get pods -n model-serving -w
```

**Deployment Phases:**
1. **Pending**: Waiting for GPU node scheduling
2. **ContainerCreating**: Pulling image
3. **Running**: Model downloading
4. **Ready**: Serving requests

---

## Useful Helm Commands

```bash
# List releases
helm list -n model-serving

# View release values
helm get values qwen-serve -n model-serving

# View rendered manifests
helm get manifest qwen-serve -n model-serving

# Get release history
helm history qwen-serve -n model-serving

# Rollback to previous version
helm rollback qwen-serve 1 -n model-serving

# Uninstall a model
helm uninstall qwen-serve -n model-serving
```

---

## Exposing Models

By default, models are only accessible within the cluster. To expose externally, use the `expose-model.sh` script:

```bash
# Expose all models
./fusion-model-serving/scripts/expose-model.sh model-serving

# Expose specific model
./fusion-model-serving/scripts/expose-model.sh qwen-2-5-7b-instruct model-serving
```

See [Main Documentation - Exposing Models](../../Main_Readme.md#exposing-models-for-external-access) for details.

---

## Troubleshooting

### Model Stuck in Pending

**Check GPU availability:**
```bash
oc describe node <worker-node> | grep -i gpu
oc describe pod <predictor-pod> -n model-serving
```

### Model Download Failures

**Check logs:**
```bash
oc logs <predictor-pod> -n model-serving
```

**For gated models, create token secret:**
```bash
oc create secret generic hf-token \
  --from-literal=token=<your-hf-token> \
  -n model-serving
```

### Out of Memory Errors

**Increase memory in values file:**
```yaml
resources:
  limits:
    memory: "32Gi"
  requests:
    memory: "32Gi"
```

**Then upgrade:**
```bash
helm upgrade qwen-serve ./fusion-model-serving/deploy/helm \
  --namespace model-serving \
  -f ./my-updated-values.yaml
```

---

## Advanced Configuration

### Multi-GPU Deployment

For larger models requiring multiple GPUs:

```yaml
resources:
  limits:
    nvidia.com/gpu: "2"
  requests:
    nvidia.com/gpu: "2"

model:
  extraArgs:
    - "--tensor-parallel-size=2"
```

### Custom vLLM Arguments

```yaml
model:
  extraArgs:
    - "--max-model-len=4096"
    - "--max-num-seqs=256"
    - "--enable-prefix-caching"
```

### Production Authentication

```yaml
model:
  extraArgs:
    - "--api-key=your-secure-api-key"
```

---

## Next Steps

- **Try GitOps**: [GitOps Deployment Guide](../gitops/README.md) for automated, version-controlled deployments
- **Try Kubernetes**: [Kubernetes Deployment Guide](../kubernetes/README.md) for direct manifest control
- **Configure Monitoring**: Set up Prometheus and Grafana
- **Implement Autoscaling**: Configure HPA based on load

---

## Additional Resources

- [Helm Documentation](https://helm.sh/docs/)
- [KServe Documentation](https://kserve.github.io/website/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)