# Quick Start: Deploying Meta Llama Models

This guide provides a streamlined workflow for deploying Meta Llama models that require HuggingFace authentication.

## Prerequisites Checklist

- [ ] HuggingFace account created
- [ ] Llama model license accepted on HuggingFace
- [ ] HuggingFace token generated (with Read permissions)
- [ ] OpenShift cluster with GPU nodes available
- [ ] Red Hat OpenShift AI and GitOps operators installed
- [ ] Repository forked and cloned

## Step-by-Step Deployment

### 1. Accept Model License

Visit the model page and accept the license:
- **Llama 3 8B**: https://huggingface.co/meta-llama/Meta-Llama-3-8B
- **Llama 3 70B**: https://huggingface.co/meta-llama/Meta-Llama-3-70B
- **Llama 3.1 405B**: https://huggingface.co/meta-llama/Meta-Llama-3.1-405B

### 2. Create HuggingFace Token

1. Go to https://huggingface.co/settings/tokens
2. Click "New token"
3. Name: `openshift-model-serving`
4. Type: Read
5. Copy the token (starts with `hf_`)

### 3. Create Secret in OpenShift

```bash
# Using the helper script (recommended)
./fusion-model-serving/scripts/create-hf-secret.sh model-serving hf_xxxxxxxxxxxxxxxxxxxxx

# Or manually
oc create namespace model-serving
oc create secret generic hf-token-secret \
  --from-literal=token="hf_xxxxxxxxxxxxxxxxxxxxx" \
  -n model-serving
```

### 4. Enable HuggingFace Authentication

Edit `fusion-model-serving/gitops/models/kserve-model-serving.yaml`:

```yaml
# Uncomment these lines (around line 36-41):
- name: HF_TOKEN
  valueFrom:
    secretKeyRef:
      name: hf-token-secret
      key: token
```

### 5. Deploy Llama Model

```bash
# Update repoURL in llama-model-serving-application.yaml to your fork
# Then apply:
oc apply -f fusion-model-serving/gitops/llama-model-serving-application.yaml
```

### 6. Monitor Deployment

```bash
# Check Argo CD application
oc get application llama-3-70b-model -n openshift-gitops

# Watch InferenceService
oc get inferenceservice -n llama-model-serving -w

# Check pod logs
oc logs -f $(oc get pods -n llama-model-serving -l serving.kserve.io/inferenceservice=meta-llama-3-70b -o name) -n llama-model-serving
```

### 7. Expose Model (Optional)

```bash
# Expose the model externally
./fusion-model-serving/scripts/expose-model.sh llama-model-serving

# Test the endpoint
curl -k https://meta-llama-3-70b-external-llama-model-serving.apps.your-cluster.com/v1/models \
  -H "Authorization: Bearer EMPTY"
```

## Resource Requirements by Model

| Model | Recommended GPUs | Memory | Deployment Time |
|-------|------------------|--------|-----------------|
| Llama 3 8B | 1 x A100 (40GB) | 16Gi | ~5-10 min |
| Llama 3 70B | 4 x A100 (40GB) | 128Gi | ~15-20 min |
| Llama 3.1 405B | 8 x A100 (80GB) | 512Gi | ~30-45 min |

## Troubleshooting

### Authentication Errors

**Error**: `401 Unauthorized` or `403 Forbidden`

**Solutions**:
1. Verify token is correct: `oc get secret hf-token-secret -n model-serving -o jsonpath='{.data.token}' | base64 -d`
2. Check license acceptance on HuggingFace
3. Ensure token has Read permissions
4. Regenerate token if needed

### Resource Issues

**Error**: Pod stuck in `Pending` state

**Solutions**:
1. Check GPU availability: `oc describe nodes | grep -i gpu`
2. Verify resource requests match cluster capacity
3. Check node selectors and tolerations
4. Review pod events: `oc describe pod <pod-name> -n llama-model-serving`

### Model Download Issues

**Error**: Model download fails or times out

**Solutions**:
1. Check network connectivity from pods
2. Verify HuggingFace service is accessible
3. Increase timeout values if needed
4. Check pod logs for specific errors

### Memory Issues

**Error**: `OOMKilled` or out of memory errors

**Solutions**:
1. Increase memory limits in Application manifest
2. Reduce `--gpu-memory-utilization` parameter (default: 0.75)
3. Use tensor parallelism for large models
4. Consider using quantized model versions

## Configuration Examples

### Llama 3 8B (Single GPU)

```yaml
- op: replace
  path: /spec/predictor/containers/0/env/0/value
  value: meta-llama/Meta-Llama-3-8B
- op: replace
  path: /spec/predictor/containers/0/resources/limits/nvidia.com~1gpu
  value: "1"
- op: replace
  path: /spec/predictor/containers/0/resources/limits/memory
  value: "16Gi"
```

### Llama 3 70B (Multi-GPU)

```yaml
- op: replace
  path: /spec/predictor/containers/0/env/0/value
  value: meta-llama/Meta-Llama-3-70B
- op: replace
  path: /spec/predictor/containers/0/resources/limits/nvidia.com~1gpu
  value: "4"
- op: replace
  path: /spec/predictor/containers/0/resources/limits/memory
  value: "128Gi"
```

### Llama 3.1 405B (Enterprise Scale)

```yaml
- op: replace
  path: /spec/predictor/containers/0/env/0/value
  value: meta-llama/Meta-Llama-3.1-405B
- op: replace
  path: /spec/predictor/containers/0/resources/limits/nvidia.com~1gpu
  value: "8"
- op: replace
  path: /spec/predictor/containers/0/resources/limits/memory
  value: "512Gi"
```

## Testing Your Deployment

### List Available Models

```bash
curl -k https://your-model-endpoint/v1/models \
  -H "Authorization: Bearer EMPTY"
```

### Chat Completion Request

```bash
curl -k -X POST https://your-model-endpoint/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{
    "model": "meta-llama/Meta-Llama-3-70B",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain quantum computing in simple terms."}
    ],
    "max_tokens": 500,
    "temperature": 0.7
  }'
```

## Security Best Practices

1. **Never commit tokens to Git**
   - Use the secret creation script
   - Keep tokens in secure secret management systems

2. **Rotate tokens regularly**
   - Generate new tokens every 90 days
   - Update secrets immediately after rotation

3. **Use minimal permissions**
   - Token should have Read access only
   - Create separate tokens per environment

4. **Monitor token usage**
   - Review HuggingFace token activity
   - Set up alerts for unusual access patterns

## Next Steps

- Review the [main README](README.md) for detailed architecture information
- Explore [model customization options](README.md#customizing-the-model-serving-application)
- Set up [monitoring and observability](README.md#monitoring-deployment)
- Configure [external access](README.md#exposing-the-model-for-external-access)

## Support

For issues or questions:
- Check the [troubleshooting section](#troubleshooting)
- Review OpenShift AI documentation
- Open an issue in the repository