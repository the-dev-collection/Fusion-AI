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

1. **Deploy using the bootstrap application:**
   ```bash
   oc apply -f gitops/bootstrap.yaml
   ```

2. **Or deploy directly:**
   ```bash
   oc apply -f gitops/llmops-application.yaml
   ```

## Namespace Configuration

**NEW**: You can now specify the target namespace directly in the Application CR without modifying individual resource files.

### Changing the Deployment Namespace

Edit [`gitops/llmops-application.yaml`](./gitops/llmops-application.yaml) and change the `spec.destination.namespace` field:

```yaml
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: your-custom-namespace  # Change this to your desired namespace
```

**Default namespace**: `krishi-rakshak-ds`

For detailed information about namespace configuration, see the [Namespace Configuration Guide](./gitops/NAMESPACE_CONFIGURATION.md).

## Architecture

```
fusion-model-serving/
├── gitops/
│   ├── bootstrap.yaml                    # Bootstrap Application CR
│   ├── llmops-application.yaml          # Main Application CR (configure namespace here)
│   ├── NAMESPACE_CONFIGURATION.md       # Detailed namespace configuration guide
│   └── models/
│       ├── kustomization.yaml           # Kustomize configuration
│       ├── kserve-model-serving.yaml    # InferenceService definition
│       ├── rbac.yaml                    # RBAC resources
│       ├── inferenceservice-config.yaml # ConfigMap
│       └── missing-crds.yaml            # Optional CRD definitions
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

**NEW**: You can now change the model by editing a single location in [`gitops/models/kustomization.yaml`](./gitops/models/kustomization.yaml):

```yaml
# ConfigMap generator for model configuration
# CHANGE MODEL HERE: Update the MODEL_NAME value to use a different model
configMapGenerator:
  - name: model-config
    literals:
      - MODEL_NAME=ibm-granite/granite-3.2-8b-instruct  # Change this to your desired Hugging Face model
    options:
      disableNameSuffixHash: true
```

**Example**: To use Meta's Llama 3.1 8B model:
```yaml
configMapGenerator:
  - name: model-config
    literals:
      - MODEL_NAME=meta-llama/Meta-Llama-3.1-8B-Instruct
```

The model name is automatically propagated to both the environment variable and command arguments in the InferenceService.

## Accessing the Model

Once deployed, the model is accessible via the InferenceService endpoint:

```bash
# Get the service URL
oc get inferenceservice granite-llm -n <your-namespace>

# Test the model (from within the cluster)
curl -X POST http://granite-llm-predictor.<your-namespace>.svc.cluster.local/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ibm-granite/granite-3.2-8b-instruct",
    "prompt": "What is AI?",
    "max_tokens": 100
  }'
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

### Multiple Model Deployments

To deploy multiple models to different namespaces, create additional Application CRs:

```yaml
# File: gitops/llmops-application-prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: llmops-models-prod
  namespace: openshift-gitops
spec:
  source:
    repoURL: https://github.com/the-dev-collection/Fusion-AI.git
    targetRevision: main
    path: fusion-model-serving/gitops/models
  destination:
    server: https://kubernetes.default.svc
    namespace: production-models  # Different namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### GPU Memory Optimization

Adjust GPU memory utilization in [`kserve-model-serving.yaml`](./gitops/models/kserve-model-serving.yaml):

```yaml
args:
- --gpu-memory-utilization
- "0.75"  # Adjust between 0.5 and 0.95
```

## Documentation

- [Namespace Configuration Guide](./gitops/NAMESPACE_CONFIGURATION.md) - Detailed guide on configuring namespaces
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