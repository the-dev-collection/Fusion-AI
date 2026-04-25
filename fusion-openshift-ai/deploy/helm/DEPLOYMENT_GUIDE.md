# Red Hat OpenShift AI Helm Deployment Guide

This guide provides step-by-step instructions for deploying Red Hat OpenShift AI (RHOAI) using Helm charts.

## Overview

This Helm chart automates the installation of:
- Red Hat OpenShift AI Operator
- DataScienceCluster (DSC) with configurable components
- Required namespaces and operator groups

## Prerequisites

Before deploying, ensure you have:

1. **OpenShift Cluster Access**
   - OpenShift 4.12 or later
   - Cluster admin privileges
   - `oc` CLI tool installed and configured

2. **Helm Installation**
   - Helm 3.x installed
   - Verify with: `helm version`

3. **Cluster Requirements**
   - Access to Red Hat Operator Catalog (`redhat-operators`)
   - Sufficient cluster resources for AI/ML workloads

## Chart Structure

```
fusion-openshift-ai/deploy/helm/
├── Chart.yaml                    # Chart metadata
├── values.yaml                   # Default configuration values
├── templates/
│   ├── _helpers.tpl             # Template helpers
│   ├── operator.yaml            # Operator subscription and namespace
│   └── dsc.yaml                 # DataScienceCluster configuration
└── DEPLOYMENT_GUIDE.md          # This file
```

## Configuration

### Key Configuration Options

The [`values.yaml`](values.yaml) file contains all configurable parameters:

#### Namespace Configuration
```yaml
namespace:
  create: true                    # Create namespace if it doesn't exist
  name: redhat-ods-operator      # Namespace for RHOAI operator
```

#### Operator Subscription
```yaml
subscription:
  create: true
  name: rhods-operator
  channel: stable-3.x              # Operator channel (fast-3.x)
  source: redhat-operators       # Operator catalog source
  installPlanApproval: Automatic # Automatic or Manual
```

#### DataScienceCluster Components

Configure which components to enable. The following configuration is based on the reference DataScienceCluster CR:

```yaml
dataScienceCluster:
  components:
    aipipelines:
      managementState: Managed   # AI Pipelines for workflow orchestration
    dashboard:
      managementState: Managed   # RHOAI Dashboard UI
    feastoperator:
      managementState: Managed   # Feature store for ML
    kserve:
      managementState: Managed   # Model serving platform
      nim:
        managementState: Managed # NVIDIA NIM integration
    kueue:
      managementState: Removed   # Job queueing (optional)
    llamastackoperator:
      managementState: Removed   # LlamaStack operator (optional)
    mlflowoperator:
      managementState: Removed   # MLflow operator (optional)
    modelregistry:
      managementState: Managed   # Model registry
      registriesNamespace: rhoai-model-registries
    ray:
      managementState: Managed   # Distributed computing framework
    trainer:
      managementState: Managed   # Training jobs
    trainingoperator:
      managementState: Removed   # Training operator (optional)
    trustyai:
      managementState: Managed   # AI explainability and monitoring
    workbenches:
      managementState: Managed   # Jupyter notebooks and workbenches
```

**Management States:**
- `Managed`: Component is installed and managed by the operator
- `Removed`: Component is not installed
- `Unmanaged`: Component exists but is not managed by the operator

## Deployment Steps

### Step 1: Review and Customize Values

1. Navigate to the Helm chart directory:
   ```bash
   cd fusion-openshift-ai/deploy/helm
   ```

2. Review the default [`values.yaml`](values.yaml):
   ```bash
   cat values.yaml
   ```

3. (Optional) Create a custom values file:
   ```bash
   cp values.yaml custom-values.yaml
   ```

4. Edit `custom-values.yaml` to customize your deployment:
   ```bash
   vi custom-values.yaml
   ```

### Step 2: Validate the Chart

Validate the Helm chart syntax:
```bash
helm lint .
```

Preview the rendered templates:
```bash
helm template rhoai . -f values.yaml
```

Or with custom values:
```bash
helm template rhoai . -f custom-values.yaml
```

### Step 3: Install the Chart (One-Step Installation)

#### Option A: Install with Default Values

**Single command installation** (creates namespace automatically):

```bash
helm install rhoai . \
  --namespace redhat-ods-operator \
  --create-namespace
```

This single command will:
- Create the `redhat-ods-operator` namespace
- Install the RHOAI operator
- Deploy the DataScienceCluster with all configured components

#### Option B: Install with Custom Values

```bash
helm install rhoai . \
  -f custom-values.yaml \
  --namespace redhat-ods-operator \
  --create-namespace
```

#### Option C: Dry Run (Test Without Installing)

```bash
helm install rhoai . \
  --dry-run \
  --debug \
  --namespace redhat-ods-operator
```

### Step 4: Verify Installation

1. Check Helm release status:
   ```bash
   helm list -n redhat-ods-operator
   ```

2. Verify operator installation:
   ```bash
   oc get subscription -n redhat-ods-operator
   oc get csv -n redhat-ods-operator
   ```

3. Wait for operator to be ready:
   ```bash
   oc wait --for=condition=AtLatestKnown \
     subscription/rhods-operator \
     -n redhat-ods-operator \
     --timeout=300s
   ```

4. Check DataScienceCluster status:
   ```bash
   oc get datasciencecluster -n redhat-ods-operator
   oc describe datasciencecluster default-dsc -n redhat-ods-operator
   ```

5. Verify component deployments:
   ```bash
   oc get pods -n redhat-ods-applications
   oc get pods -n rhods-notebooks
   ```

### Step 5: Access the Dashboard

1. Get the dashboard route:
   ```bash
   oc get route -n redhat-ods-applications
   ```

