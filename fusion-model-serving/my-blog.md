# Deploying LLM on IBM Fusion HCI with llm-d and Red Hat OpenShift AI 3.0


## Introduction

Getting an LLM to respond is the easy part. Getting it to respond consistently, at scale, with observable performance — that's where most deployments run into trouble.

Red Hat OpenShift AI 3.0 introduces a new inference architecture built around llm-d, which disaggregates the Prefill and Decode phases of LLM inference into separate, independently-scalable pod pools. Running this stack on IBM Fusion HCI further simplifies GPU, storage, and operator readiness for enterprise AI workloads.

In this blog, I'll walk through the prerequisites, the `LLMInferenceService` CR configuration with full Prefill-Decode separation, the authentication setup via Red Hat Connectivity Link, and three rounds of load testing with real Prometheus metrics. The model used was `mistralai/Ministral-3-8B-Instruct-2512`, deployed in the `llm-model-serving` namespace on IBM Fusion HCI running OpenShift 4.19+.

---

## Architecture: What We're Building

The request path from user to model looks like this:

```
User Request (HTTPS)
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Gateway API (openshift-ingress namespace)                   │
│ - openshift-ai-inference Gateway                            │
│ - Port 443, TLS termination                                 │
│ - OpenShift-managed certificate                             │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Kuadrant (Red Hat Connectivity Link)                        │
│ ├── Authorino → KubernetesTokenReview (JWT validation)      │
│ └── Limitador → Rate limiting                               │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ EPP Scheduler (Endpoint Picker Protocol)                    │
│                                                              │
│ Scheduling Plugins:                                         │
│ ├── prefill-header-handler                                  │
│ ├── prefill-filter    → routes prefill to prefill pool      │
│ ├── decode-filter     → routes decode to decode pool        │
│ ├── queue-scorer      → weight 1.0 (queue depth)            │
│ ├── kv-cache-utilization-scorer → weight 2.0 (cache hits)   │
│ ├── max-score-picker  → selects highest-scoring pod         │
│ └── pd-profile-handler                                      │
└─────────────────────────────────────────────────────────────┘
        │
   ┌────┴────────┐
   ▼             ▼
┌─────────┐  ┌─────────┐
│ Prefill │  │ Decode  │
│  Pool   │  │  Pool   │
├─────────┤  ├─────────┤
│ Pod 1   │  │ Pod 1   │
│ (1 GPU) │  │ (1 GPU) │
├─────────┤  ├─────────┤
│ Pod 2   │  │ Pod 2   │
│ (1 GPU) │  │ (1 GPU) │
└─────────┘  └─────────┘
```

**What llm-d changes about this picture** is the EPP Scheduler layer. Traditional vLLM deployments route requests using round-robin or simple load balancing. The EPP Scheduler in llm-d routes based on semantic awareness of the inference pipeline: it understands which phase a request is in (prefill vs decode), which pods have warm KV caches for similar prompts, and the current queue depth per pod. The result is measurably better GPU utilization and lower time-to-first-token (TTFT) for workloads with prompt overlap.

---

## Prerequisites

### IBM Fusion HCI Cluster

- IBM Fusion HCI cluster installed, running, and healthy
- OpenShift 4.19+ running on Fusion
- GPU nodes with NVIDIA GPUs
- Cluster admin access

### OpenShift Cluster and Operator Requirements

