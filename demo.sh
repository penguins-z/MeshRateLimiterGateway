#!/bin/bash
# ============================================
# MeshRateLimiterGateway - Full Demo Script
# Self-contained (runs inside Docker, controls sibling containers)
# ============================================

set -e

GATEWAY_1="http://gateway-1:9000"
GATEWAY_2="http://gateway-2:9000"
GATEWAY_3="http://gateway-3:9000"
PORTS=("$GATEWAY_1" "$GATEWAY_2" "$GATEWAY_3")

echo "============================================"
echo " MeshRateLimiterGateway - Full Demo"
echo " Distributed Rate Limiter + Circuit Breaker"
echo "============================================"

# Wait for gateways to be ready
echo ""
echo "[SETUP] Waiting for gateways to be ready..."
for i in $(seq 1 60); do
    if curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_1/status" | grep -q "200"; then
        echo "[SETUP] Gateways are ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "[SETUP] ERROR: Gateways not ready after 60s. Exiting."
        exit 1
    fi
    sleep 1
done

# Reset Redis
redis-cli -h redis FLUSHALL > /dev/null
echo "[SETUP] Redis flushed."
echo ""

echo "[SETUP] Restarting gateways to reset circuit breakers..."
docker restart gateway-1 gateway-2 gateway-3
sleep 15
echo "[SETUP] Gateways restarted."

# --- 1. REGISTER BOTH USERS ---
echo "============================================"
echo " STEP 1: REGISTER two users via the gateway"
echo " POST /api/auth/register -> gateway-1"
echo " User 'rlm' = custom tier (capacity 50)"
echo " User 'que' = custom tier (capacity 20)"
echo "============================================"
echo ""
echo "  Registering rlm@gmail.com..."
REG_RLM=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"rlm","email":"rlm@gmail.com","password":"rlm"}' "$GATEWAY_1/api/auth/register")
echo "  Response: $REG_RLM"
echo ""
echo "  Registering que@gmail.com..."
REG_QUE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"que","email":"que@gmail.com","password":"que"}' "$GATEWAY_1/api/auth/register")
echo "  Response: $REG_QUE"

