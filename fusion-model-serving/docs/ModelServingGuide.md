
# Simplifying AI Model Serving on IBM Fusion HCI with Red Hat OpenShift AI and GitOps

## Introduction

In the rapidly evolving landscape of AI and machine learning, deploying and managing models in production environments remains a significant challenge. Organizations struggle with complex configurations, inconsistent deployments, and the operational overhead of maintaining AI infrastructure. This is where **IBM Fusion HCI** provides the foundational platform, and this GitOps-based model serving solution demonstrates how to leverage that foundation effectively.

This blog explores how a GitOps-driven approach to model serving on IBM Fusion HCI makes it remarkably easy to deploy, manage, and scale AI models in production, transforming what was once a multi-day endeavor into a simple, declarative configuration that can be deployed in minutes.

## Why IBM Fusion HCI?

**IBM Fusion HCI** is a purpose-built, hyper-converged architecture designed to deploy bare metal Red Hat OpenShift container management and deployment software alongside IBM Fusion software. It provides a fully integrated infrastructure that combines compute, networking, and storage resources optimized for containerized workloads.

For AI workloads such as model serving with Red Hat OpenShift AI (RHOAI), IBM Fusion HCI offers:

### **Integrated Infrastructure for AI Workloads**
- **Fully integrated infrastructure** combining compute, networking, and storage resources optimized for containerized workloads
- **Bare Metal Red Hat OpenShift** deployment for maximum performance and control
- **Software-defined storage** to meet the storage requirements of modern, stateful Kubernetes applications

### **Optimized for GPU-Accelerated AI**
- **Predictable GPU scheduling and utilization** using Red Hat OpenShift in combination with the NVIDIA GPU Operator
- **High-performance compute resources** designed for mission-critical containers and hybrid cloud deployments
- **Efficient resource management** ensuring operational efficiency for AI inference workloads

### **Enterprise-Grade Reliability**
- **Comprehensive infrastructure** with compute, networking, and storage resources
- **Data platform and global data services** for Red Hat OpenShift Container Platform
- **Appliance form-factor** with hyper-converged infrastructure and integrated software-defined storage

### **Consistent Operational Foundation**
- **Secure, controlled deployment** within enterprise infrastructure
- **Unified platform** for multiple AI blueprints on the same Red Hat OpenShift-based environment
- **Lifecycle management** of compute nodes, networking, and storage with operational efficiency

IBM Fusion HCI serves as the **foundational infrastructure layer** that enables organizations to run stateful and GPU-accelerated AI workloads with enterprise-grade reliability, making it the ideal platform for deploying production AI model serving solutions.

## Understanding Model Serving with Red Hat OpenShift AI

### What is RHOAI Model Serving?

Red Hat OpenShift AI (RHOAI) provides enterprise-grade AI/ML capabilities built on OpenShift. Running on IBM Fusion HCI's integrated infrastructure, RHOAI leverages **KServe** - a Kubernetes-native model serving framework that provides:

- **Standardized inference protocols** - OpenAI-compatible APIs for seamless integration
- **Auto-scaling capabilities** - Dynamic scaling based on traffic patterns
- **GPU acceleration** - Native support for NVIDIA GPUs leveraging Fusion HCI's optimized compute resources
- **Multi-framework support** - Deploy models from various ML frameworks
- **Production-ready features** - Health checks, metrics, logging, and monitoring

### The Challenge: Traditional Model Deployment

Traditionally, deploying an AI model to production involves:

1. Setting up infrastructure (compute, storage, networking)
2. Configuring model serving frameworks (TensorFlow Serving, TorchServe, vLLM)
3. Managing dependencies and container images
4. Setting up load balancers and ingress
5. Implementing monitoring and logging
6. Managing updates and rollbacks
7. Ensuring security and access control

This complexity often requires specialized DevOps knowledge and can take days or weeks to set up correctly.

## How This GitOps Solution Simplifies Model Serving on IBM Fusion HCI

