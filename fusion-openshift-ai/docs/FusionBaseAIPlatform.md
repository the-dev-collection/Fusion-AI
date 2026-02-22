# GitOps-Driven Installation of Red Hat OpenShift AI on IBM Fusion with Argo CD
Artificial Intelligence workloads are rapidly becoming a core part of modern enterprise platforms. Organizations require a scalable, Kubernetes-native way to build, train, deploy, and manage machine learning models efficiently across hybrid cloud environments.

Red Hat OpenShift AI (RHOAI) extends Red Hat OpenShift with an enterprise-grade hybrid AI and MLOps platform, with tooling across the full AI/ML lifecycle, including training, serving, monitoring, and managing models.

IBM Fusion HCI provides the infrastructure foundation for AI workloads, while OpenShift GitOps (Argo CD) enables a declarative and continuously reconciled deployment model.

In this blog, we demonstrate how to install Red Hat OpenShift AI on IBM Fusion using Argo CD, ensuring a version-controlled and self-healing operator lifecycle.

This approach delivers:
  - A fully GitOps-managed RHOAI operator installation
  - Declarative deployment of core data science platform components
  - Continuous synchronization and health monitoring through Argo CD

#### Why GitOps for Operator Installation?

Operators can be installed manually through the OpenShift console, but production environments require consistency across clusters.

GitOps ensures operator installation is version-controlled and automatically reconciled, making deployments predictable and auditable across environments.


## Prerequisites
Before installing the Red Hat OpenShift AI Operator using OpenShift GitOps (Argo CD), ensure the following prerequisites are in place on your IBM Fusion HCI cluster.

#### Cluster and Platform Requirements
  - IBM Fusion HCI cluster with Red Hat OpenShift Container Platform installed, running, and accessible
  - At least one worker node capable of supporting AI workloads (GPU-enabled if required)

#### Storage Configuration

  - A default StorageClass must be available for provisioning persistent volumes required by OpenShift AI components (workbenches, pipelines, and model storage)

Verify storage classes:
```
oc get sc
```
If no default storage class is set, configure one using IBM Fusion Data Foundation or another supported storage provider.
#### Required Platform Operators

The following operators must be installed before proceeding:
  - Red Hat OpenShift GitOps Operator (Argo CD) - for GitOps-driven deployment and continuous sync
  - Node Feature Discovery (NFD) - to detect node hardware capabilities (such as GPUs)
  - NVIDIA GPU Operator (required only if GPU-based workloads are planned) - to enable GPU acceleration for training and serving
  - Red Hat OpenShift Service Mesh 3 Operator

#### Access and Permissions

  - `oc` CLI configured and authenticated to your OpenShift cluster
  - Cluster-admin or sufficient RBAC to create namespaces, roles, and Argo CD Applications
  - Access to the Argo CD UI or `oc apply` permissions in the `openshift-gitops` namespace

## Repository Setup

1. Fork the repository so it can serve as your GitOps source of truth.

2. Clone the forked copy of this repository:
```bash
   git clone git@github.com:<your-username>/Fusion-AI.git
```

3. Login to your cluster using `oc login` or by exporting the KUBECONFIG:
```bash
   oc login
```

## GitOps Repository Structure
```bash
fusion-openshift-ai/
├── docs/
│   └── FusionBaseAIPlatform.md          # Documentation and deployment guide
│
├── gitops/
│   ├── rhoai-application.yaml           # Argo CD Application CR
│   │
│   └── rhoai/
│       ├── operator.yaml                # RHOAI Operator subscription and install
│       ├── dsc.yaml                     # DataScienceCluster (platform configuration)
│       ├── kustomization.yaml           # Kustomize base to manage resources
│       ├── patch-argocd-rbac.yaml       # RBAC patch for Argo CD permissions
│       └── patch-argocd-health-job.yaml # Health check enhancements for Argo CD
```

## Bootstrapping the Installation with an Argo CD Application

The installation begins with a single Argo CD Application resource defined in Git.

The entry point for the installation is the Application manifest: `rhoai-application.yaml` 

To bootstrap the installation, apply the Application directly from your local repository:
```bash
oc apply -f fusion-openshift-ai/gitops/rhoai-application.yaml
```

This Application instructs Argo CD to deploy all manifests from the following Git path:
```bash
source:
  path: fusion-openshift-ai/gitops/rhoai
```
Sync is fully automated, meaning Argo CD will both install and continuously self-heal the platform:

```
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```
Once this Application is applied, Argo CD becomes responsible for the complete RHOAI installation lifecycle, managing operator installation, RBAC setup, CR creation, and ongoing reconciliation of the platform state.

## Verifying the Installation in Argo CD

After applying the Argo CD Application, the installation can be verified directly from the OpenShift console.

Navigate to:

**Red Hat Applications → OpenShift GitOps → Cluster Argo CD**

<p align="center"><img width="309" alt="image" src="https://github.ibm.com/user-attachments/assets/030d4eb7-2dca-4bd8-9476-d517ecaf4486" /><p>