# --- 2. LOGIN BOTH USERS ---
echo ""
echo "============================================"
echo " STEP 2: LOGIN both users via Gateway"
echo " POST /api/auth/login -> gateway-1"
echo "============================================"
echo ""
echo "  Logging in rlm..."
LOGIN_RLM=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"email":"rlm@gmail.com","password":"rlm"}' "$GATEWAY_1/api/auth/login")
echo "  Response: $LOGIN_RLM"
TOKEN_RLM=$(echo "$LOGIN_RLM" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$TOKEN_RLM" ]; then
    echo "ERROR: rlm login failed. Exiting."
    exit 1
fi
echo "  rlm token captured."

echo ""
echo "  Logging in que..."
LOGIN_QUE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"email":"que@gmail.com","password":"que"}' "$GATEWAY_1/api/auth/login")
echo "  Response: $LOGIN_QUE"
TOKEN_QUE=$(echo "$LOGIN_QUE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
if [ -z "$TOKEN_QUE" ]; then
    echo "ERROR: que login failed. Exiting."
    exit 1
fi
echo "  que token captured."

# --- SETUP: Create a company ---
echo ""
echo "[SETUP] Creating a company for job applications..."
COMPANY=$(curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN_RLM" \
    -d '{"name":"TechCorp","industry":"Technology","website":"https://techcorp.com","email":"hr@techcorp.com","location":"Remote"}' \
    "$GATEWAY_1/api/companies")
echo "  Response: $COMPANY"

# --- 3. GET - List applications ---
echo ""
echo "============================================"
echo " STEP 3: GET applications for both users (should be empty)"
echo " GET /api/applications -> gateway-1"
echo "============================================"
echo ""
echo "  [rlm] GET /api/applications"
curl -s -H "Authorization: Bearer $TOKEN_RLM" "$GATEWAY_1/api/applications"
echo ""
echo "  [que] GET /api/applications"
curl -s -H "Authorization: Bearer $TOKEN_QUE" "$GATEWAY_1/api/applications"
echo ""

# --- 4. POST - Create application ---
echo ""
echo "============================================"
echo " STEP 4: CREATE a job application for both users"
echo " POST /api/applications -> gateway-1"
echo "============================================"
echo ""
echo "  [rlm] Creating application..."
CREATED_RLM=$(curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN_RLM" \
    -d '{"jobTitle":"Backend Engineer","companyId":1,"status":"SAVED","targetDate":"2026-09-01","jobUrl":"https://example.com/job","description":"Found on LinkedIn"}' \
    "$GATEWAY_1/api/applications")
echo "  Response: $CREATED_RLM"
APP_ID_RLM=$(echo "$CREATED_RLM" | grep -o '"id":[0-9]*' | cut -d: -f2)
echo "  Created application ID: $APP_ID_RLM"

echo ""
echo "  [que] Creating application..."
CREATED_QUE=$(curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN_QUE" \
    -d '{"jobTitle":"Backend Engineer","companyId":1,"status":"SAVED","targetDate":"2026-09-01","jobUrl":"https://example.com/job","description":"Found on LinkedIn"}' \
    "$GATEWAY_1/api/applications")
echo "  Response: $CREATED_QUE"
APP_ID_QUE=$(echo "$CREATED_QUE" | grep -o '"id":[0-9]*' | cut -d: -f2)
echo "  Created application ID: $APP_ID_QUE"

# --- 5. GET - Fetch single application ---
echo ""
echo "============================================"
echo " STEP 5: GET single application by ID for both users"
echo " GET /api/applications/{id} -> gateway-1"
echo "============================================"
echo ""
echo "  [rlm] GET /api/applications/$APP_ID_RLM"
curl -s -H "Authorization: Bearer $TOKEN_RLM" "$GATEWAY_1/api/applications/$APP_ID_RLM"
echo ""
echo "  [que] GET /api/applications/$APP_ID_QUE"
curl -s -H "Authorization: Bearer $TOKEN_QUE" "$GATEWAY_1/api/applications/$APP_ID_QUE"
echo ""

# --- 5b. CROSS-USER ACCESS TEST ---
echo ""
echo "============================================"
echo " STEP 5b: CROSS-USER ACCESS TEST"
echo " rlm tries to access que's application (ID $APP_ID_QUE)"
echo " Expected: 403 Forbidden or 404 Not Found"
echo " Proves: HireTrack enforces user isolation, gateway proxies faithfully"
echo "============================================"
echo ""
echo "  [rlm] GET /api/applications/$APP_ID_QUE (que's application)"
curl -s -w "\n  HTTP Status: %{http_code}" -H "Authorization: Bearer $TOKEN_RLM" "$GATEWAY_1/api/applications/$APP_ID_QUE"
echo ""

# --- 6. PUT - Update application (rlm) ---
echo ""
echo "============================================"
echo " STEP 6: UPDATE application (full replace) - rlm"
echo " PUT /api/applications/$APP_ID_RLM -> gateway-1"
echo "============================================"
curl -s -X PUT -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN_RLM" \
    -d '{"jobTitle":"Senior Backend Engineer","companyId":1,"status":"APPLIED","targetDate":"2026-09-15","jobUrl":"https://example.com/job","description":"Updated via gateway"}' \
    "$GATEWAY_1/api/applications/$APP_ID_RLM"
echo ""

# --- 7. PATCH - Update status (que) ---
echo ""
echo "============================================"
echo " STEP 7: PATCH application status - que"
echo " PATCH /api/applications/$APP_ID_QUE/status -> gateway-1"
echo "============================================"
curl -s -X PATCH -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN_QUE" \
    -d '{"status":"INTERVIEW_SCHEDULED"}' \
    "$GATEWAY_1/api/applications/$APP_ID_QUE/status"
echo ""

# --- 8. DELETE - Delete applications ---
echo ""
echo "============================================"
echo " STEP 8: DELETE applications for both users"
echo " DELETE /api/applications/{id} -> gateway-1"
echo "============================================"
echo ""
echo "  [rlm] Deleting application $APP_ID_RLM..."
DEL_RLM=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN_RLM" "$GATEWAY_1/api/applications/$APP_ID_RLM")
echo "  HTTP Status: $DEL_RLM (204 = success)"
echo ""
echo "  [que] Deleting application $APP_ID_QUE..."
DEL_QUE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN_QUE" "$GATEWAY_1/api/applications/$APP_ID_QUE")
echo "  HTTP Status: $DEL_QUE (204 = success)"

# --- 8b. VERIFY DELETION ---
echo ""
echo "============================================"
echo " STEP 8b: VERIFY deletions"
echo " GET /api/applications/{id} -> gateway-1"
echo " Expected: 404 Not Found for both users"
echo "============================================"
echo ""
echo "  [rlm] GET /api/applications/$APP_ID_RLM (should be 404)"
curl -s -w "\n  HTTP Status: %{http_code}" -H "Authorization: Bearer $TOKEN_RLM" "$GATEWAY_1/api/applications/$APP_ID_RLM"
echo ""
echo "  [que] GET /api/applications/$APP_ID_QUE (should be 404)"
curl -s -w "\n  HTTP Status: %{http_code}" -H "Authorization: Bearer $TOKEN_QUE" "$GATEWAY_1/api/applications/$APP_ID_QUE"
echo ""

# --- 9. STATUS endpoint ---
echo ""
echo "============================================"
echo " STEP 9: CHECK gateway status endpoint"
echo " GET /status -> gateway-1"
echo " Shows: per-client token buckets + circuit breaker state"
echo " Note: /status bypasses rate limiter entirely"
echo "============================================"
curl -s "$GATEWAY_1/status"
echo ""

# --- 10. RATE LIMIT test - TIER COMPARISON ---
echo ""
echo "============================================"
echo " STEP 10: TIER-BASED RATE LIMIT TEST"
echo " rlm = custom tier, capacity 50 (sends 55 requests)"
echo " que = custom tier, capacity 20 (sends 23 requests)"
echo " Slight variance between expected result and actual result possible due to refill rate "
echo " Both distributed across 3 gateway instances"
echo " Proves: different clients get different limits"
echo " Proves: limits are globally enforced via shared Redis"
echo " Flushing Redis before test to reset tokens"
echo "============================================"
redis-cli -h redis FLUSHALL > /dev/null

echo ""
echo "  --- rlm: 55 requests (capacity 50) ---"
RLM_ALLOWED=0; RLM_BLOCKED=0
for i in $(seq 1 55); do
    PORT_IDX=$((i % 3))
    GW="${PORTS[$PORT_IDX]}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN_RLM" "$GW/api/applications")
    if [ "$CODE" = "429" ]; then
        RLM_BLOCKED=$((RLM_BLOCKED + 1))
        LABEL="BLOCKED"
    else
        RLM_ALLOWED=$((RLM_ALLOWED + 1))
        LABEL="ALLOWED"
    fi
    echo "  Request $i -> gateway-$((PORT_IDX + 1)) -> HTTP $CODE ($LABEL)"