This GitOps-driven model serving solution revolutionizes the deployment process by providing a **declarative, GitOps-driven approach** that abstracts away complexity while leveraging IBM Fusion HCI's integrated infrastructure. Here's what makes it special:

### 1. Single Configuration File

Instead of managing dozens of YAML files and complex configurations, this solution provides a **single Application CR** ([`model-serving.yaml`](./gitops/model-serving.yaml)) that serves as your complete model serving configuration. This file is your single source of truth.

### 2. GitOps-Native Architecture

Built on ArgoCD, the solution ensures:
- **Declarative configuration** - Define desired state, not imperative steps
- **Version control** - All changes tracked in Git
- **Automated synchronization** - ArgoCD continuously reconciles actual vs. desired state
- **Self-healing** - Automatic recovery from configuration drift
- **Audit trail** - Complete history of all changes

### 3. Intelligent Label Propagation

The solution uses Kustomize's `commonLabels` feature with strategic patches to automatically propagate labels across all resources. Change labels once in the Application CR, and they cascade to:
- RBAC resources (Roles, RoleBindings)
- ConfigMaps and Secrets
- InferenceServices
- All Kubernetes resources

### 4. Simplified Customization

The entire model serving configuration is controlled through **just 3 strategic patches**:

**Patch 1: Application Labels** - Define your application identity
**Patch 2: Model Selection** - Specify which HuggingFace model to serve
**Patch 3: Resource Configuration** - Set GPU, memory, and compute requirements

## The GitOps Application: Deep Dive

Let's explore how the [`model-serving.yaml`](./gitops/model-serving.yaml) application makes model serving effortless on IBM Fusion HCI.

### Architecture Overview

```
fusion-model-serving/
├── gitops/
│   ├── model-serving.yaml          # ← Single configuration file
│   └── models/
│       ├── kustomization.yaml      # Kustomize orchestration
│       ├── kserve-model-serving.yaml  # InferenceService template
│       ├── rbac.yaml               # Access control
│       ├── inferenceservice-config.yaml  # ODH configuration
│       └── missing-crds.yaml       # CRD definitions
└── scripts/
    └── expose-model.sh             # External access automation
```

### The Power of Three Patches

#### Patch 1: Application Identity

```yaml
- target:
    kind: Kustomization
  patch: |-
    - op: replace
      path: /commonLabels/app.kubernetes.io~1name
      value: llmops-models
    - op: replace
      path: /commonLabels/validated-patterns.io~1pattern
      value: llmops-platform
```

This patch sets labels that automatically propagate to **every resource** in your deployment, ensuring consistent labeling and easy resource discovery.

#### Patch 2: Model Selection

```yaml
- target:
    kind: ConfigMap
    name: model-config
  patch: |-
    - op: replace
      path: /data/MODEL_NAME
      value: ibm-granite/granite-3.2-8b-instruct
```

Simply specify the HuggingFace model path. The system handles:
- Model downloading from HuggingFace Hub
- Caching configuration
- Environment setup
- vLLM runtime configuration

#### Patch 3: Resource Allocation

```yaml
- target:
    kind: InferenceService
  patch: |-
    - op: replace
      path: /metadata/name
      value: granite-3-2-8b-instruct
    - op: replace
      path: /spec/predictor/containers/0/resources/limits/nvidia.com~1gpu
      value: "1"
    - op: replace
      path: /spec/predictor/containers/0/resources/limits/memory
      value: "16Gi"
```

Configure your InferenceService name and resource requirements. The system automatically:
- Schedules pods on IBM Fusion HCI's GPU nodes
- Allocates requested resources from the integrated infrastructure
- Sets up health checks
- Configures networking

## Prerequisites

Before deploying model serving on IBM Fusion HCI, ensure you have:

### Infrastructure Requirements

1. **IBM Fusion HCI Cluster**
   - Deployed and operational
   - GPU nodes with NVIDIA GPUs (A100, V100, or similar)
   - NVIDIA GPU Operator installed
   - Minimum 1 GPU node with 16Gi memory

