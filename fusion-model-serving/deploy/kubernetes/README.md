# Model Serving with Kubernetes Manifests

Deploy KServe-based LLM model serving on Red Hat OpenShift AI using native Kubernetes manifests and the `oc` command-line tool. This guide focuses on direct YAML manifest deployment.

For general information about model serving, prerequisites, and other deployment methods, see the [main documentation](../../Main_Readme.md).

## Overview

This deployment method provides:
- Direct control over resource definitions
- Simple `oc apply` commands
- Quick prototyping and testing
- Easy CI/CD integration

---

## Prerequisites

Ensure you have:
- Red Hat OpenShift AI installed with KServe enabled
- GPU-enabled worker nodes (for LLM serving)
- `oc` CLI authenticated to your cluster
- Sufficient RBAC permissions

For detailed prerequisites, see [Main Documentation - Prerequisites](../../Main_Readme.md#prerequisites).

---

## Quick Start

### Step 1: Create the Namespace

```bash
oc apply -f fusion-model-serving/deploy/kubernetes/create_project.yaml
```

### Step 2: Deploy the Model

Deploy the default model (IBM Granite 3.2 8B Instruct):

```bash
oc apply -f fusion-model-serving/deploy/kubernetes/kserve-model-serving.yaml
```

### Step 3: Monitor Deployment

```bash
# Check InferenceService status
oc get inferenceservice -n model-serving

# Watch pod creation
oc get pods -n model-serving -w

# View detailed information
oc describe inferenceservice granite-llm -n model-serving
```

**Deployment Phases:**
1. **Pending**: Waiting for GPU node scheduling
2. **ContainerCreating**: Pulling vLLM container image
3. **Running**: Model downloading from Hugging Face
4. **Ready**: Model loaded and serving requests

---

## Understanding the InferenceService Manifest

The [`kserve-model-serving.yaml`](./kserve-model-serving.yaml) defines a KServe InferenceService. Key sections:

### Metadata

```yaml
metadata:
  name: granite-llm              # InferenceService name
  namespace: model-serving       # Target namespace
  labels:
    app: llm-serving
    model: granite
```

### Resource Allocation

```yaml
resources:
  limits:
    nvidia.com/gpu: "1"         # Maximum GPU count
    memory: "16Gi"              # Maximum memory
    cpu: "4"
  requests:
    nvidia.com/gpu: "1"         # Reserved GPU count
    memory: "16Gi"              # Reserved memory
    cpu: "4"
```

### Model Configuration

```yaml
env:
- name: MODEL
  value: "ibm-granite/granite-3.2-8b-instruct"  # Hugging Face model ID
- name: HF_HOME
  value: "/tmp/hf_cache"
- name: VLLM_CACHE_ROOT
  value: "/tmp/vllm_cache"
```

### Runtime Arguments

```yaml
args:
- --model
- $(MODEL)
- --host
- "0.0.0.0"
- --port
- "8080"
- --api-key
- "EMPTY"
- --trust-remote-code
- --gpu-memory-utilization
- "0.75"
```

---

## Deploying Different Models

### Example 1: Deploy Qwen 2.5 7B Instruct

1. **Copy the base manifest:**
```bash
cp fusion-model-serving/deploy/kubernetes/kserve-model-serving.yaml qwen-model.yaml
```

2. **Edit the manifest:**

```yaml
metadata:
  name: qwen-2-5-7b-instruct    # Change name
  labels:
    model: qwen                  # Update label

spec:
  predictor:
    containers:
    - env:
      - name: MODEL
        value: "Qwen/Qwen2.5-7B-Instruct"  # Update model
```

3. **Deploy:**
```bash
oc apply -f qwen-model.yaml
```

### Example 2: Deploy Mistral 7B Instruct

```yaml
metadata:
  name: mistral-7b-instruct
  labels:
    model: mistral

spec:
  predictor:
    containers:
    - env:
      - name: MODEL
        value: "mistralai/Mistral-7B-Instruct-v0.2"
```

### Example 3: Larger Model with More Resources

For models like Llama 2 13B:

```yaml
metadata:
  name: llama-2-13b-chat

spec:
  predictor:
    containers:
    - env:
      - name: MODEL
        value: "meta-llama/Llama-2-13b-chat-hf"
      resources:
        limits:
          nvidia.com/gpu: "2"      # Increase GPUs
          memory: "32Gi"           # Increase memory
        requests:
          nvidia.com/gpu: "2"
          memory: "32Gi"
      args:
      - --model
      - $(MODEL)
      - --host
      - "0.0.0.0"
      - --port
      - "8080"
      - --tensor-parallel-size
      - "2"                        # Enable multi-GPU
      - --gpu-memory-utilization
      - "0.85"
```

---

## Required Changes for Different Models

When deploying a different model, **must update**:

1. **InferenceService Name** (`metadata.name`)
   - Must be unique within namespace
   - Use descriptive names (e.g., `qwen-2-5-7b`, `mistral-7b`)

2. **Model Repository** (`env.MODEL`)
   - Hugging Face model path (e.g., `organization/model-name`)
   - Verify model exists and is accessible

3. **Model Label** (`metadata.labels.model`)
   - For organization and filtering

### Optional Customizations

**Adjust GPU allocation:**
```yaml
resources:
  limits:
    nvidia.com/gpu: "2"
  requests:
    nvidia.com/gpu: "2"
args:
  - --tensor-parallel-size
  - "2"
```

**Increase memory:**
```yaml
resources:
  limits:
    memory: "32Gi"
  requests:
    memory: "32Gi"
```

**Modify GPU memory utilization:**
```yaml
args:
  - --gpu-memory-utilization
  - "0.85"
```

**Add custom vLLM arguments:**
```yaml
args:
  - --max-model-len
  - "4096"
  - --max-num-seqs
  - "256"
  - --enable-prefix-caching
```

---

## Managing Deployments

### View InferenceServices

```bash
oc get inferenceservice -n model-serving
```

### Get Detailed Information

```bash
oc describe inferenceservice granite-llm -n model-serving
```

### View Pod Logs

```bash
# Get pod name
oc get pods -n model-serving

# View logs
oc logs <predictor-pod-name> -n model-serving -f
```

### Update Deployment

Edit manifest and reapply:
```bash
oc apply -f fusion-model-serving/deploy/kubernetes/kserve-model-serving.yaml
```

### Delete Deployment

```bash
# Delete specific model
oc delete inferenceservice granite-llm -n model-serving

# Delete entire namespace
oc delete namespace model-serving
```

---

## Deploying Multiple Models

Deploy multiple models by creating separate manifests with unique names:

```bash
# Deploy Granite
oc apply -f granite-model.yaml

# Deploy Qwen
oc apply -f qwen-model.yaml

# Deploy Mistral
oc apply -f mistral-model.yaml

# View all models
oc get inferenceservice -n model-serving
```

---

## Exposing Models

By default, models are only accessible within the cluster. To expose externally:

```bash
# Expose all models
./fusion-model-serving/scripts/expose-model.sh model-serving

# Expose specific model
./fusion-model-serving/scripts/expose-model.sh granite-llm model-serving
```

See [Main Documentation - Exposing Models](../../Main_Readme.md#exposing-models-for-external-access) for details.

---

## Troubleshooting

### Model Stuck in Pending

**Check GPU and scheduling:**
```bash
oc describe node <worker-node> | grep -i gpu
oc describe pod <predictor-pod> -n model-serving
oc get pods -n nvidia-gpu-operator
```

### Model Download Failures

**Check logs:**
```bash
oc logs <predictor-pod> -n model-serving
```

**For gated models:**
```bash
oc create secret generic hf-token \
  --from-literal=token=<your-hf-token> \
  -n model-serving
```

Add to manifest:
```yaml
env:
- name: HUGGING_FACE_HUB_TOKEN
  valueFrom:
    secretKeyRef:
      name: hf-token
      key: token
```

### Out of Memory Errors

Increase memory in manifest:
```yaml
resources:
  limits:
    memory: "32Gi"
  requests:
    memory: "32Gi"
```

Reapply:
```bash
oc apply -f your-model.yaml
```

### Image Pull Errors

```bash
# Check pod events
oc describe pod <predictor-pod> -n model-serving

# Test image accessibility
oc run test-vllm --image=vllm/vllm-openai:latest --rm -it -- /bin/bash
```

---

## Best Practices

### Resource Planning
- Ensure GPU requests match node capacity
- Allocate sufficient memory for model size
- Provide adequate CPU for preprocessing

### Security
- Use proper authentication in production
- Implement network policies
- Use dedicated ServiceAccounts with minimal permissions

### Performance
- Tune `--gpu-memory-utilization` based on workload
- Adjust `--max-num-seqs` for throughput
- Enable `--enable-prefix-caching` for repeated prompts

---

## Next Steps

- **Try GitOps**: [GitOps Deployment Guide](../gitops/README.md) for automated deployments
- **Try Helm**: [Helm Deployment Guide](../helm/README.md) for templated deployments
- **Configure Monitoring**: Set up Prometheus and Grafana
- **Implement Autoscaling**: Configure HPA based on load

---

## Additional Resources

- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- [KServe Documentation](https://kserve.github.io/website/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [OpenShift CLI Documentation](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)