#!/bin/bash
set -euo pipefail

# PreToolUse hook for Write/Edit.
# Reads JSON from stdin, parses file_path, blocks modification of sensitive files.
# Exit 0 = allow, Exit 1 = block.

INPUT=$(cat /dev/stdin)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('file_path',''))" 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

BASENAME=$(basename "$FILE_PATH")

BLOCKED=""

# Environment files
if [[ "$BASENAME" == ".env" ]] || [[ "$BASENAME" == .env.* ]]; then
    BLOCKED="Environment file"
fi

# SSH keys
case "$BASENAME" in
    id_rsa*|id_ed25519*|id_ecdsa*|authorized_keys|known_hosts)
        BLOCKED="SSH key/config file"
        ;;
esac

# Certificates
case "$BASENAME" in
    *.pem|*.key|*.crt|*.p12|*.pfx)
        BLOCKED="Certificate/key file"
        ;;
esac

# Credentials
if echo "$BASENAME" | grep -qiE '(credentials|secret|password|token|keystore)'; then
    BLOCKED="Credentials file"
fi

# Cloud configs
if echo "$BASENAME" | grep -qE '^(gcloud-.*\.json|service-account.*\.json|aws-credentials)$'; then
    BLOCKED="Cloud credentials file"
fi

# Lock files
case "$BASENAME" in
    package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|poetry.lock)
        BLOCKED="Lock file (auto-generated)"
        ;;
esac

# Sensitive directories
if echo "$FILE_PATH" | grep -qE '/(\.ssh|\.gnupg|\.aws|\.gcloud)/'; then
    BLOCKED="File in sensitive directory"
fi

if [[ -n "$BLOCKED" ]]; then
    echo "BLOCKED: $BLOCKED" >&2
    echo "File: $FILE_PATH" >&2
    exit 1
fi

exit 0
