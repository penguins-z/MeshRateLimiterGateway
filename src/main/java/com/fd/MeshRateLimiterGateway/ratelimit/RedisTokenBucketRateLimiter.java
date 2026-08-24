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
    private final RateLimitProperties properties;

    public RedisTokenBucketRateLimiter(StringRedisTemplate redisTemplate,
                                       RedisScript<Long> script,
                                       RateLimitProperties properties) {
        this.redisTemplate = redisTemplate;
        this.script = script;
        this.properties = properties;
    }

    @Override
    public boolean allowRequest(String clientId) {
        String key = "ratelimit:hiretrack:" + clientId;
        double now = System.currentTimeMillis() / 1000.0;
        double capacity = properties.getCapacityFor(clientId);
        double refillRate = properties.getRefillRateFor(clientId);

        Long result = redisTemplate.execute(
                script,
                Collections.singletonList(key),
                String.valueOf(capacity),
                String.valueOf(refillRate),
                String.valueOf(now),
                "1"
        );

        return result != null && result == 1L;
    }
}