2. **Red Hat OpenShift AI** installed on IBM Fusion HCI
   - RHOAI operator deployed
   - KServe component enabled
   - Model serving capabilities configured

3. **OpenShift GitOps (ArgoCD)** installed
   - ArgoCD operator deployed
   - Default ArgoCD instance running in `openshift-gitops` namespace

### Access Requirements

- `oc` CLI tool installed and configured
- Cluster admin or sufficient RBAC permissions
- Git repository access (for GitOps workflow)

### Resource Requirements

**Minimum (Development):**
- 1x NVIDIA GPU (A100, V100, T4)
- 16Gi memory
- 4 CPU cores

**Recommended (Production):**
- 2x NVIDIA A100 GPUs
- 32Gi memory
- 8 CPU cores

## Deploying the Model Serving Application

### Step 1: Apply the Application

The deployment process is remarkably simple:

```bash
# Clone the Fusion repository
git clone https://github.com/the-dev-collection/Fusion-AI.git
cd Fusion-AI/fusion-model-serving

# Deploy the model serving application
oc apply -f gitops/model-serving.yaml
```

That's it! ArgoCD will now:
1. Create the target namespace (`test-model-serving` by default)
2. Deploy RBAC resources
3. Create required ConfigMaps
4. Deploy the InferenceService on IBM Fusion HCI
5. Set up networking and services

### Step 2: Monitor Deployment

Watch the deployment progress:

```bash
# Check ArgoCD application status
oc get application llmops-models -n openshift-gitops

# Monitor InferenceService
oc get inferenceservice -n test-model-serving

# Watch pod creation
oc get pods -n test-model-serving -w

# View deployment logs
oc logs -f deployment/granite-3-2-8b-instruct-predictor -n test-model-serving
```

The model will go through these phases:
1. **Pending** - Waiting for GPU node scheduling on Fusion HCI
2. **ContainerCreating** - Pulling vLLM image
3. **Running** - Downloading model from HuggingFace
4. **Ready** - Model loaded and serving requests

### Step 3: Verify Deployment

Check that your model is ready:

```bash
# Check InferenceService status
oc get inferenceservice granite-3-2-8b-instruct -n test-model-serving

# Expected output:
# NAME                      URL                                              READY
# granite-3-2-8b-instruct   http://granite-3-2-8b-instruct.test-model...    True
```

## Customizing for Your Models

One of the solution's greatest strengths is how easily you can customize the deployment for any model. Here's how:

### Serving a Different Model

Want to serve Meta's Llama 3.1 instead of IBM Granite? Simply edit [`gitops/model-serving.yaml`](./gitops/model-serving.yaml):

```yaml
# Patch 2: Change the model
- target:
    kind: ConfigMap
    name: model-config
  patch: |-
    - op: replace
      path: /data/MODEL_NAME
      value: meta-llama/Meta-Llama-3.1-8B-Instruct  # ← New model

# Patch 3: Update InferenceService name
- target:
    kind: InferenceService
  patch: |-
    - op: replace
      path: /metadata/name
      value: meta-llama-3-1-8b-instruct  # ← Kubernetes-compatible name
    - op: replace
      path: /metadata/labels/model
      value: llama  # ← Model identifier
```

**Naming Convention:** Convert HuggingFace model names to Kubernetes-compatible names:
- Take the part after "/" in the model path
- Replace dots (.) with dashes (-)
- Convert to lowercase

**Examples:**
- `ibm-granite/granite-3.2-8b-instruct` → `granite-3-2-8b-instruct`
- `meta-llama/Meta-Llama-3.1-8B-Instruct` → `meta-llama-3-1-8b-instruct`
destination:
  server: https://kubernetes.default.svc
  namespace: production-models  # ← Your namespace
```

ArgoCD will automatically create the namespace if it doesn't exist (thanks to `CreateNamespace=true`).

### Customizing Application Labels

Update application identity and labels:

```yaml
metadata:
  name: my-ai-models  # ← Application name
  labels:
    app.kubernetes.io/name: my-ai-models
    validated-patterns.io/pattern: my-ai-platform

