# Fusion Model Serving

This directory contains the GitOps configuration for deploying LLM model serving using KServe on OpenShift AI.

## Overview

The model serving configuration deploys:
- **KServe InferenceService** - Serves the IBM Granite LLM model using vLLM
- **RBAC Resources** - Permissions for ArgoCD to manage resources
- **ConfigMaps** - Configuration required by ODH Model Controller

## Quick Start

### Prerequisites
- OpenShift cluster with OpenShift AI installed
- ArgoCD/OpenShift GitOps installed
- GPU nodes available in the cluster

### Deployment

Deploy the model serving application:

```bash
oc apply -f gitops/model-serving.yaml
```

This deploys the LLM model serving infrastructure to your OpenShift cluster. ArgoCD will automatically sync and manage the deployment.

## Configuration

All configuration is done in a single file: [`gitops/model-serving.yaml`](./gitops/model-serving.yaml)

### Changing the Deployment Namespace

Edit `spec.destination.namespace` in [`gitops/model-serving.yaml`](./gitops/model-serving.yaml) (default: `krishi-rakshak-ds`)

## Architecture

```
fusion-model-serving/
├── gitops/
│   ├── model-serving.yaml               # Main Application CR (configure here)
│   └── models/
│       ├── kustomization.yaml           # Kustomize configuration
│       ├── kserve-model-serving.yaml    # InferenceService definition
│       ├── rbac.yaml                    # RBAC resources
│       ├── inferenceservice-config.yaml # ConfigMap
│       └── missing-crds.yaml            # Optional CRD definitions
├── scripts/
│   └── expose-model.sh                  # Script to expose models externally
└── docs/
    └── ModelServingGuide.md             # Detailed deployment guide
```

## Model Configuration

The default configuration deploys the **IBM Granite 3.2 8B Instruct** model:
- Model: `ibm-granite/granite-3.2-8b-instruct`
- Runtime: vLLM with OpenAI-compatible API
- GPU: 1x NVIDIA GPU required
- Memory: 16Gi

### Customizing the Model

Edit [`gitops/model-serving.yaml`](./gitops/model-serving.yaml) to configure your model:

```yaml
kustomize:
  patches:
    # 1. Set your Hugging Face model
    - target:
        kind: ConfigMap
        name: model-config
      patch: |-
        - op: replace
          path: /data/MODEL_NAME
          value: meta-llama/Meta-Llama-3.1-8B-Instruct  # ← Change this
    
    # 2. Set InferenceService name (derived from model name)
    - target:
        kind: InferenceService
      patch: |-
        - op: replace
          path: /metadata/name
          value: meta-llama-3-1-8b-instruct  # ← Change this
```

**Name Conversion Rules:**
- Take the part after "/" in MODEL_NAME
- Replace dots (.) with dashes (-)
- Convert to lowercase

**Examples:**
- `ibm-granite/granite-3.2-8b-instruct` → `granite-3-2-8b-instruct`
- `meta-llama/Meta-Llama-3.1-8B-Instruct` → `meta-llama-3-1-8b-instruct`
- `mistralai/Mistral-7B-Instruct-v0.2` → `mistral-7b-instruct-v0-2`

**Complete Workflow:**
```bash
# 1. Edit model configuration
vim gitops/model-serving.yaml

# 2. Apply the configuration
oc apply -f gitops/model-serving.yaml

# 3. Wait for ArgoCD to sync (check ArgoCD UI)

# 4. Expose all models in namespace
./scripts/expose-model.sh krishi-rakshak-ds
```

## Accessing the Model

Once deployed, the model is accessible internally within the cluster.

### Exposing Models Externally

Use the provided script to expose models via OpenShift Routes with TLS:

```bash
# Expose ALL models in a namespace
./scripts/expose-model.sh krishi-rakshak-ds

# Or expose a specific model
./scripts/expose-model.sh <inferenceservice-name> <namespace>
```

