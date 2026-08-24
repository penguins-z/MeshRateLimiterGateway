package com.fd.MeshRateLimiterGateway.status;

import com.fd.MeshRateLimiterGateway.ratelimit.RateLimitProperties;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

@RestController
public class StatusController {

    private final StringRedisTemplate redisTemplate;
    private final CircuitBreaker circuitBreaker;
    private final RateLimitProperties properties;

    public StatusController(StringRedisTemplate redisTemplate,
                            CircuitBreaker circuitBreaker,
                            RateLimitProperties properties) {
        this.redisTemplate = redisTemplate;
        this.circuitBreaker = circuitBreaker;
        this.properties = properties;
    }

    @GetMapping("/status")
    public Map<String, Object> status() {
        Map<String, Object> result = new HashMap<>();

        // Circuit breaker state
        Map<String, Object> cbState = new HashMap<>();
        cbState.put("state", circuitBreaker.getState().name());
        cbState.put("failureRate", circuitBreaker.getMetrics().getFailureRate());
        cbState.put("numberOfFailedCalls", circuitBreaker.getMetrics().getNumberOfFailedCalls());
        cbState.put("numberOfSuccessfulCalls", circuitBreaker.getMetrics().getNumberOfSuccessfulCalls());
        result.put("circuitBreaker", cbState);

        // Rate limit buckets from Redis
        Map<String, Map<String, String>> buckets = new HashMap<>();
        Set<String> keys = redisTemplate.keys("ratelimit:hiretrack:*");
        if (keys != null) {
            double now = System.currentTimeMillis() / 1000.0;
            for (String key : keys) {
                String clientId = key.replace("ratelimit:hiretrack:", "");
                double capacity = properties.getCapacityFor(clientId);
                double refillRate = properties.getRefillRateFor(clientId);

                Map<Object, Object> entries = redisTemplate.opsForHash().entries(key);
                double tokens = Double.parseDouble(entries.getOrDefault("tokens", "0").toString());
                double lastRefill = Double.parseDouble(entries.getOrDefault("last_refill", "0").toString());
                double elapsed = now - lastRefill;
                double currentTokens = Math.min(capacity, tokens + (elapsed * refillRate));

                Map<String, String> bucketData = new HashMap<>();
                bucketData.put("currentTokens", String.format("%.2f", currentTokens));
                bucketData.put("capacity", String.valueOf(capacity));
                bucketData.put("tier", properties.getClients().containsKey(clientId) ? "custom" : "default");
                buckets.put(clientId, bucketData);
            }
        }
        result.put("buckets", buckets);

        return result;
    }
}