According to the [official OpenShift AI 3.3 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/deploying_models#deploying-models-using-distributed-inference_rhoai-user):

**Required Operators:**

Install these operators from OperatorHub in the OpenShift Web Console:

| Operator | Channel | Purpose | Notes |
|---|---|---|---|
| Red Hat OpenShift AI | `fast-3.x` | Core AI/ML platform with KServe | Includes model serving capabilities |
| NVIDIA GPU Operator | `v25.10` | GPU device plugin & drivers | Required for GPU workloads |
| Red Hat Connectivity Link | `stable` (v1.1.1+) | API gateway, auth & rate limiting (Kuadrant) | Must be installed before deploying models |
| Red Hat OpenShift Serverless | `stable` | Knative for serverless inference scaling | Required for KServe |
| Node Feature Discovery | `stable` | Detects hardware features (GPUs, CPUs) | Auto-labels GPU nodes |
| LeaderWorkerSet Operator | `stable` | Manages prefill-decode pod groups | Required for llm-d |

**Verify Operator Installation:**

```bash
# Check all operators are in Succeeded state
oc get csv -A | grep -E "rhods|gpu|rhcl|serverless|nfd|leaderworkerset"
```

**Cluster Requirements:**
- OpenShift cluster running version **4.19.9 or later** on IBM Fusion HCI
- OpenShift Service Mesh v2 must **not** be installed (conflicts with Gateway API)
- A `GatewayClass` and a `Gateway` named `openshift-ai-inference` in the `openshift-ingress` namespace
- Access to the OpenShift CLI (`oc`)
- Cluster admin access

**Verify Gateway API Resources:**

```bash
# Verify Gateway API is configured
oc get gatewayclass
oc get gateway -n openshift-ingress openshift-ai-inference
```

**Authentication Requirements:**
- Red Hat Connectivity Link must be configured **before** deploying the `LLMInferenceService`
- Create a `ServiceAccount` with permission to access the `LLMInferenceService`
- Generate a JWT token for API authentication

---

## Step 1: Configure Authentication First

**Critical ordering requirement:** Authentication via Red Hat Connectivity Link must be configured **before** deploying the `LLMInferenceService`. The ODH Model Controller creates `AuthPolicy` resources automatically when you deploy a model — but only if Kuadrant is already running and Authorino is properly configured.

### Create the Kuadrant CR

```bash
oc apply -f - <<EOF
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
spec: {}
EOF
```

Wait for it to become ready:

```bash
oc wait Kuadrant -n kuadrant-system kuadrant --for=condition=Ready --timeout=10m
```

### Enable TLS for Authorino

This is required for token-based authentication. The annotation tells OpenShift's service-ca operator to generate a signed TLS certificate for the Authorino service:

```bash
oc annotate svc/authorino-authorino-authorization \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  -n kuadrant-system
```

Then update the Authorino CR to use that certificate:

```bash
oc apply -f - <<EOF
apiVersion: operator.authorino.kuadrant.io/v1beta1
kind: Authorino
metadata:
  name: authorino
  namespace: kuadrant-system
spec:
  replicas: 1
  clusterWide: true
  listener:
    tls:
      enabled: true
      certSecretRef:
        name: authorino-server-cert
  oidcServer:
    tls:
      enabled: false
EOF
```

Wait for the pods:

```bash
oc wait --for=condition=ready pod -l authorino-resource=authorino \
  -n kuadrant-system --timeout 150s
```

### If OpenShift AI Was Installed Before Connectivity Link

If RHOAI was already running when you installed Connectivity Link, restart the controllers so they pick up the Kuadrant integration:

```bash
oc delete pod -n redhat-ods-applications -l app=odh-model-controller
oc delete pod -n redhat-ods-applications -l control-plane=kserve-controller-manager
```

### How AuthPolicies Are Created Automatically

Once Kuadrant is running, when you deploy an `LLMInferenceService` the ODH Model Controller automatically creates two `AuthPolicy` objects — one at the Gateway level and one scoped to the HTTPRoute for your specific model. You verify them after deployment:

```bash
oc get authpolicy -A
# NAMESPACE          NAME                             TARGETREF
# openshift-ingress  openshift-ai-inference-authn     Gateway
# llm-model-serving  ministral-3-8b-pd-kserve-route-authn  HTTPRoute
```

For production, leave authentication enabled (the default). To explicitly re-enable if it was disabled:

```yaml
annotations:
  security.opendatahub.io/enable-auth: "true"
```

---

## Step 2: Deploy the LLMInferenceService with PD Separation

This is the core of what makes llm-d different from a standard KServe deployment. The `LLMInferenceService` CR defines separate Prefill and Decode replica pools, and configures the EPP Scheduler with plugin weights that determine how requests are routed between them.

Here is the full CR we used:

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: ministral-3-8b-pd
  namespace: llm-model-serving
spec:
  model:
    name: mistralai/Ministral-3-8B-Instruct-2512
    uri: 'hf://mistralai/Ministral-3-8B-Instruct-2512'

  # Prefill pool: compute-intensive prompt processing
  prefill:
    replicas: 2
    template:
      containers:
        - env:
            - name: HF_HOME
              value: /models/cache
          livenessProbe:
            failureThreshold: 10
            httpGet:
              path: /health
              port: 8000
              scheme: HTTPS
            initialDelaySeconds: 300
            periodSeconds: 30
            timeoutSeconds: 60
          name: main
          resources:
            limits:
              cpu: '4'
              memory: 48Gi
              nvidia.com/gpu: '1'
            requests:
              cpu: '4'
              memory: 48Gi
              nvidia.com/gpu: '1'

  # Decode pool: memory-bandwidth-sensitive token generation
  replicas: 2

  # Gateway and HTTPRoute
  router:
    gateway: {}
    route: {}

  # EPP Scheduler configuration
  scheduler:
    template:
      containers:
        - args:
            - '--pool-name'
            - '{{ ChildName .ObjectMeta.Name `-inference-pool` }}'
            - '--pool-namespace'
            - '{{ .ObjectMeta.Namespace }}'
            - '--zap-encoder'
            - json
            - '--grpc-port'
            - '9002'
            - '--grpc-health-port'
            - '9003'
            - '--secure-serving'
            - '--model-server-metrics-scheme'
            - https
            - '--enable-pprof'
            - '--zap-log-level'
            - debug
            - '--cert-path'
            - /var/run/kserve/tls
            - '--config-text'
            - |
              apiVersion: inference.networking.x-k8s.io/v1alpha1
              kind: EndpointPickerConfig
              plugins:
                - type: prefill-header-handler
                - type: prefill-filter
                - type: decode-filter
                - type: queue-scorer
                - type: kv-cache-utilization-scorer
                - type: max-score-picker
                - type: pd-profile-handler
              parameters:
                threshold: 0
                hashBlockSize: 16
              schedulingProfiles:
                - name: prefill
                  plugins:
                    - pluginRef: prefill-filter
                    - pluginRef: queue-scorer
                      weight: 1.0
                    - pluginRef: max-score-picker
                - name: decode
                  plugins:
                    - pluginRef: decode-filter
                    - pluginRef: queue-scorer
                      weight: 1.0
                    - pluginRef: kv-cache-utilization-scorer
                      weight: 2.0
                    - pluginRef: max-score-picker
          name: main
          resources: {}
  template:
    containers:
      - env:
          - name: HF_HOME
            value: /models/cache
        livenessProbe:
          failureThreshold: 10
          httpGet:
            path: /health
            port: 8000
            scheme: HTTPS
          initialDelaySeconds: 300
          periodSeconds: 30
          timeoutSeconds: 60
        name: main
        resources:
          limits:
            cpu: '4'
            memory: 48Gi
            nvidia.com/gpu: '1'
          requests:
            cpu: '4'
            memory: 48Gi
            nvidia.com/gpu: '1'
```

### Configuration Decisions Worth Explaining

**`hashBlockSize: 16`** controls the granularity of KV cache prefix matching. The EPP Scheduler tracks which blocks of context are cached on which decode pod. With a block size of 16 tokens, the scheduler can match cache state at a finer resolution — meaning partial prompt overlaps (shared system prompts, few-shot examples) still get cache hits. A larger block size is coarser and misses more partial matches; a smaller one creates more index overhead. 16 tokens was the tuned value for our workload.

**KV Cache Utilization Scorer weight 2.0 vs Queue Scorer weight 1.0** on the decode scheduling profile means the scheduler prioritizes cache hits over queue depth. The scheduler will send a request to a slightly busier pod if that pod already holds the matching KV prefix. For decode-phase requests, the cost of a cache miss (recomputing the full prompt context) outweighs the cost of a marginally longer queue. We measured this trade-off empirically — cache-aware routing provides better performance at any reasonable queue depth for our prompt distribution.

**Prefill scheduling is queue-only.** The prefill pool has no cache affinity scoring because prefill is purely compute-bound. Each prefill pod processes prompts independently; there's no cache state to reuse between prefill requests. Routing based only on queue length is both correct and optimal for the prefill phase.

**`initialDelaySeconds: 300`** on the liveness probe. Model loading for an 8B parameter model takes several minutes — the pod needs time to download model weights and load them into GPU memory before the health endpoint responds. This is particularly relevant on IBM Fusion HCI where storage reads happen over the network fabric; 300 seconds provides a safe buffer for model initialization.

---

## Step 3: Verify the Deployment

```bash
# Check overall status
oc get llminferenceservice -n llm-model-serving

# Expect: 2 prefill pods + 2 decode pods + 1 scheduler pod
oc get pods -n llm-model-serving

# Verify AuthPolicies were auto-created
oc get authpolicy -A

# Get the inference endpoint
oc get llminferenceservice ministral-3-8b-pd -n llm-model-serving \
  -o jsonpath='{.status.url}'
```

---

## Step 4: Load Testing and Observability

We ran two focused test scenarios to validate the Prefill-Decode separation and KV cache efficiency. All metrics were scraped by Prometheus and queried via the OpenShift monitoring stack.

### TEST 1 — Basic Load: Sanity Check and Token Metrics

The first test fires 50 concurrent requests with a detailed prompt to confirm that the PD separation is working — both pod pools receiving traffic, token metrics emitting correctly.

```bash
PROMPT="Explain Quantum Computing in detail with examples and code"
seq 1 50 | xargs -n1 -P15 -I{} curl -k \
  https://openshift-ai-inference.../v1/chat/completions \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"mistralai/Ministral-3-8B-Instruct-2512\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]
  }"