2. Access the RHOAI dashboard using the route URL

## Upgrading

### Upgrade with New Values

```bash
helm upgrade rhoai . \
  -f custom-values.yaml \
  --namespace redhat-ods-operator
```

### Upgrade Operator Channel

To upgrade to a different operator channel, update [`values.yaml`](values.yaml):

```yaml
subscription:
  channel: stable-3.x  # Change from fast-3.x to stable-3.x
```

Then upgrade:
```bash
helm upgrade rhoai . \
  --namespace redhat-ods-operator
```

## Uninstalling

### Remove the Helm Release

```bash
helm uninstall rhoai -n redhat-ods-operator
```

### Clean Up Resources

The Helm uninstall may not remove all resources. Clean up manually:

```bash
# Delete DataScienceCluster
oc delete datasciencecluster --all -n redhat-ods-operator

# Delete operator subscription
oc delete subscription rhods-operator -n redhat-ods-operator

# Delete CSV (ClusterServiceVersion)
oc delete csv -l operators.coreos.com/rhods-operator.redhat-ods-operator -n redhat-ods-operator

# Delete namespace (optional)
oc delete namespace redhat-ods-operator
```

## Troubleshooting

### Operator Not Installing

1. Check subscription status:
   ```bash
   oc describe subscription rhods-operator -n redhat-ods-operator
   ```

2. Check install plan:
   ```bash
   oc get installplan -n redhat-ods-operator
   ```

3. Check operator pod logs:
   ```bash
   oc logs -n redhat-ods-operator -l name=rhods-operator
   ```

### DataScienceCluster Not Ready

1. Check DSC status:
   ```bash
   oc get datasciencecluster default-dsc -n redhat-ods-operator -o yaml
   ```

2. Check component conditions:
   ```bash
   oc describe datasciencecluster default-dsc -n redhat-ods-operator
   ```

3. Check application pods:
   ```bash
   oc get pods -n redhat-ods-applications
   ```

### Component Issues

For specific component issues:

```bash
# Check KServe
oc get pods -n redhat-ods-applications -l app=odh-model-controller

# Check Workbenches
oc get pods -n rhods-notebooks

# Check Dashboard
oc get pods -n redhat-ods-applications -l app=rhods-dashboard
```

## Advanced Configuration

### Custom Component Configuration

To customize specific components, modify the [`values.yaml`](values.yaml). Here's an example based on the reference DataScienceCluster:

```yaml
dataScienceCluster:
  name: default-dsc
  components:
    # Enable AI Pipelines for workflow management
    aipipelines:
      managementState: Managed
    
    # Enable Dashboard for UI access
    dashboard:
      managementState: Managed
    
    # Enable Feast for feature store capabilities
    feastoperator:
      managementState: Managed
    
    # Configure KServe for model serving with NIM support
    kserve:
      managementState: Managed
      nim:
        managementState: Managed
    
    # Model Registry with custom namespace
    modelregistry:
      managementState: Managed
      registriesNamespace: rhoai-model-registries
    
    # Enable Ray for distributed computing
    ray:
      managementState: Managed
    
    # Enable Trainer for training jobs
    trainer:
      managementState: Managed
    
    # Enable TrustyAI for model monitoring
    trustyai:
      managementState: Managed
    
    # Enable Workbenches for notebook environments
    workbenches:
      managementState: Managed
    
    # Optional components (set to Removed if not needed)
    kueue:
      managementState: Removed
    llamastackoperator:
      managementState: Removed
    mlflowoperator:
      managementState: Removed
    trainingoperator:
      managementState: Removed
```

**Component Descriptions:**

- **aipipelines**: Kubeflow Pipelines for ML workflow orchestration
- **dashboard**: Web-based UI for managing RHOAI resources
- **feastoperator**: Feature store for managing ML features
- **kserve**: Model serving platform with support for various frameworks
  - **nim**: NVIDIA NIM (NVIDIA Inference Microservices) integration
- **kueue**: Job queueing system for batch workloads
- **llamastackoperator**: Operator for LlamaStack deployments
- **mlflowoperator**: MLflow integration for experiment tracking
- **modelregistry**: Central registry for ML models
- **ray**: Distributed computing framework for scaling ML workloads
- **trainer**: Training job management
- **trainingoperator**: Kubernetes operator for distributed training
- **trustyai**: AI explainability, fairness, and monitoring tools
- **workbenches**: Jupyter notebook environments and development workspaces

### Using Helm Values Override

Override specific values from command line:

```bash
helm install rhoai . \
  --set subscription.channel=stable-3.x \
  --set dataScienceCluster.components.ray.managementState=Removed \
  --namespace redhat-ods-operator
```

### Multiple Environments

Create environment-specific values files:

```bash
# Development
helm install rhoai . -f values-dev.yaml

# Production
helm install rhoai . -f values-prod.yaml
```

## Best Practices

1. **Version Control**: Keep your custom `values.yaml` files in version control
2. **Testing**: Always test with `--dry-run` before actual deployment
3. **Backup**: Document your configuration before upgrades
4. **Monitoring**: Set up monitoring for operator and component health
5. **Resource Limits**: Configure appropriate resource limits for production workloads
6. **Security**: Review and configure security settings for your environment

## Additional Resources

- [Red Hat OpenShift AI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- [Helm Documentation](https://helm.sh/docs/)
- [OpenShift Operator Lifecycle Manager](https://docs.openshift.com/container-platform/latest/operators/understanding/olm/olm-understanding-olm.html)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review OpenShift and operator logs
3. Consult Red Hat OpenShift AI documentation
4. Contact Red Hat Support (for enterprise customers)