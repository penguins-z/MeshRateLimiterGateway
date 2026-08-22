package com.fd.MeshRateLimiterGateway.ratelimit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.concurrent.ConcurrentHashMap;

@Component
@Profile("!redis")
public class InMemoryTokenBucketRateLimiter implements RateLimiter{

    private final ConcurrentHashMap<String, TokenBucket>  buckets = new ConcurrentHashMap<>();
    private final double capacity;
    private final double refillRatePerSecond;

    public InMemoryTokenBucketRateLimiter(@Value("${ratelimit.capacity}") double capacity,
                                          @Value("${ratelimit.refill-rate-per-second}") double refillRatePerSecond) {
        this.capacity = capacity;
        this.refillRatePerSecond = refillRatePerSecond;
    }

    @Override
    public boolean allowRequest(String clientId) {
        TokenBucket tokenBucket = buckets.computeIfAbsent(clientId, id -> new TokenBucket(capacity, refillRatePerSecond));
        synchronized (tokenBucket) {
            return tokenBucket.tryConsume();
        }
    }
}