### External Access (after exposing)

```bash
# Get the route URL
ROUTE_URL=$(oc get route <inferenceservice-name>-external -n <namespace> -o jsonpath='{.spec.host}')

# List available models
curl -k https://${ROUTE_URL}/v1/models \
  -H "Authorization: Bearer EMPTY"

# Test with chat completions
curl -k -X POST https://${ROUTE_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{
    "model": "ibm-granite/granite-3.2-8b-instruct",
    "messages": [
      {"role": "user", "content": "What is AI?"}
    ],
    "max_tokens": 100
  }'
```

### Internal Access (from within the cluster)

```bash
# Get the service URL
oc get inferenceservice -n <your-namespace>

# Test the model (from within the cluster)
curl -X POST http://<inferenceservice-name>-predictor.<your-namespace>.svc.cluster.local/v1/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{
    "model": "ibm-granite/granite-3.2-8b-instruct",
    "prompt": "What is Redhat openshift AI?",
    "max_tokens": 100
  }'
```

### Port Forwarding (for local development)

```bash
# Forward port 8080 from the pod to your local machine
oc port-forward \
  pod/$(oc get pod -n <your-namespace> -l app=isvc.<inferenceservice-name>-predictor -o jsonpath='{.items[0].metadata.name}') \
  8080:8080 \
  -n <your-namespace>

# Then access via localhost
curl http://localhost:8080/v1/models \
  -H "Authorization: Bearer EMPTY"
```

## Monitoring

Check the deployment status:

```bash
# Check InferenceService status
oc get inferenceservice -n <your-namespace>

# Check pod status
oc get pods -n <your-namespace>

# View logs
oc logs -f deployment/granite-llm-predictor -n <your-namespace>

# Check ArgoCD application status
oc get application llmops-models -n openshift-gitops
```

## Troubleshooting

### Common Issues

1. **Pod stuck in Pending state**
   - Check if GPU nodes are available: `oc get nodes -l nvidia.com/gpu.present=true`
   - Verify GPU resources: `oc describe node <node-name>`

2. **Model download fails**
   - Check internet connectivity from the pod
   - Verify Hugging Face model name is correct
   - Check pod logs: `oc logs <pod-name> -n <your-namespace>`

3. **Permission errors**
   - Verify RBAC resources are created: `oc get role,rolebinding -n <your-namespace>`
   - Check ArgoCD service account permissions

4. **Namespace not created**
   - Ensure `CreateNamespace=true` is set in the Application CR
   - Manually create the namespace: `oc create namespace <your-namespace>`

## Resource Requirements

### Minimum Requirements
- **GPU**: 1x NVIDIA GPU (A100, V100, or similar)
- **Memory**: 16Gi
- **CPU**: 4 cores

### Recommended for Production
- **GPU**: 2x NVIDIA A100 GPUs
- **Memory**: 32Gi
- **CPU**: 8 cores

## Advanced Configuration

### GPU Memory Optimization

Adjust GPU memory utilization in [`gitops/models/kserve-model-serving.yaml`](./gitops/models/kserve-model-serving.yaml):

```yaml
args:
- --gpu-memory-utilization
- "0.75"  # Adjust between 0.5 and 0.95
```

## Documentation

- [Model Serving Guide](./docs/ModelServingGuide.md) - Comprehensive deployment and configuration guide
- [Fusion AI Documentation](../README.md) - Main project documentation

## Support

For issues and questions:
1. Check the [troubleshooting section](#troubleshooting)
2. Review the [Model Serving Guide](./docs/ModelServingGuide.md)
3. Check ArgoCD application logs: `oc logs -n openshift-gitops deployment/openshift-gitops-application-controller`

## Contributing

When making changes:
1. Test in a development namespace first
2. Update documentation if adding new features
3. Follow GitOps best practices
4. Ensure backward compatibility

## License

See [LICENSE](../LICENSE) file in the root directory.