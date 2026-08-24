package com.fd.MeshRateLimiterGateway.ratelimit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.concurrent.ConcurrentHashMap;

@Component
@Profile("!redis")
public class InMemoryTokenBucketRateLimiter implements RateLimiter {

    private final ConcurrentHashMap<String, TokenBucket> buckets = new ConcurrentHashMap<>();
    private final RateLimitProperties properties;

    public InMemoryTokenBucketRateLimiter(RateLimitProperties properties) {
        this.properties = properties;
    }

    @Override
    public boolean allowRequest(String clientId) {
        double capacity = properties.getCapacityFor(clientId);
        double refillRate = properties.getRefillRateFor(clientId);

        TokenBucket bucket = buckets.computeIfAbsent(clientId,
                id -> new TokenBucket(capacity, refillRate));
        synchronized (bucket) {
            return bucket.tryConsume();
        }
    }
}
