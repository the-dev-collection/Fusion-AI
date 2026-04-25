
## Required Platform Operators
The following operators must be installed and in a Ready state:
  - Red Hat OpenShift GitOps (Argo CD)
    - Enables declarative, Git-driven deployment and reconciliation.
    
## Deploying the Model Serving Application 

Model serving is deployed using an Argo CD Application that continuously syncs Kubernetes manifests from Git.

### Apply the Argo CD Application
Before applying the Application, update the `source.repoURL` field in model-serving-application.yaml to point to your forked repository:
```bash
spec:
  source:
    repoURL: https://github.com/<your-username>/storage-fusion.git
```
Ensure the repository URL matches the fork you cloned and are using as your GitOps source of truth.


Apply the application YAML:
```bash
oc apply -f fusion-model-serving/gitops/model-serving-application.yaml
```

This creates an Argo CD Application that points to:
```
fusion-model-serving/gitops/models
```
The Application name defaults to llmops-models but can be customized in the Application manifest metadata.

This creates an Argo CD Application (llmops-models) in the openshift-gitops namespace, which points to:
  - **Git repository path:** fusion-model-serving/gitops/models
  - **Target namespace**: model-serving (default)
The target namespace can be customized directly in the Application manifest by modifying `spec.destination.namespace`.



Once applied, Argo CD will automatically:
  - **Create the target namespace** (model-serving) if namespace auto-creation is enabled in the sync policy.
  - **Provision RBAC permissions** (Roles, RoleBindings) required for KServe and model pods to run securely.
  - **Deploy the InferenceService CR**, triggering OpenShift AI + KServe to launch the predictor workload on IBM Fusion HCI.- by default ibm-granite/granite-3.2-8b-instruct.
  - **Create internal Kubernetes Services** (via KServe), and external access is optional and must be configured separately using OpenShift Routes.

Any drift from the declared Git state is automatically corrected by Argo CD.

### Monitor Deployment

After applying the Application, monitor the rollout to ensure all resources are created successfully.

Watch the deployment progress:

```bash
# Check Argo CD application status
oc get application llmops-models -n openshift-gitops

# Monitor InferenceService
oc get inferenceservice -n model-serving

# Watch pod creation
oc get pods -n model-serving -w
```

#### Model Deployment Phases

During startup, the model-serving workload typically moves through these states:

- Pending: Waiting for scheduling onto a GPU-enabled Fusion HCI worker node
- ContainerCreating: Container image pulling and initialization
- Running: vLLM container started, and model download begins
- Ready: Model fully loaded and serving inference traffic

These states primarily reflect the lifecycle of the predictor pod created by the KServe InferenceService, with final readiness determined by the InferenceService status.


## Argo CD Application View

After applying the Argo CD Application, the deployment can be verified from the OpenShift console.

Navigate to:

**Red Hat Applications → OpenShift GitOps → Cluster Argo CD**

<p align="center"><img width="309" alt="image" src="https://github.ibm.com/user-attachments/assets/030d4eb7-2dca-4bd8-9476-d517ecaf4486" /><p>


When prompted, log in using your OpenShift (OCP) credentials via the integrated OAuth authentication.

This opens the Argo CD dashboard, where the llmops-models application will appear once synchronization completes.


### Expected Application Status

Once the Argo CD application is successfully synced, it will appear in the Argo CD UI as shown below.

The application should display:
- **Application Name:** `llmops-models`
- **Sync Status:** `Synced`
- **Health Status:** `Healthy`
- All Kubernetes resources managed under GitOps

<p align="center"><img width="1725" alt="model-serving" src="https://github.ibm.com/user-attachments/assets/0497640d-1b0d-4a27-b469-b0b92f0120fb" /></p>


---
## Exposing the Model for External Access
By default, KServe creates internal ClusterIP services for InferenceServices. These services are not externally accessible in OpenShift unless explicitly exposed using a Route or Ingress.

