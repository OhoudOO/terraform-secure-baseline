#!/usr/bin/env bash
# Runs the same checks as CI, locally and with Docker only: fmt, validate, Trivy, Checkov.
set -euo pipefail
cd "$(dirname "$0")/.."
TF=(docker run --rm -v "$PWD:/w" -v tfplugins:/root/.terraform.d/plugin-cache -e TF_PLUGIN_CACHE_DIR=/root/.terraform.d/plugin-cache)
"${TF[@]}" -w /w hashicorp/terraform:latest fmt -recursive -check -diff
for dir in bootstrap envs/dev envs/staging envs/prod; do
  "${TF[@]}" -w "/w/$dir" hashicorp/terraform:latest init -backend=false -input=false >/dev/null
  "${TF[@]}" -w "/w/$dir" hashicorp/terraform:latest validate -no-color
done
docker run --rm -v "$PWD:/src:ro" aquasec/trivy config /src --quiet --skip-dirs '**/.terraform' --severity HIGH,CRITICAL --exit-code 1
docker run --rm -v "$PWD:/src:ro" bridgecrew/checkov:latest -d /src --framework terraform --quiet --compact --skip-path .terraform
echo "All checks passed."
