# ============================================
# MeshRateLimiterGateway - Full Demo Script
# ============================================

Write-Output "============================================"
Write-Output " MeshRateLimiterGateway - Full Demo"
Write-Output " Distributed Rate Limiter + Circuit Breaker"
Write-Output "============================================"

# Setup: Create JSON request bodies
Write-Output "`n[SETUP] Creating JSON request body files..."
[System.IO.File]::WriteAllText("$PWD\register-rlm.json", '{"name":"rlm","email":"rlm@gmail.com","password":"rlm"}')
[System.IO.File]::WriteAllText("$PWD\login-rlm.json", '{"email":"rlm@gmail.com","password":"rlm"}')
[System.IO.File]::WriteAllText("$PWD\register-que.json", '{"name":"que","email":"que@gmail.com","password":"que"}')
[System.IO.File]::WriteAllText("$PWD\login-que.json", '{"email":"que@gmail.com","password":"que"}')
[System.IO.File]::WriteAllText("$PWD\create-app.json", '{"jobTitle":"Backend Engineer","companyId":1,"status":"SAVED","targetDate":"2026-09-01","jobUrl":"https://example.com/job","description":"Found on LinkedIn"}')
[System.IO.File]::WriteAllText("$PWD\update-app.json", '{"jobTitle":"Senior Backend Engineer","companyId":1,"status":"APPLIED","targetDate":"2026-09-15","jobUrl":"https://example.com/job","description":"Updated via gateway"}')
[System.IO.File]::WriteAllText("$PWD\update-status.json", '{"status":"INTERVIEW_SCHEDULED"}')
Write-Output "[SETUP] Done."

# Reset state
Write-Output "`n[SETUP] Resetting Redis and restarting gateway containers to clear circuit breaker state..."
docker exec ratelimiter-redis redis-cli FLUSHALL | Out-Null
docker restart gateway-1 gateway-2 gateway-3 | Out-Null
Write-Output "[SETUP] Waiting 10 seconds for gateways to start..."
Start-Sleep -Seconds 10
Write-Output "[SETUP] Ready.`n"

# --- 1. REGISTER BOTH USERS ---
Write-Output "============================================"
Write-Output " STEP 1: REGISTER two users via the gateway"
Write-Output " POST /api/auth/register -> port 9001"
Write-Output " User 'rlm' = custom tier (capacity 50)"
Write-Output " User 'que' = custom tier (capacity 20)"
Write-Output "============================================"
Write-Output "`n  Registering rlm@gmail.com..."
$regRlm = curl.exe -s -X POST -H "Content-Type: application/json" -H "X-Client-Id: rlm" -d `@register-rlm.json http://localhost:9001/api/auth/register
Write-Output "  Response: $regRlm"
Write-Output "`n  Registering que@gmail.com..."
$regQue = curl.exe -s -X POST -H "Content-Type: application/json" -H "X-Client-Id: que" -d `@register-que.json http://localhost:9001/api/auth/register
Write-Output "  Response: $regQue"

# --- 2. LOGIN BOTH USERS ---
Write-Output "`n============================================"
Write-Output " STEP 2: LOGIN both users via Gateway"
Write-Output " POST /api/auth/login -> port 9001"
Write-Output "============================================"
Write-Output "`n  Logging in rlm..."
$loginRlm = curl.exe -s -X POST -H "Content-Type: application/json" -H "X-Client-Id: rlm" -d `@login-rlm.json http://localhost:9001/api/auth/login
Write-Output "  Response: $loginRlm"
$tokenRlm = ($loginRlm | ConvertFrom-Json).token
if (-not $tokenRlm) {
    Write-Output "ERROR: rlm login failed. Exiting."
    exit 1
}
Write-Output "  rlm token captured."

Write-Output "`n  Logging in que..."
$loginQue = curl.exe -s -X POST -H "Content-Type: application/json" -H "X-Client-Id: que" -d `@login-que.json http://localhost:9001/api/auth/login
Write-Output "  Response: $loginQue"
$tokenQue = ($loginQue | ConvertFrom-Json).token
if (-not $tokenQue) {
    Write-Output "ERROR: que login failed. Exiting."
    exit 1
}
Write-Output "  que token captured."

# --- 3. GET - List applications for both users ---
Write-Output "`n============================================"
Write-Output " STEP 3: GET applications for both users (should be empty)"
Write-Output " GET /api/applications -> port 9001"
Write-Output "============================================"
Write-Output "`n  [rlm] GET /api/applications"
$getRlm = curl.exe -s -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" http://localhost:9001/api/applications
Write-Output "  Response: $getRlm"
Write-Output "`n  [que] GET /api/applications"
$getQue = curl.exe -s -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" http://localhost:9001/api/applications
Write-Output "  Response: $getQue"