# And in patches:
- target:
    kind: Kustomization
  patch: |-
    - op: replace
      path: /commonLabels/app.kubernetes.io~1name
      value: my-ai-models
    - op: replace
      path: /commonLabels/validated-patterns.io~1pattern
      value: my-ai-platform
```

### Complete Customization Workflow

```bash
# 1. Edit the configuration
vim gitops/model-serving.yaml

# 2. Commit changes (GitOps best practice)
git add gitops/model-serving.yaml
git commit -m "Deploy Llama 3.1 model with 2 GPUs"
git push

# 3. Apply or let ArgoCD auto-sync
oc apply -f gitops/model-serving.yaml

# 4. ArgoCD automatically:
#    - Detects changes
#    - Applies all patches
#    - Updates all resources
#    - Ensures desired state
```

## Making Models Available Externally

By default, models are accessible only within the cluster. To enable external access, Fusion provides an automated script.

### The expose-model.sh Script

The [`expose-model.sh`](./scripts/expose-model.sh) script creates OpenShift Routes with TLS encryption, making your models accessible from outside the cluster.

### Usage Options

**Option 1: Expose All Models in a Namespace**

```bash
./scripts/expose-model.sh test-model-serving
```

This will:
- Discover all InferenceServices in the namespace
- Create TLS-secured Routes for each
- Display access URLs and test commands

**Option 2: Expose a Specific Model**

```bash
./scripts/expose-model.sh granite-3-2-8b-instruct test-model-serving
```

### What the Script Does

1. **Validates** - Checks that InferenceService and Service exist
2. **Creates Route** - Sets up edge-terminated TLS route
3. **Configures Security** - Enables HTTPS with redirect from HTTP
4. **Provides URLs** - Displays the external access URL
5. **Generates Test Commands** - Shows curl commands for testing

### Example Output

```bash
╔════════════════════════════════════════════════════════════╗
║         Expose Models - External Access                    ║
╚════════════════════════════════════════════════════════════╝

Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Namespace: test-model-serving
  Mode:      Expose ALL InferenceServices
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Found InferenceServices:
  - granite-3-2-8b-instruct

Processing: granite-3-2-8b-instruct
  ✓ Exposed at: https://granite-3-2-8b-instruct-external-test-model-serving.apps.cluster.example.com

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Successfully exposed 1 InferenceService(s)!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test your models:
  granite-3-2-8b-instruct:
    curl -k https://granite-3-2-8b-instruct-external-test-model-serving.apps.cluster.example.com/v1/models -H 'Authorization: Bearer EMPTY'
```

### Testing External Access

Once exposed, test your model with OpenAI-compatible API calls:

```bash
# Get the route URL
ROUTE_URL=$(oc get route granite-3-2-8b-instruct-external -n test-model-serving -o jsonpath='{.spec.host}')

# List available models
curl -k https://${ROUTE_URL}/v1/models \
  -H "Authorization: Bearer EMPTY"

# Test chat completions
curl -k -X POST https://${ROUTE_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{
    "model": "ibm-granite/granite-3.2-8b-instruct",
    "messages": [
      {"role": "user", "content": "Explain quantum computing in simple terms"}
    ],
    "max_tokens": 200,
    "temperature": 0.7
  }'

# Test text completions
curl -k -X POST https://${ROUTE_URL}/v1/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{
    "model": "ibm-granite/granite-3.2-8b-instruct",
    "prompt": "The future of AI is",
    "max_tokens": 100
  }'
```

### Integration with Applications

Your external applications can now integrate with the model using standard OpenAI SDK:

**Python Example:**

```python
from openai import OpenAI

# Configure client with your model endpoint
client = OpenAI(
    base_url=f"https://{route_url}/v1",
    api_key="EMPTY"  # vLLM uses dummy key
)

# Use like any OpenAI model
response = client.chat.completions.create(
    model="ibm-granite/granite-3.2-8b-instruct",
    messages=[
        {"role": "user", "content": "What is Red Hat OpenShift AI?"}
    ]
)

