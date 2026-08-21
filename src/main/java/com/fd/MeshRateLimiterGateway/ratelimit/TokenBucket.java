package com.fd.MeshRateLimiterGateway.ratelimit;

public class TokenBucket {
    private final double capacity;
    private final double refillRatePerSecond;
    private double tokens;
    private long lastRefillTimestampMillis;

    public TokenBucket(double capacity, double refillRatePerSecond) {
        this.capacity = capacity;
        this.refillRatePerSecond = refillRatePerSecond;
        this.tokens = capacity; //on creation, user starts with max tokens
        this.lastRefillTimestampMillis = System.currentTimeMillis();
    }

    private void refill() {
        long now = System.currentTimeMillis();
        double elapsedSeconds = (now - lastRefillTimestampMillis) / 1000d;
        double tokensToAdd = elapsedSeconds * refillRatePerSecond;
        tokens = Math.min(capacity, tokens + tokensToAdd);
        this.lastRefillTimestampMillis = now;
    }

    public boolean tryConsume() {
        refill();
        if(tokens >= 1){
            tokens--;
            return true;
        }
        else
            return false;
    }
}