By default, KServe InferenceServices are only accessible within the cluster. To make them available to external applications (dashboards, APIs, or client tools), use the included expose-model.sh script to create an OpenShift Edge-terminated Route.

The `expose-model.sh` utility automatically generates OpenShift Routes with TLS encryption, making your models available outside the cluster.

It supports two usage modes:

#### 1. Expose All Models in a Namespace

To expose every deployed InferenceService in a given namespace:
```bash
# Expose all models in a namespace
./scripts/expose-model.sh <namespace>
```

```bash
# Example
./scripts/expose-model.sh test-model-serving
```

This will:
  - Discover all InferenceServices in the namespace
  - Create TLS-secured OpenShift Routes for each model
  - Display the external access URLs and test commands


## Customizing the Model Serving Application

The deployment is designed with stable base manifests, while customization is handled through the OpenShift GitOps Application resource.

Instead of editing multiple YAML files, model name, resources, and metadata are adjusted using spec.source.kustomize.patches. This keeps the setup reusable and allows you to serve different models by changing only a few values.

All customization happens in the Argo CD Application manifest, while the base templates remain reusable and unchanged.

Customization is grouped into two key areas.

### 1. Application Identity and Labels
The first customization controls the labels applied across all resources deployed by this application.

Within the Application YAML, the following patch overrides the commonLabels defined in the base Kustomization:

```
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
To customize this for a different application, users only need to change the values:
  - Change `llmops-models` to the desired application name
  - Change `llmops-platform` to match the target platform or environment label

For example:

``` value: text-generation-serving```

This ensures that all resources deployed by Argo CD automatically carry the correct application identity.

### 2. Configuring the Model and InferenceService Deployment

The model name and all InferenceService settings are configured together in a single patch. The model is set directly as an environment variable on the container — no ConfigMap is involved. This avoids naming conflicts when multiple models are deployed to the same namespace.

In the Application YAML, the following patch defines the model identity, resource requirements, and serving configuration:
```
- target:
    kind: InferenceService
  patch: |-
    - op: replace
      path: /metadata/name
      value: granite-3-2-8b-instruct
    - op: replace
      path: /metadata/labels/model
      value: granite
    - op: replace
      path: /spec/predictor/containers/0/env/0/value
      value: ibm-granite/granite-3.2-8b-instruct
    - op: replace
      path: /spec/predictor/containers/0/resources/limits/nvidia.com~1gpu
      value: "1"
    - op: replace
      path: /spec/predictor/containers/0/resources/limits/memory
      value: "16Gi"
    - op: replace
      path: /spec/predictor/containers/0/resources/requests/nvidia.com~1gpu
      value: "1"
    - op: replace
      path: /spec/predictor/containers/0/resources/requests/memory
      value: "16Gi"
```

  - `metadata.name` defines the Kubernetes InferenceService name, which becomes the serving endpoint identifier.
  - `labels.model` adds a model-family label (granite) for tracking, filtering, and observability.
  - `env[0].value` sets the Hugging Face model ID (`MODEL`) passed directly to the vLLM container — no ConfigMap required. To serve a different model, update this value only. For example, to serve Mistral: `value: mistralai/Mistral-7B-Instruct-v0.2`
  - `limits.nvidia.com/gpu` sets the maximum GPU count the serving container can consume during inference.
  - `limits.memory` caps the memory usage to prevent resource exhaustion or OOM termination.
  - `requests.nvidia.com/gpu` ensures the pod is scheduled only on nodes with an available GPU by reserving one.
  - `requests.memory` reserves the required RAM upfront to guarantee stable scheduling and startup.

By configuring both requests and limits, this patch ensures predictable GPU-backed model serving and makes the application flexible enough to support anything from lightweight models to GPU-heavy LLM workloads.

Ensure that the requested GPU and memory values align with the actual node capacity.
If insufficient resources are available, the InferenceService will remain Pending.