print(response.choices[0].message.content)
```

**JavaScript Example:**

```javascript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: `https://${routeUrl}/v1`,
  apiKey: 'EMPTY'
});

const response = await client.chat.completions.create({
  model: 'ibm-granite/granite-3.2-8b-instruct',
  messages: [
    { role: 'user', content: 'Explain GitOps in one sentence' }
  ]
});

console.log(response.choices[0].message.content);
```

## Advanced Features and Benefits

### 1. Automatic Self-Healing

ArgoCD continuously monitors your deployment. If someone manually changes a resource, ArgoCD automatically reverts it to the desired state defined in Git.

```bash
# Try manually changing the model
oc patch inferenceservice granite-3-2-8b-instruct -n test-model-serving \
  --type=json -p='[{"op": "replace", "path": "/spec/predictor/containers/0/resources/limits/memory", "value": "8Gi"}]'

# ArgoCD will automatically revert this change within seconds!
```

### 2. Version Control and Rollback

Every change is tracked in Git, enabling easy rollbacks:

```bash
# Rollback to previous version
git revert HEAD
git push

# ArgoCD automatically applies the rollback
```

### 3. Multi-Environment Deployments

Deploy the same model to multiple environments with different configurations:

```yaml
# dev-model-serving.yaml
destination:
  namespace: dev-models
  
# prod-model-serving.yaml  
destination:
  namespace: prod-models
```

### 4. Resource Optimization

vLLM runtime provides excellent GPU utilization:
- **GPU memory utilization**: Configurable (default 75%)
- **Continuous batching**: Automatic request batching
- **PagedAttention**: Efficient memory management
- **Tensor parallelism**: Multi-GPU support

### 5. Monitoring and Observability

Built-in integration with OpenShift monitoring:

```bash
# View metrics
oc get --raw /apis/metrics.k8s.io/v1beta1/namespaces/test-model-serving/pods

# Check resource usage
oc adm top pods -n test-model-serving

# View detailed pod metrics
oc describe pod <pod-name> -n test-model-serving
```

## Real-World Use Cases

### Use Case 1: Multi-Model Serving

Serve multiple models simultaneously:

```bash
# Deploy Granite model
oc apply -f gitops/model-serving-granite.yaml

# Deploy Llama model
oc apply -f gitops/model-serving-llama.yaml

# Deploy Mistral model
oc apply -f gitops/model-serving-mistral.yaml

# Expose all models
./scripts/expose-model.sh production-models
```

### Use Case 2: A/B Testing

Deploy different model versions for comparison:

```yaml
# model-v1.yaml
metadata:
  name: granite-v1
spec:
  destination:
    namespace: ab-testing

# model-v2.yaml
metadata:
  name: granite-v2
spec:
  destination:
    namespace: ab-testing
```

### Use Case 3: Development to Production Pipeline

```bash
# 1. Deploy to dev
oc apply -f gitops/model-serving-dev.yaml

# 2. Test in dev environment
./scripts/expose-model.sh dev-models

# 3. Promote to staging
oc apply -f gitops/model-serving-staging.yaml

# 4. Deploy to production
oc apply -f gitops/model-serving-prod.yaml
```

## Troubleshooting Common Issues

### Issue 1: Pod Stuck in Pending

**Symptom:** InferenceService pod remains in Pending state

**Solution:**
```bash
# Check GPU node availability
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU resources
oc describe node <gpu-node-name> | grep -A 5 "Allocated resources"

# Verify GPU operator is running
oc get pods -n nvidia-gpu-operator
```

### Issue 2: Model Download Fails

**Symptom:** Pod crashes during model download

**Solution:**
```bash
# Check pod logs
oc logs <pod-name> -n test-model-serving

# Verify internet connectivity
oc run test-curl --image=curlimages/curl -it --rm -- curl -I https://huggingface.co

# Check if model exists on HuggingFace
# Visit: https://huggingface.co/<model-path>
```

### Issue 3: Out of Memory

**Symptom:** Pod OOMKilled or crashes with memory errors

**Solution:**
```yaml
# Increase memory allocation
- op: replace
  path: /spec/predictor/containers/0/resources/limits/memory
  value: "32Gi"  # Increase from 16Gi

