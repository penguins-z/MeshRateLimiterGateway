package com.fd.MeshRateLimiterGateway.ratelimit;

public interface RateLimiter {
    boolean allowRequest(String clientId);
}
