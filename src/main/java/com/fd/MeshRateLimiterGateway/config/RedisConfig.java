package com.fd.MeshRateLimiterGateway.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.core.script.RedisScript;

@Configuration
public class RedisConfig {

    @Bean
    public RedisScript<Long> tokenBucketScript() {
        return RedisScript.of(new ClassPathResource("scripts/token_bucket.lua"), Long.class);
    }
}