```


#### Running Requests

Validates load distribution across pods:

```promql
kserve_vllm:num_requests_running
```

<img width="3006" height="1586" alt="image" src="https://github.com/user-attachments/assets/d8d2e0db-4f71-42cf-91f1-c9e3b75e0ccf" />


#### Per-Pod Token Breakdown

**Decode tokens per pod:**
```promql
sum by(pod)(
  rate(kserve_vllm_generation_tokens_total{llm_svc_role="decode"}[1m])
)
```
<img width="2948" height="1336" alt="image" src="https://github.com/user-attachments/assets/ba784a2e-fbd3-4f2a-be6b-6468abe4eeba" />


**Prefill tokens per pod:**
```promql
sum by(pod)(
  rate(kserve_vllm_prompt_tokens_total{llm_svc_role="prefill"}[1m])
)
```

<img width="2934" height="1344" alt="image" src="https://github.com/user-attachments/assets/71081b6e-328d-430f-945e-0f9973aafcc4" />



**Results:** Both the `ministral-3-8b-pd-kserve-prefill-*` and `ministral-3-8b-pd-kserve-*` (decode) pods showed traffic, and the `llm_svc_role` label confirmed correct phase tagging. The EPP Scheduler correctly routed prefill-phase requests to the prefill pool and decode-phase requests to the decode pool, with no cross-contamination.

The metric graphs showed decode token generation climbing as 50 concurrent requests progressed through the pipeline. Prefill token throughput spiked early (parallel prompt processing is fast) and then settled as requests moved into the decode phase.

---

### TEST 2 — KV Cache Efficiency: The Critical Performance Test

KV cache efficiency is the primary performance differentiator of disaggregated inference. The metric that matters most is the prefix cache hit rate per decode pod. A high hit rate indicates the EPP Scheduler is correctly routing semantically-similar requests to the same decode pod, where the KV cache state from previous requests is already in GPU memory, eliminating redundant computation.

#### KV Cache Hits Per Decode Pod

Primary metric for cache effectiveness:

```promql
sum by(pod)(
  rate(kserve_vllm_prefix_cache_hits_total{llm_svc_role="decode"}[1m])
)
```
<img width="2940" height="1332" alt="image" src="https://github.com/user-attachments/assets/00b7f7ac-d3dc-40ac-b741-457d0b65b5d6" />


#### Token Comparison for Cache Efficiency

Shows the relationship between prompt tokens processed and cache hits:

```promql
increase(kserve_vllm_prompt_tokens_total[1m])
```

<img width="3026" height="1476" alt="image" src="https://github.com/user-attachments/assets/247e19e8-9ed2-4a5b-81d8-d56e02e34bec" />


#### Prefill Impact Analysis

**Cache hits:**
```promql
increase(kserve_vllm_prefix_cache_hits_total[1m])
```

<img width="3028" height="1470" alt="image" src="https://github.com/user-attachments/assets/37c0be63-bd0c-426f-ab53-492a9a438d3b" />


**Prompt tokens (overall):**
```promql
increase(kserve_vllm_prompt_tokens_total[1m])
```

<img width="2992" height="1376" alt="image" src="https://github.com/user-attachments/assets/199430f8-d46b-4497-9ed3-8ba134b9ab8f" />


**Prefill tokens per pod:**
```promql
sum by(pod)(
  increase(kserve_vllm_prompt_tokens_total{llm_svc_role="prefill"}[1m])
)
```

<img width="3014" height="1138" alt="image" src="https://github.com/user-attachments/assets/e342fe72-06a4-41cf-be0b-63e2235b1dc1" />


This counter tracks cumulative prefill load. Spikes correspond to new conversation turns or structurally unique prompts. The critical observation is that these spikes are isolated to the prefill pod pool — because PD is disaggregated, a sudden burst of new unique prompts does not impact decode latency on the decode pods. The two phases absorb their respective loads independently.

#### Time to First Token (TTFT)

**Token generation baseline:**
```promql
increase(kserve_vllm_generation_tokens_total[1m])
```

<img width="3008" height="1574" alt="image" src="https://github.com/user-attachments/assets/3c63f7c8-d12a-41be-affa-6daf0f19f764" />


**Decode tokens per pod:**
```promql
sum by(pod)(
  increase(kserve_vllm_generation_tokens_total{llm_svc_role="decode"}[1m])
)
```

<img width="3022" height="1022" alt="image" src="https://github.com/user-attachments/assets/8c3eb1d5-5cf1-46ac-8c9f-5c4886bcfdc7" />


**TTFT metric:**
```promql
rate(kserve_vllm_time_to_first_token_seconds_sum[1m])
```

<img width="3018" height="1460" alt="image" src="https://github.com/user-attachments/assets/fe7231c3-3302-48af-bd78-4e70818fdb10" />


TTFT is what users actually feel — the pause between sending a message and seeing the first token of the response. With KV cache prefix matching working, requests whose prompts share a prefix with a recently-processed request skip the prefill computation for the matching portion. The result is a measurable TTFT reduction for any workload with structural prompt similarity (shared system prompts, chat history, few-shot examples).

#### Decode Latency

**Request count (distribution/volume):**
```promql
rate(kserve_vllm_time_to_first_token_seconds_count[1m])
```

<img width="3010" height="1422" alt="image" src="https://github.com/user-attachments/assets/9415287b-edcb-4271-a899-a7c2e2a90e31" />


**Actual decode latency:**
```promql
rate(kserve_vllm_request_decode_time_seconds_sum[1m])
```

<img width="3008" height="1422" alt="image" src="https://github.com/user-attachments/assets/9b53e851-c9af-4d34-a1cb-01fe2aeef54b" />


This measures the time spent in the decode phase (token-by-token generation) per request. The KV cache utilization scorer at weight 2.0 meant decode pods with warm caches consistently outperformed cold pods for similar prompts. In the metrics, this showed up as lower decode latency variance — requests to the right pod (cache hit) completed faster and more predictably than requests to a cold pod.

#### Cache Efficiency Analysis

**Decode time count (efficiency signal):**
```promql
rate(kserve_vllm_request_decode_time_seconds_count[1m])
```

<img width="3022" height="1408" alt="image" src="https://github.com/user-attachments/assets/5fe0bbe4-eb4b-4e9d-b635-b40e19bbe310" />


**Prompt tokens (denominator/reference):**
```promql
increase(kserve_vllm_prompt_tokens_total[1m])
```

<img width="3006" height="1420" alt="image" src="https://github.com/user-attachments/assets/5225a5a6-b403-4d26-ab11-24f5388d4894" />


Per-pod cache hit metrics verify that the `hashBlockSize: 16` and the kv-cache-utilization-scorer at weight 2.0 are working correctly. If cache hits were evenly distributed across both decode pods, the prefix-cache scorer wouldn't be working — you'd see all hits going to whichever pod happened to process the first request. What we observed instead was asymmetric cache distribution: the decode pod that processed a given prompt class accumulated hits for subsequent similar prompts, confirming the sticky-routing behavior the scorer is designed to produce.

---

## Observability: From Black Box to Transparent Pipeline

Traditional LLM serving treats the inference process as a black box. A request goes in, tokens come out, and the only observable metric is end-to-end response time. With llm-d, every phase of inference exposes detailed metrics:

- **Prefill phase** → `prompt_tokens_total`, `time_to_first_token_seconds`
- **Decode phase** → `generation_tokens_total`, `request_decode_time_seconds`
- **Cache layer** → `prefix_cache_hits_total`, `prefix_cache_cache_hits_total`
- **Scheduler routing** → `num_requests_running` broken out by `llm_tox_role`

This enables you to answer questions that were previously unanswerable without deep instrumentation: Is latency increasing because of prefill (new/unique prompts)? Because of decode (too many concurrent requests)? Because of cache misses (suboptimal routing)? Each root cause has a different solution, and without per-phase metrics you're operating blind.

On IBM Fusion HCI, these Prometheus metrics feed into the OpenShift monitoring stack with no additional configuration. User workload monitoring needs to be enabled at the cluster level by an admin, but once enabled, the kserve metrics surface automatically via the pod monitors that the ODH stack creates.

---

## Key Takeaways

**Prefill-Decode disaggregation delivers measurable benefits.** Once you observe the per-role metrics side by side — prefill pods handling bursty compute load, decode pods performing steady token generation — the architecture's value becomes clear. Scaling them independently based on actual load profiles is demonstrably superior to scaling monolithic serving pods.

**EPP Scheduler plugin weights require tuning.** The balance between `queue-scorer` and `kv-cache-utilization-scorer` depends on your workload characteristics. For workloads with high prompt similarity, weight the cache scorer higher (2.0+). For highly varied one-shot workloads, queue depth becomes the dominant signal (weight 1.0+). Monitor per-pod cache hit distribution as your calibration metric.

**Authentication ordering is non-negotiable.** The ODH Model Controller creates AuthPolicies automatically when Kuadrant is running — but only if Kuadrant was running before the `LLMInferenceService` was deployed. If you get the order wrong, you need to restart the controllers and redeploy. Follow the prerequisite sequence in the docs exactly.

**IBM Fusion HCI provides infrastructure reliability.** Pre-validated GPU node profiles, high-throughput storage for model weights, and native OpenShift integration eliminate infrastructure debugging. You can focus on tuning inference parameters rather than troubleshooting cluster issues. For production deployments, this infrastructure predictability significantly reduces operational overhead.

---

## What's Next

In future posts I'll cover:

- **RateLimitPolicy** with Limitador for per-token and per-request rate limiting tiers
- **DNSPolicy** for custom domain routing on Fusion
- **GenAI Playground** with MCP server tool integration
- **Multi-model deployments** sharing GPU node pools with namespace resource quotas

---

## Resources

- Red Hat OpenShift AI 3.3 — Deploying Models with Distributed Inference: [docs.redhat.com](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/deploying_models#deploying-models-using-distributed-inference_rhoai-user)
- Red Hat Blog — LLM-D Observability: [redhat.com/en/blog](https://www.redhat.com/en/blog/tokens-caches-how-llm-d-improves-llm-observability-red-hat-openshift-ai-3.0)
- Red Hat Connectivity Link Documentation: [docs.redhat.com](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.2/html-single/introduction_to_connectivity_link/index)
- llm-d Project: [llm-d.ai](https://llm-d.ai)
- IBM Fusion HCI Documentation: [ibm.com/docs/fusion](https://www.ibm.com/docs/fusion)
- GitHub — Configuration files: [github.com/nirjhar17/openshift-ai-3-deployment](https://github.com/nirjhar17/openshift-ai-3-deployment)

---
