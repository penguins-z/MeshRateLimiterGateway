package com.fd.MeshRateLimiterGateway.ratelimit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Collections;

@Component
@Profile("redis")
public class RedisTokenBucketRateLimiter implements RateLimiter {

    private final StringRedisTemplate redisTemplate;
    private final RedisScript<Long> script;
    private final double capacity;
    private final double refillRatePerSecond;

    public RedisTokenBucketRateLimiter(
            StringRedisTemplate redisTemplate,
            RedisScript<Long> script,
            @Value("${ratelimit.capacity}") double capacity,
            @Value("${ratelimit.refill-rate-per-second}") double refillRatePerSecond) {
        this.redisTemplate = redisTemplate;
        this.script = script;
        this.capacity = capacity;
        this.refillRatePerSecond = refillRatePerSecond;
    }

    @Override
    public boolean allowRequest(String clientId) {
        String key = "ratelimit:hiretrack:" + clientId;
        double now = Instant.now().toEpochMilli() / 1000.0;

        Long result = redisTemplate.execute(
                script,
                Collections.singletonList(key),
                String.valueOf(capacity),
                String.valueOf(refillRatePerSecond),
                String.valueOf(now),
                "1"
        );

        return result != null && result == 1L;
    }
}