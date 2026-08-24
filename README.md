# MeshRateLimiterGateway

A distributed API gateway that enforces per-client rate limiting using a Redis-backed token bucket algorithm and protects the backend with a circuit breaker.

## Architecture

Each gateway instance:
1. **Extracts client ID** from `X-Client-Id` header (falls back to IP)
2. **Rate limits** via Redis Lua script (atomic token bucket)
3. **Proxies** the request to HireTrack (if allowed)
4. **Circuit breaks** if HireTrack is unresponsive (fast-fail with 503)

## Features

| Feature | Implementation |
|---------|---------------|
| Token Bucket Rate Limiting | Redis + Lua script for atomic operations |
| Per-Client Tiers | YAML config (rlm: 50/min, que: 20/min, default: 10/min) |
| Distributed State | All gateway instances share Redis - limits enforced globally |
| Circuit Breaker | Resilience4j (50% threshold, window=5, 30s open, 1 half-open probe) |
| Transparent Proxy | All HTTP methods, headers, and body forwarded faithfully |
| Status Endpoint | `/status` - real-time token counts + circuit breaker state |

## Tech Stack

- **Java 21** + **Spring Boot 4.1.0**
- **Redis 7** - shared rate limit state
- **Resilience4j** - circuit breaker (core library, programmatic config)
- **WebClient** - non-blocking HTTP proxy
- **Docker Compose** - multi-instance deployment
- **Lua scripting** - atomic token bucket operations in Redis

## Quick Start (Docker - fully self-contained)

```bash
# Clone and run everything (HireTrack + Postgres + Redis + 3 Gateways)
docker-compose up -d --build

# Run the automated demo (registers users, tests CRUD, rate limits, circuit breaker)
docker-compose --profile demo run --rm demo

# Cleanup
docker-compose --profile demo down -v
```

## How Rate Limiting Works

```
Client Request -> Gateway Filter -> Redis Lua Script -> Allow/Deny
                                         |
                               +---------+---------+
                               |  Token Bucket     |
                               |  - capacity: 50   |
                               |  - tokens: 47     |
                               |  - refill: 0.83/s |
                               |  - last_refill: ts|
                               +-------------------+
```

The Lua script executes atomically in Redis:
1. Read current bucket state
2. Calculate tokens to add since last refill (lazy refill)
3. If tokens >= 1: decrement and return ALLOWED
4. Else: return DENIED (429 Too Many Requests)

Because it is in Redis, all 3 gateway instances see the same bucket - a client cannot bypass limits by hitting different instances.

## How Circuit Breaker Works

```
CLOSED --(50% failures in window of 5)--> OPEN --(30s wait)--> HALF_OPEN
  ^                                                                |
  +----------(probe succeeds)--------------------------------------+
```

- **CLOSED**: Normal operation, requests forwarded to HireTrack
- **OPEN**: HireTrack is down, instant 503 (no network call)
- **HALF_OPEN**: Sends 1 probe request - if it succeeds, circuit closes

The circuit breaker is **per-instance** (in-memory) - this is industry standard because:
- Each instance has its own network path to the backend
- No coordination overhead
- Distributed circuit breakers add complexity without proportional benefit

## Project Structure

```
src/main/java/com/fd/MeshRateLimiterGateway/
+-- gateway/
|   +-- GatewayFilter.java          # OncePerRequestFilter - orchestrates everything
+-- ratelimit/
|   +-- RateLimiter.java            # Interface: boolean allowRequest(clientId)
|   +-- TokenBucket.java            # POJO: capacity, tokens, lastRefill
|   +-- InMemoryTokenBucketRateLimiter.java   # @Profile(!redis) - single instance
|   +-- RedisTokenBucketRateLimiter.java      # @Profile(redis) - distributed
|   +-- RateLimitProperties.java    # Per-client tier config from YAML
+-- proxy/
|   +-- ProxyService.java           # WebClient proxy + circuit breaker wrapper
+-- circuitbreaker/
|   +-- CircuitBreakerConfig.java   # Resilience4j programmatic configuration
+-- config/
|   +-- RedisConfig.java            # Loads Lua script as Spring bean
+-- status/
    +-- StatusController.java       # GET /status - observability endpoint

src/main/resources/
+-- application.yml                 # Server, backend URL, tier config, Redis
+-- scripts/
    +-- token_bucket.lua            # Atomic token bucket algorithm
```

## Demo Output Highlights

**Rate Limiting (tier-based):**
```
rlm (capacity 50): 50 allowed, 3 blocked
que (capacity 20): 20 allowed, 3 blocked
Different clients, different limits, same Redis, same gateway instances!
```

**Circuit Breaker (backend failure):**
```
Request 1 -> HTTP 502 (TRIED backend, failed)
Request 2 -> HTTP 502 (TRIED backend, failed)
Request 3 -> HTTP 502 (TRIED backend, failed)
Request 4 -> HTTP 503 (CIRCUIT OPEN - instant fail)
...
[35 seconds later]
Recovery probe -> HTTP 200 (CIRCUIT RECOVERED - backend responding!)
```

## Configuration

```yaml
ratelimit:
  default-capacity: 10
  default-refill-rate-per-second: 0.1667    # ~10 per minute
  clients:
    rlm:
      capacity: 50
      refill-rate-per-second: 0.8333        # ~50 per minute
    que:
      capacity: 20
      refill-rate-per-second: 0.3333        # ~20 per minute
```

## Design Decisions

| Decision | Reasoning |
|----------|-----------|
| Redis for rate limiting | Shared state across instances; Lua for atomicity without distributed locks |
| In-memory circuit breaker | Per-instance is industry standard; no coordination needed |
| Lazy token refill | No background threads; tokens calculated on-demand using elapsed time |
| OncePerRequestFilter | Intercepts ALL requests before DispatcherServlet; terminal handler for proxied paths |
| WebClient (not RestTemplate) | Non-blocking I/O; does not tie up servlet threads while waiting for backend |
| Profiles for switching | @Profile(redis) vs @Profile(!redis) - easy local dev without Redis |