# shellcheck shell=bash
# Shared helpers for the host-side monitoring scripts (list-batches.sh,
# watch-batch.sh, monitor-all-batches.sh, saga-health-check.sh).
#
# The orchestrator rejects unauthenticated calls (Spring Security with JWT
# resource server). Each monitoring script sources this file to obtain a
# short-lived service-account token via Keycloak's client-credentials grant
# and reuse it across curl calls. The IT mints tokens the same way.
#
# All defaults can be overridden via env vars (e.g. for a remote stack).

# Avoid double-sourcing.
if [ -n "${__MONITOR_COMMON_SOURCED:-}" ]; then
    return 0
fi
__MONITOR_COMMON_SOURCED=1

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://localhost:8095}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-transcript}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-transcript-e2e}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-e2e-dev-secret}"

# Mint a client-credentials JWT from Keycloak. Caches it in JWT and tracks
# expiry in JWT_EXP (epoch seconds). Refreshes automatically when the token
# is missing or within 30s of expiry. Exits with a clear message on failure.
mint_jwt() {
    local now
    now=$(date +%s)
    # Refresh if missing or expiring within 30s (covers clock skew and slow curls).
    if [ -n "${JWT:-}" ] && [ -n "${JWT_EXP:-}" ] && [ "$JWT_EXP" -gt $((now + 30)) ]; then
        return 0
    fi

    local token_url="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token"
    local response
    response=$(curl -s -X POST "$token_url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=client_credentials" \
        --data-urlencode "client_id=${KEYCLOAK_CLIENT_ID}" \
        --data-urlencode "client_secret=${KEYCLOAK_CLIENT_SECRET}")

    local token expires_in
    token=$(echo "$response" | jq -r '.access_token // empty')
    expires_in=$(echo "$response" | jq -r '.expires_in // 60')
    if [ -z "$token" ]; then
        echo "Error: failed to mint JWT from Keycloak at $token_url" >&2
        echo "Response: $response" >&2
        exit 1
    fi
    JWT="$token"
    JWT_EXP=$((now + expires_in))
    export JWT JWT_EXP
}

# Curl wrapper that automatically attaches the bearer token (and refreshes it
# if expired). Use this in any script that calls the orchestrator from the host.
auth_curl() {
    mint_jwt
    curl -s -H "Authorization: Bearer $JWT" "$@"
}