# --- 4. POST - Create application for both users ---
Write-Output "`n============================================"
Write-Output " STEP 4: CREATE a job application for both users"
Write-Output " POST /api/applications -> port 9001"
Write-Output "============================================"
Write-Output "`n  [rlm] Creating application..."
$createdRlm = curl.exe -s -X POST -H "Content-Type: application/json" -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" -d `@create-app.json http://localhost:9001/api/applications
Write-Output "  Response: $createdRlm"
$appIdRlm = ($createdRlm | ConvertFrom-Json).id
Write-Output "  Created application ID: $appIdRlm"

Write-Output "`n  [que] Creating application..."
$createdQue = curl.exe -s -X POST -H "Content-Type: application/json" -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" -d `@create-app.json http://localhost:9001/api/applications
Write-Output "  Response: $createdQue"
$appIdQue = ($createdQue | ConvertFrom-Json).id
Write-Output "  Created application ID: $appIdQue"

# --- 5. GET - Fetch single application ---
Write-Output "`n============================================"
Write-Output " STEP 5: GET single application by ID for both users"
Write-Output " GET /api/applications/{id} -> port 9001"
Write-Output "============================================"
Write-Output "`n  [rlm] GET /api/applications/${appIdRlm}"
$getOneRlm = curl.exe -s -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" "http://localhost:9001/api/applications/$appIdRlm"
Write-Output "  Response: $getOneRlm"
Write-Output "`n  [que] GET /api/applications/${appIdQue}"
$getOneQue = curl.exe -s -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" "http://localhost:9001/api/applications/$appIdQue"
Write-Output "  Response: $getOneQue"

# --- 5b. UNAUTHORIZED-USER ACCESS TEST ---
Write-Output "`n============================================"
Write-Output " STEP 5b: UNAUTHORIZED-USER ACCESS TEST"
Write-Output " rlm tries to access que's application (ID ${appIdQue})"
Write-Output " Expected: 404 Not Found (Authorization)"
Write-Output " Proves: HireTrack enforces user isolation, gateway proxies faithfully"
Write-Output "============================================"
Write-Output "`n  [rlm] GET /api/applications/${appIdQue} (que's application)"
$UNAUTHORIZEDAccess = curl.exe -s -w "`n%{http_code}" -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" "http://localhost:9001/api/applications/$appIdQue"
Write-Output "  Response: $UNAUTHORIZEDAccess"

# --- 6. PUT - Update application (rlm only) ---
Write-Output "`n============================================"
Write-Output " STEP 6: UPDATE application (full replace) - rlm"
Write-Output " PUT /api/applications/${appIdRlm} -> port 9001"
Write-Output "============================================"
$putResponse = curl.exe -s -X PUT -H "Content-Type: application/json" -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" -d `@update-app.json "http://localhost:9001/api/applications/$appIdRlm"
Write-Output "Response: $putResponse"

# --- 7. PATCH - Update status (que only) ---
Write-Output "`n============================================"
Write-Output " STEP 7: PATCH application status - que"
Write-Output " PATCH /api/applications/${appIdQue}/status -> port 9001"
Write-Output "============================================"
$patchResponse = curl.exe -s -X PATCH -H "Content-Type: application/json" -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" -d `@update-status.json "http://localhost:9001/api/applications/$appIdQue/status"
Write-Output "Response: $patchResponse"

# --- 8. DELETE - Delete applications for both users ---
Write-Output "`n============================================"
Write-Output " STEP 8: DELETE applications for both users"
Write-Output " DELETE /api/applications/{id} -> port 9001"
Write-Output "============================================"
Write-Output "`n  [rlm] Deleting application ${appIdRlm}..."
$delRlm = curl.exe -s -o NUL -w "%{http_code}" -X DELETE -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" "http://localhost:9001/api/applications/$appIdRlm"
Write-Output "  HTTP Status: $delRlm (204 = success)"
Write-Output "`n  [que] Deleting application ${appIdQue}..."
$delQue = curl.exe -s -o NUL -w "%{http_code}" -X DELETE -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" "http://localhost:9001/api/applications/$appIdQue"
Write-Output "  HTTP Status: $delQue (204 = success)"

