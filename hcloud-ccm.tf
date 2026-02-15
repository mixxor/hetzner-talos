# CCM is installed via externalCloudProvider manifests in controlplane.tf.
# The hcloud secret (token + network name) is baked into the Talos machine
# config as an inlineManifest, so it's available immediately at bootstrap.
#
# NOTE: If you rotate your Hetzner API token, you must either:
#   1. Run: tofu apply (re-applies machine config with new token)
#   2. Or manually: kubectl -n kube-system create secret generic hcloud \
#        --from-literal=token="NEW_TOKEN" --from-literal=network="NETWORK" \
#        --dry-run=client -o yaml | kubectl apply -f -
#      Then restart the CCM: kubectl -n kube-system rollout restart deployment/hcloud-cloud-controller-manager