# Or reduce GPU memory utilization in kserve-model-serving.yaml
args:
- --gpu-memory-utilization
- "0.6"  # Reduce from 0.75
```

### Issue 4: ArgoCD Sync Fails

**Symptom:** Application shows "OutOfSync" or sync errors

**Solution:**
```bash
# Check ArgoCD application status
oc get application llmops-models -n openshift-gitops -o yaml

# View sync errors
oc describe application llmops-models -n openshift-gitops

# Manual sync
oc patch application llmops-models -n openshift-gitops \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

## Best Practices

### 1. Resource Planning

- **Start small**: Begin with 1 GPU and 16Gi memory
- **Monitor usage**: Use `oc adm top` to track actual resource consumption
- **Scale gradually**: Increase resources based on actual load

### 2. Model Selection

- **Choose appropriate models**: Match model size to available GPU memory
- **Consider quantization**: Use quantized models (4-bit, 8-bit) for resource efficiency
- **Test locally first**: Validate model compatibility before production deployment

### 3. GitOps Workflow

- **Use branches**: Develop changes in feature branches
- **Test in dev**: Always test in development namespace first
- **Review changes**: Use pull requests for production changes
- **Tag releases**: Tag stable configurations for easy rollback

### 4. Security

- **Use secrets**: Store sensitive data in Kubernetes Secrets
- **Enable RBAC**: Implement proper access controls
- **Secure routes**: Always use TLS for external access
- **Network policies**: Restrict pod-to-pod communication

### 5. Monitoring

- **Set up alerts**: Configure alerts for pod failures, OOM, GPU issues
- **Track metrics**: Monitor inference latency, throughput, GPU utilization
- **Log aggregation**: Centralize logs for troubleshooting
- **Regular audits**: Review resource usage and costs

## Conclusion

IBM Fusion's model serving solution represents a paradigm shift in how organizations deploy and manage AI models in production. By combining Red Hat OpenShift AI's robust model serving capabilities with GitOps principles through ArgoCD, Fusion delivers:

✅ **Simplicity** - Single configuration file for complete model serving setup
✅ **Reliability** - Self-healing, automated synchronization, and version control
✅ **Flexibility** - Easy customization for any model and resource requirements
✅ **Scalability** - GPU-accelerated inference with auto-scaling capabilities
✅ **Security** - Built-in RBAC, TLS encryption, and OpenShift security features
✅ **Observability** - Integrated monitoring, logging, and metrics

What once required days of complex configuration and specialized expertise can now be accomplished in minutes with a simple `oc apply` command. This democratization of AI infrastructure enables teams to focus on what truly matters - building innovative AI applications that deliver business value.

Whether you're deploying your first model or managing a fleet of AI services, IBM Fusion provides the foundation for reliable, scalable, and maintainable model serving in production.

## Getting Started

Ready to deploy your first model? Follow these steps:

1. **Install prerequisites**: Ensure OpenShift, RHOAI, and GitOps are installed
2. **Clone the repository**: `git clone https://github.com/the-dev-collection/Fusion-AI.git`
3. **Customize configuration**: Edit `fusion-model-serving/gitops/model-serving.yaml`
4. **Deploy**: `oc apply -f fusion-model-serving/gitops/model-serving.yaml`
5. **Expose**: `./fusion-model-serving/scripts/expose-model.sh test-model-serving`
6. **Test**: Use the provided curl commands to verify your deployment

## Additional Resources

- **GitHub Repository**: [Fusion-AI](https://github.com/the-dev-collection/Fusion-AI)
- **Documentation**: [Model Serving Guide](./docs/ModelServingGuide.md)
- **Red Hat OpenShift AI**: [Official Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- **KServe**: [KServe Documentation](https://kserve.github.io/website/)
- **ArgoCD**: [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

*IBM Fusion - Making Enterprise AI Simple, Reliable, and Scalable*
