#!/usr/bin/env bash
# Cross-tool round-trip (spec 002 §3, the acceptance contract): a certificate
# emitted by `tenant-emit build-certificate` with every binding applied
# (corpus attestation, SBOM + audit, agentic posture) MUST verify clean under
# the separately-vended `tenant-tail verify-certificate`, and tampering any
# bound input MUST fail verification (exit 1) for that input's own reason.
#
# A tenant certificate is unsealed by design (spec 001 §3: no platform
# countersign), and tenant-tail >= 0.4.0 rejects unsealed certificates unless
# `--allow-unsealed` is passed (spec 198 FR-014), so every verify passes it.
# Each tamper case asserts both exit 1 and the expected error text, so a
# failure for an unrelated reason (e.g. the seal gate) cannot pass as a
# detected tamper.
#
# Usage: scripts/roundtrip.sh <tenant-emit-bin> <tenant-tail-bin> [scratch-dir]
# Requires OAP_SIGNING_KEY (any valid 32-byte base64 seed).
set -euo pipefail

EMIT="${1:?usage: roundtrip.sh <tenant-emit-bin> <tenant-tail-bin> [scratch-dir]}"
TT="${2:?usage: roundtrip.sh <tenant-emit-bin> <tenant-tail-bin> [scratch-dir]}"
SCRATCH="${3:-$(mktemp -d)}"
: "${OAP_SIGNING_KEY:?OAP_SIGNING_KEY must be set to an operator seed}"

FIXTURES="$(cd "$(dirname "$0")/.." && pwd)/crates/tenant-emit-cli/tests/fixtures/roundtrip"

# Lay out a fresh produced app + run dir and emit a fully bound certificate.
emit_fresh() {
  rm -rf "$SCRATCH"
  mkdir -p "$SCRATCH"
  cp -R "$FIXTURES/app" "$SCRATCH/app"
  cp "$FIXTURES/corpus-attestation.json" "$SCRATCH/attestation.json"
  RUN="$SCRATCH/app/.factory/runs/run-ci-001"
  CERT="$RUN/governance-certificate.json"
  mkdir -p "$RUN/tenant-codegen" "$RUN/s5-ui-specification"
  printf 'fn main(){}\n' > "$RUN/tenant-codegen/app.rs"
  cp "$FIXTURES/build-spec.yaml" "$RUN/s5-ui-specification/build-spec.yaml"
  "$EMIT" build-certificate "$RUN" \
    --tenant-mode \
    --signer-subject ci@tenant --signer-identity-provider github-actions \
    --stage-ids auto --require-operator-key \
    --corpus-attestation "$SCRATCH/attestation.json" --require-corpus-binding \
    --sbom-dir "$SCRATCH/app" --require-sbom-binding
}

verify() {
  "$TT" verify-certificate "$CERT" \
    --artifact-dir "$RUN" \
    --allow-unsealed \
    --corpus-attestation "$SCRATCH/attestation.json" \
    --sbom-dir "$SCRATCH/app"
}

echo "== emit a fully bound certificate, verify clean (must exit 0) =="
emit_fresh
out="$(verify 2>&1)" || { echo "$out"; echo "FAIL: clean certificate did not verify"; exit 1; }
echo "$out"
for want in "corpus binding VERIFIED" "sbom artifact binding VERIFIED" "agentic posture: DECLARED"; do
  grep -qF "$want" <<<"$out" || { echo "FAIL: clean verify did not report: $want"; exit 1; }
done

# tamper <name> <expected error substring> <mutation...>
tamper() {
  local name="$1" want="$2"
  shift 2
  emit_fresh >/dev/null 2>&1
  "$@"
  echo "== tamper: $name (must exit 1 with: $want) =="
  local out
  if out="$(verify 2>&1)"; then
    echo "$out"
    echo "FAIL: the verifier accepted a tampered $name"
    exit 1
  fi
  grep -qF "$want" <<<"$out" || {
    echo "$out"
    echo "FAIL: tampered $name was rejected, but not for the expected reason"
    exit 1
  }
}

tamper "stage artifact" "artifact hash mismatch: tenant-codegen/app.rs" \
  sh -c 'printf "tampered\n" > "$0"' "$SCRATCH/app/.factory/runs/run-ci-001/tenant-codegen/app.rs"
tamper "corpus attestation" "corpus binding MISMATCH" \
  sed -i.bak 's/registry-xyz/registry-tampered/' "$SCRATCH/attestation.json"
tamper "CycloneDX BOM" "sbom binding MISMATCH" \
  sed -i.bak 's/1\.19\.0/1.19.1/' "$SCRATCH/app/.factory/sbom.cdx.json"
tamper "audit artifact" "sbom binding MISMATCH" \
  sh -c 'printf "{}\n" > "$0"' "$SCRATCH/app/.factory/audit.json"
tamper "certificate posture" "certificate hash mismatch" \
  sed -i.bak 's/"posture": "declared"/"posture": "governed"/' "$SCRATCH/app/.factory/runs/run-ci-001/governance-certificate.json"

echo "round-trip OK: fully bound certificate verified clean; every tamper was rejected for its own reason"
