# Source this to set up KUBECONFIG from KUBECONFIG_B64 env var.
# Usage: source ${path.module}/files/kubeconfig-env.sh
KUBECONFIG_FILE=$(mktemp)
printf '%s' "$KUBECONFIG_B64" | base64 --decode > "$KUBECONFIG_FILE"
trap 'rm -f "$KUBECONFIG_FILE"' EXIT
export KUBECONFIG="$KUBECONFIG_FILE"