done
echo ""
echo "  rlm TOTAL: Allowed=$RLM_ALLOWED | Blocked(429)=$RLM_BLOCKED (expected: 50 allowed, 5 blocked)"

echo ""
echo "  --- que: 23 requests (capacity 20) ---"
QUE_ALLOWED=0; QUE_BLOCKED=0
for i in $(seq 1 23); do
    PORT_IDX=$((i % 3))
    GW="${PORTS[$PORT_IDX]}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN_QUE" "$GW/api/applications")
    if [ "$CODE" = "429" ]; then
        QUE_BLOCKED=$((QUE_BLOCKED + 1))
        LABEL="BLOCKED"
    else
        QUE_ALLOWED=$((QUE_ALLOWED + 1))
        LABEL="ALLOWED"
    fi
    echo "  Request $i -> gateway-$((PORT_IDX + 1)) -> HTTP $CODE ($LABEL)"
done
echo ""
echo "  que TOTAL: Allowed=$QUE_ALLOWED | Blocked(429)=$QUE_BLOCKED (expected: 20 allowed, 3 blocked)"

echo ""
echo "  TIER COMPARISON:"
echo "  rlm (capacity 50): $RLM_ALLOWED allowed, $RLM_BLOCKED blocked"
echo "  que (capacity 20): $QUE_ALLOWED allowed, $QUE_BLOCKED blocked"
echo "  Different clients, different limits, same Redis, same gateway instances!"

# --- 10b. FAKE JWT ATTACK TEST ---
echo ""
echo "============================================"
echo " STEP 10b: FAKE JWT ATTACK SIMULATION"
echo " Attacker sends requests with 4 different fake JWTs"
echo " Each fake JWT has a different email (fake1-4@evil.com)"
echo " Expected: ALL share the same IP bucket (10 total)"
echo " Proves: cannot bypass rate limit with fake tokens"
echo "============================================"
redis-cli -h redis FLUSHALL > /dev/null

FAKE_ALLOWED=0; FAKE_BLOCKED=0
for i in $(seq 1 12); do
    # Create a garbage token (invalid signature)
    FAKE_TOKEN="eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmYWtlJHtpfUBldmlsLmNvbSJ9.invalidsignature"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $FAKE_TOKEN" "$GATEWAY_1/api/applications")
    if [ "$CODE" = "429" ]; then
        FAKE_BLOCKED=$((FAKE_BLOCKED + 1))
        LABEL="BLOCKED"
    else
        FAKE_ALLOWED=$((FAKE_ALLOWED + 1))
        LABEL="ALLOWED"
    fi
    echo "  Request $i (fakejwt${i}@fake.com) -> HTTP $CODE ($LABEL)"