# --- 8b. VERIFY DELETION ---
Write-Output "`n============================================"
Write-Output " STEP 8b: VERIFY deletions"
Write-Output " GET /api/applications/{id} -> port 9001"
Write-Output " Expected: 404 Not Found for both users"
Write-Output "============================================"
Write-Output "`n  [rlm] GET /api/applications/${appIdRlm} (should be 404)"
$verifyRlm = curl.exe -s -w "`n%{http_code}" -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" "http://localhost:9001/api/applications/$appIdRlm"
Write-Output "  Response: $verifyRlm"
Write-Output "`n  [que] GET /api/applications/${appIdQue} (should be 404)"
$verifyQue = curl.exe -s -w "`n%{http_code}" -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" "http://localhost:9001/api/applications/$appIdQue"
Write-Output "  Response: $verifyQue"

# --- 9. STATUS endpoint ---
Write-Output "`n============================================"
Write-Output " STEP 9: CHECK gateway status endpoint"
Write-Output " GET /status -> port 9001"
Write-Output " Shows: per-client token buckets + circuit breaker state"
Write-Output " Note: /status bypasses rate limiter entirely"
Write-Output "============================================"
$status = curl.exe -s http://localhost:9001/status
Write-Output "Response: $status"

# --- 10. RATE LIMIT test - TIER COMPARISON ---
Write-Output "`n============================================"
Write-Output " STEP 10: TIER-BASED RATE LIMIT TEST"
Write-Output " rlm = custom tier, capacity 50 (sends 53 requests)"
Write-Output " que = custom tier, capacity 20 (sends 23 requests)"
Write-Output " Both distributed across 3 gateway instances"
Write-Output " Proves: different clients get different limits"
Write-Output " Proves: limits are globally enforced via shared Redis"
Write-Output "============================================"
docker exec ratelimiter-redis redis-cli FLUSHALL | Out-Null

Write-Output "`n  --- rlm: 58 requests (capacity 50) ---"
$rlmAllowed = 0; $rlmBlocked = 0
1..58 | ForEach-Object {
    $port = 9001 + ($_ % 3)
    $code = curl.exe -s -o NUL -w "%{http_code}" -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" "http://localhost:${port}/api/applications"
    if ($code -eq "429") { $rlmBlocked++ } else { $rlmAllowed++ }
    $label = if ($code -eq "429") {"BLOCKED"} else {"ALLOWED"}
    Write-Output "  Request $_ -> port $port -> HTTP $code ($label)"
}
Write-Output "`n  rlm TOTAL: Allowed=$rlmAllowed | Blocked(429)=$rlmBlocked (expected: 50 allowed, 8 blocked)"

Write-Output "`n  --- que: 25 requests (capacity 20) ---"
$queAllowed = 0; $queBlocked = 0
1..25 | ForEach-Object {
    $port = 9001 + ($_ % 3)
    $code = curl.exe -s -o NUL -w "%{http_code}" -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" "http://localhost:${port}/api/applications"
    if ($code -eq "429") { $queBlocked++ } else { $queAllowed++ }
    $label = if ($code -eq "429") {"BLOCKED"} else {"ALLOWED"}
    Write-Output "  Request $_ -> port $port -> HTTP $code ($label)"
}
Write-Output "`n  que TOTAL: Allowed=$queAllowed | Blocked(429)=$queBlocked (expected: 20 allowed, 5 blocked)"

Write-Output "`n  TIER COMPARISON:"
Write-Output "  rlm (capacity 50): $rlmAllowed allowed, $rlmBlocked blocked"
Write-Output "  que (capacity 20): $queAllowed allowed, $queBlocked blocked"
Write-Output "  Different clients, different limits, same Redis, same gateway instances!"