This opens the Argo CD dashboard, where the rhoai-install application will appear once synchronization completes.

  ### Argo CD Authentication 

  ####  Local Admin User
Log in using the CLI and retrieve the Argo CD admin credentials.
```bash
oc login --token=<TOKEN> --server=<API_SERVER>
```
Grant the required permissions:
```bash
oc adm policy add-cluster-role-to-user cluster-admin \
  -z openshift-gitops-argocd-application-controller \
  -n openshift-gitops
```
Retrieve the Argo CD admin password:
```bash
argoPass=$(oc get secret/openshift-gitops-cluster \
  -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d)

echo $argoPass
```
Use this password to log in to the Argo CD UI as the admin user.

### Expected Application Status
Once synchronization completes successfully, the application should display:
  - Application Name: rhoai-install
  - Sync Status: Synced
  - Health Status: Healthy
  - All associated Kubernetes resources reconciled under GitOps management

<p align="center"><img width="1666" alt="image" src="https://github.ibm.com/user-attachments/assets/f3b2f7d9-9b9f-4243-93c9-ed772ddcb229" /><p>

A synced and Healthy state confirms that the desired configuration stored in Git matches the live cluster state and that the OpenShift AI components are functioning as expected.

## How Argo CD Drives the Installation Flow

After the Application is applied, Argo CD orchestrates the installation sequence using the manifests defined in Git.

All manifests are organized with Kustomize (`kustomization.yaml`), allowing Argo CD to apply resources in a predictable GitOps sequence:
  - Install the operator (operator.yaml)
  - Apply RBAC for patching (patch-argocd-rbac.yaml)
  - Enable custom health checks (patch-argocd-health-job.yaml)
  - Initialize the platform (dsc.yaml)


  ### Operator Installation Through GitOps 
The installation begins with `operator.yaml`, which installs the Red Hat OpenShift AI operator through OLM (Namespace, OperatorGroup, and Subscription).

Argo CD monitors the operator installation until the ClusterServiceVersion reaches the Succeeded phase.

  ### Making Argo CD Operator-Aware
RHOAI introduces operator-managed resources such as CSVs, DSCInitialization, and DataScienceCluster.

By default, Argo CD does not understand the health conditions of these custom resources. An early PreSync RBAC step (`patch-argocd-rbac.yaml`) grants Argo CD permission to patch its own configuration.

  ### Enabling Custom Health Checks for RHOAI
Next, a PreSync Job (`patch-argocd-health-job.yaml`) updates Argo CD with health logic for:
  - CSV = Succeeded
  - DSCInitialization = Ready
  - DataScienceCluster = Ready

This prevents the operator installation from remaining in a perpetual Progressing state within Argo CD.

  ### Initializing the AI Platform with DataScienceCluster
Finally, Argo CD applies `dsc.yaml`, creating the DataScienceCluster resource that triggers deployment of the full OpenShift AI platform.

From this point onward, Argo CD continuously reconciles the platform state with the desired configuration stored in Git.

## Customizing OpenShift AI with DataScienceCluster Components

The DataScienceCluster specification is organized by platform components.

Each component is controlled through a simple switch called managementState:
  - **Managed** → the component is enabled and deployed
  - **Removed** → the component is disabled and not installed

This makes the DataScienceCluster the central place to customize exactly what gets installed in your OpenShift AI platform.


  ####  Components Enabled in This Setup (Managed)
In this configuration, the following core services are enabled:
  - **Dashboard** – provides the OpenShift AI user interface
  - **Workbenches** – enables notebook environments, deployed into rhods-notebooks
  - **KServe** – activates model serving, with Headless deployment mode
      - **NIM integration** is also enabled under KServe
  - **Model Registry** – deployed into rhoai-model-registries for managing model metadata
  - **TrustyAI** – enables responsible AI evaluation, with restricted execution and no online access
  - **AI Pipelines** – provides workflow and pipeline orchestration
  - **Ray** – enables distributed compute workloads
  - **Training Operator** – supports Kubernetes-native model training workloads

These components form the core of a full production AI platform: notebooks, serving, training, pipelines, and governance.

  #### Components Explicitly Disabled (Removed)
Several optional operators are intentionally excluded to keep the platform lightweight:
  - **Feast Operator** – feature store integration
  - **Trainer** – additional training abstraction layer
  - **MLflow Operator** – experiment tracking and model lifecycle tooling
  - **LlamaStack Operator** – advanced LLM stack services
  - **Kueue** – batch scheduling and queue-based workload orchestration

Marking these as Removed ensures they are not installed at all, reducing cluster overhead and operator sprawl.


## Final Outcome: A Fully GitOps-Managed AI Platform on Fusion
Using this approach, Red Hat OpenShift AI is installed and managed declaratively on IBM Fusion through a single Argo CD Application resource.

The operator lifecycle, health monitoring, and platform configuration are fully controlled from Git, ensuring consistency across environments.

This establishes a scalable and production-ready deployment model for enterprise AI workloads.
