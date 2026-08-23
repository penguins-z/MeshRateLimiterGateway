package com.fd.MeshRateLimiterGateway.status;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import org.springframework.beans.factory.annotation.Value;
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
    private final double capacity;
    private final double refillRatePerSecond;

    public StatusController(StringRedisTemplate redisTemplate,
                            CircuitBreaker circuitBreaker,
                            @Value("${ratelimit.capacity}") double capacity,
                            @Value("${ratelimit.refill-rate-per-second}") double refillRatePerSecond) {
        this.redisTemplate = redisTemplate;
        this.circuitBreaker = circuitBreaker;
        this.capacity = capacity;
        this.refillRatePerSecond = refillRatePerSecond;
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
                Map<Object, Object> entries = redisTemplate.opsForHash().entries(key);
                double tokens = Double.parseDouble(entries.getOrDefault("tokens", "0").toString());
                double lastRefill = Double.parseDouble(entries.getOrDefault("last_refill", "0").toString());
                double elapsed = now - lastRefill;
                double currentTokens = Math.min(capacity, tokens + (elapsed * refillRatePerSecond));

                Map<String, String> bucketData = new HashMap<>();
                bucketData.put("currentTokens", String.format("%.2f", currentTokens));
                bucketData.put("capacity", String.valueOf(capacity));
                String clientId = key.replace("ratelimit:hiretrack:", "");
                buckets.put(clientId, bucketData);
            }
        }
        result.put("buckets", buckets);

        return result;
    }
}