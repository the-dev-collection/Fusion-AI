# Namespace Configuration Guide

## Overview

The fusion-model-serving configuration has been updated to allow you to specify the target namespace directly in the Application CR itself. This provides flexibility to deploy model serving resources to any namespace without modifying individual resource files.

## How It Works

The namespace configuration uses ArgoCD's built-in namespace transformation capability combined with Kustomize:

1. **Application CR** (`llmops-application.yaml`) - Specifies the target namespace in `spec.destination.namespace`
2. **Kustomize** - Automatically applies the namespace to all resources
3. **Resource Files** - No longer contain hardcoded namespaces

## Changing the Target Namespace

To deploy model serving resources to a different namespace, simply edit the Application CR:

```yaml
# File: fusion-model-serving/gitops/llmops-application.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: llmops-models
  namespace: openshift-gitops
spec:
  destination:
    server: https://kubernetes.default.svc
    # CUSTOMIZE THIS: Change to your desired namespace
    namespace: your-custom-namespace  # <-- Change this value
  syncPolicy:
    syncOptions:
      - CreateNamespace=true  # Automatically creates the namespace if it doesn't exist
```

## Examples

### Example 1: Deploy to a custom namespace

```yaml
spec:
  destination:
    namespace: my-ml-models
```

### Example 2: Deploy to a project-specific namespace

```yaml
spec:
  destination:
    namespace: production-models
```

### Example 3: Deploy to a team namespace

```yaml
spec:
  destination:
    namespace: data-science-team
```

## What Gets Deployed

All resources will be deployed to the specified namespace:

- **InferenceService** (`granite-llm`) - The KServe model serving instance
- **ConfigMap** (`inferenceservice-config`) - Required configuration for ODH Model Controller
- **Role** (`argocd-manager`) - RBAC permissions for ArgoCD
- **RoleBinding** (`argocd-manager`) - Binds the role to ArgoCD service account

## Important Notes

1. **Namespace Creation**: The `CreateNamespace=true` sync option ensures the namespace is automatically created if it doesn't exist.

2. **RBAC**: The Role and RoleBinding are created in the target namespace, allowing ArgoCD to manage resources there.

3. **No Code Changes Required**: You don't need to modify any resource files (YAML files in the `models/` directory) - just change the Application CR.

4. **Multiple Deployments**: You can create multiple Application CRs pointing to the same source path but with different namespaces to deploy the same model serving configuration to multiple namespaces.

## Verification

After changing the namespace, verify the deployment:

```bash
# Check if the namespace was created
oc get namespace <your-namespace>

# Check if resources are deployed
oc get inferenceservice -n <your-namespace>
oc get configmap -n <your-namespace>
oc get role,rolebinding -n <your-namespace>

# Check ArgoCD application status
oc get application llmops-models -n openshift-gitops
```

## Troubleshooting

### Issue: Resources not appearing in the new namespace

**Solution**: Check the ArgoCD application sync status:
```bash
oc get application llmops-models -n openshift-gitops -o yaml
```

### Issue: Permission denied errors

**Solution**: Ensure the ArgoCD service account has permissions in the target namespace. The RBAC resources should be automatically created, but verify:
```bash
oc get rolebinding argocd-manager -n <your-namespace>
```

## Architecture

```
Application CR (llmops-application.yaml)
    ↓
    └─ spec.destination.namespace: "your-namespace"
         ↓
         └─ Kustomize processes resources
              ↓
              └─ All resources deployed to "your-namespace"
                   ├─ InferenceService
                   ├─ ConfigMap
                   ├─ Role
                   └─ RoleBinding
```

## Migration from Hardcoded Namespaces

If you're migrating from the previous configuration with hardcoded namespaces (`krishi-rakshak-ds`):

1. The default namespace remains `krishi-rakshak-ds` for backward compatibility
2. To use a different namespace, simply update the Application CR as shown above
3. No changes to resource files are needed
4. ArgoCD will handle the migration automatically during the next sync

## Best Practices

1. **Use Descriptive Names**: Choose namespace names that clearly indicate their purpose (e.g., `ml-models-prod`, `ai-serving-dev`)
2. **Environment Separation**: Use different namespaces for different environments (dev, staging, production)
3. **Team Isolation**: Use separate namespaces for different teams or projects
4. **Resource Quotas**: Consider setting resource quotas on namespaces to manage GPU and memory allocation
5. **Network Policies**: Implement network policies if you need to isolate model serving traffic

## Related Files

- [`llmops-application.yaml`](./llmops-application.yaml) - Main Application CR
- [`models/kustomization.yaml`](./models/kustomization.yaml) - Kustomize configuration
- [`models/kserve-model-serving.yaml`](./models/kserve-model-serving.yaml) - InferenceService definition
- [`models/rbac.yaml`](./models/rbac.yaml) - RBAC resources
- [`models/inferenceservice-config.yaml`](./models/inferenceservice-config.yaml) - ConfigMap