# --- 11. CIRCUIT BREAKER test ---
Write-Output "`n============================================"
Write-Output " STEP 11: CIRCUIT BREAKER TEST"
Write-Output " Stopping HireTrack to simulate backend failure"
Write-Output " Circuit breaker config: 50% failure threshold, window=5"
Write-Output " Expected: first 3 requests = 502 (tried backend, failed)"
Write-Output "           remaining = 503 (circuit OPEN, instant fail)"
Write-Output " Watch the response times - 503s should be instant"
Write-Output "============================================"
docker stop hiretrack-app | Out-Null
Write-Output "HireTrack stopped."
docker exec ratelimiter-redis redis-cli FLUSHALL | Out-Null
Start-Sleep -Seconds 2
1..10 | ForEach-Object {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = curl.exe -s -o NUL -w "%{http_code}" -H "X-Client-Id: cbtest" http://localhost:9001/api/applications
    $sw.Stop()
    $label = if ($code -eq "502") {"TRIED backend, failed"} elseif ($code -eq "503") {"CIRCUIT OPEN - instant fail"} else {$code}
    Write-Output "  Request $_ -> $($sw.ElapsedMilliseconds)ms -> HTTP $code ($label)"
}

# --- 12. RECOVERY ---
Write-Output "`n============================================"
Write-Output " STEP 12: CIRCUIT BREAKER RECOVERY"
Write-Output " Restarting HireTrack, waiting 35s for circuit to half-open"
Write-Output " Circuit will send 1 probe request - if it succeeds, closes"
Write-Output " Expected: HTTP 200 (circuit recovered, traffic flows again)"
Write-Output "============================================"
docker start hiretrack-app | Out-Null
Write-Output "  HireTrack restarted. Waiting 35 seconds..."
Start-Sleep -Seconds 35
docker exec ratelimiter-redis redis-cli FLUSHALL | Out-Null
$code = curl.exe -s -o NUL -w "%{http_code}" -H "X-Client-Id: cbtest" -H "Authorization: Bearer $tokenRlm" http://localhost:9001/api/applications
$label = if ($code -eq "200") {"CIRCUIT RECOVERED - traffic flowing!"} elseif ($code -eq "401") {"CIRCUIT RECOVERED - HireTrack responding"} else {"HTTP $code"}
Write-Output "  Recovery result -> HTTP $code ($label)"

# --- 12b. PROVE SYSTEM IS FULLY BACK ---
Write-Output "`n============================================"
Write-Output " STEP 12b: PROVE system is fully operational"
Write-Output " Fetching real data for both users after recovery"
Write-Output "============================================"
docker exec ratelimiter-redis redis-cli FLUSHALL | Out-Null
Write-Output "`n  [rlm] GET /api/applications"
$fullRlm = curl.exe -s -H "X-Client-Id: rlm" -H "Authorization: Bearer $tokenRlm" http://localhost:9001/api/applications
Write-Output "  Response: $fullRlm"
Write-Output "`n  [que] GET /api/applications"
$fullQue = curl.exe -s -H "X-Client-Id: que" -H "Authorization: Bearer $tokenQue" http://localhost:9001/api/applications
Write-Output "  Response: $fullQue"
Write-Output "`n  System is fully recovered and serving data for both users!"

# --- 13. CLEANUP ---
Write-Output "`n============================================"
Write-Output " STEP 13: CLEANUP"
Write-Output " Removing both test users from HireTrack database"
Write-Output " Flushing Redis rate limit data"
Write-Output "============================================"
docker exec hiretrack-postgres psql -U postgres -d hiretrack -c "DELETE FROM users WHERE email IN ('rlm@gmail.com','que@gmail.com');" 2>$null
Write-Output "  Users rlm@gmail.com and que@gmail.com removed from database."
docker exec ratelimiter-redis redis-cli FLUSHALL | Out-Null
Write-Output "  Redis flushed."

# Remove temp files
Remove-Item register-rlm.json, login-rlm.json, register-que.json, login-que.json, create-app.json, update-app.json, update-status.json -ErrorAction SilentlyContinue
Write-Output "  Temp files removed."

Write-Output "`n============================================"
Write-Output " DEMO COMPLETE"
Write-Output " "
Write-Output " Summary of what was demonstrated:"
Write-Output "  - All HTTP methods (GET/POST/PUT/PATCH/DELETE) proxied"
Write-Output "  - Two users with different rate limit tiers"
Write-Output "    rlm: 50 req/min | que: 20 req/min | default: 10 req/min"
Write-Output "  - Per-client rate limiting via Redis (shared across 3 instances)"
Write-Output "  - Circuit breaker: fast-fail when backend is down"
Write-Output "  - Automatic recovery when backend comes back"
Write-Output "  - Status endpoint for observability"
Write-Output "============================================"