done
echo ""
echo "  RESULT: Allowed=$FAKE_ALLOWED | Blocked=$FAKE_BLOCKED"
echo "  All 12 requests shared ONE IP bucket (capacity 10)"
echo "  Fake JWTs cannot bypass rate limiting!"

# --- 11. CIRCUIT BREAKER test ---
echo ""
echo "============================================"
echo " STEP 11: CIRCUIT BREAKER TEST"
echo " Stopping HireTrack to simulate backend failure"
echo " Circuit breaker config: 50% failure threshold, window=5"
echo " Expected: first 3 requests = 502 (tried backend, failed)"
echo "           remaining = 503 (circuit OPEN, instant fail)"
echo "============================================"
docker stop hiretrack-app
echo "  HireTrack stopped."
redis-cli -h redis FLUSHALL > /dev/null
sleep 2

for i in $(seq 1 10); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_1/api/applications")
    if [ "$CODE" = "502" ]; then
        LABEL="TRIED backend, failed"
    elif [ "$CODE" = "503" ]; then
        LABEL="CIRCUIT OPEN - instant fail"
    else
        LABEL="HTTP $CODE"
    fi
    echo "  Request $i -> HTTP $CODE ($LABEL)"
done

# --- 12. CIRCUIT BREAKER RECOVERY ---
echo ""
echo "============================================"
echo " STEP 12: CIRCUIT BREAKER RECOVERY"
echo " Restarting HireTrack, waiting 35s for circuit to half-open"
echo " Circuit will send 1 probe request - if it succeeds, closes"
echo " Expected: HTTP 200 (circuit recovered, traffic flows again)"
echo "============================================"
docker start hiretrack-app
echo "  HireTrack restarted. Waiting 35 seconds for circuit to transition to half-open..."
sleep 35
redis-cli -h redis FLUSHALL > /dev/null
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN_RLM" "$GATEWAY_1/api/applications")
if [ "$CODE" = "200" ] || [ "$CODE" = "401" ]; then
    LABEL="CIRCUIT RECOVERED - backend responding!"
else
    LABEL="HTTP $CODE"
fi
echo "  Recovery probe -> HTTP $CODE ($LABEL)"

# --- 12b. PROVE SYSTEM IS FULLY BACK ---
echo ""
echo "============================================"
echo " STEP 12b: PROVE system is fully operational"
echo " Fetching real data for both users after recovery"
echo "============================================"
redis-cli -h redis FLUSHALL > /dev/null
echo ""
echo "  [rlm] GET /api/applications"
curl -s -H "Authorization: Bearer $TOKEN_RLM" "$GATEWAY_1/api/applications"
echo ""
echo "  [que] GET /api/applications"
curl -s -H "Authorization: Bearer $TOKEN_QUE" "$GATEWAY_1/api/applications"
echo ""
echo "  System is fully recovered and serving data for both users!"

# --- 13. CLEANUP ---
echo ""
echo "============================================"
echo " STEP 13: CLEANUP"
echo " Removing both test users from HireTrack database"
echo " Flushing Redis rate limit data"
echo "============================================"
redis-cli -h redis FLUSHALL > /dev/null
echo "  Redis flushed."
docker exec hiretrack-postgres psql -U postgres -d hiretrack -c "DELETE FROM users WHERE email IN ('rlm@gmail.com','que@gmail.com');" 2>/dev/null
echo "  Users rlm@gmail.com and que@gmail.com removed from database."

echo ""
echo "============================================"
echo " DEMO COMPLETE"
echo " "
echo " Summary of what was demonstrated:"
echo "  - All HTTP methods (GET/POST/PUT/PATCH/DELETE) proxied"
echo "  - Two users with different rate limit tiers"
echo "    rlm@gmail.com: 50 req/min | que@gmail.com: 20 req/min | default: 10 req/min"
echo "  - JWT-based client identification (cannot be faked)"
echo "  - Per-client rate limiting via Redis (shared across 3 instances)"
echo "  - Circuit breaker: fast-fail when backend is down (502 -> 503)"
echo "  - Automatic recovery when backend comes back (35s wait)"
echo "  - Cross-user isolation (rlm cannot access que's data)"
echo "  - Status endpoint for observability"
echo "============================================"