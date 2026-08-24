package com.fd.MeshRateLimiterGateway.ratelimit;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

@Component
@ConfigurationProperties(prefix = "ratelimit")
public class RateLimitProperties {

    private double defaultCapacity;
    private double defaultRefillRatePerSecond;
    private Map<String, ClientConfig> clients = new HashMap<>();

    public double getDefaultCapacity() { return defaultCapacity; }
    public void setDefaultCapacity(double defaultCapacity) { this.defaultCapacity = defaultCapacity; }

    public double getDefaultRefillRatePerSecond() { return defaultRefillRatePerSecond; }
    public void setDefaultRefillRatePerSecond(double defaultRefillRatePerSecond) { this.defaultRefillRatePerSecond = defaultRefillRatePerSecond; }

    public Map<String, ClientConfig> getClients() { return clients; }
    public void setClients(Map<String, ClientConfig> clients) { this.clients = clients; }

    public double getCapacityFor(String clientId) {
        ClientConfig config = clients.get(clientId);
        return config != null ? config.getCapacity() : defaultCapacity;
    }

    public double getRefillRateFor(String clientId) {
        ClientConfig config = clients.get(clientId);
        return config != null ? config.getRefillRatePerSecond() : defaultRefillRatePerSecond;
    }

    public static class ClientConfig {
        private double capacity;
        private double refillRatePerSecond;

        public double getCapacity() { return capacity; }
        public void setCapacity(double capacity) { this.capacity = capacity; }

        public double getRefillRatePerSecond() { return refillRatePerSecond; }
        public void setRefillRatePerSecond(double refillRatePerSecond) { this.refillRatePerSecond = refillRatePerSecond; }
    }
}