package com.fd.MeshRateLimiterGateway.proxy;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import jakarta.servlet.http.HttpServletRequest;
import reactor.core.publisher.Mono;

import java.util.Collections;

@Service
public class ProxyService {

    private final WebClient webClient;
    private final CircuitBreaker circuitBreaker;

    public ProxyService(@Value("${gateway.backend-url}") String backendUrl,
                        CircuitBreaker circuitBreaker) {
        this.webClient = WebClient.builder()
                .baseUrl(backendUrl)
                .build();
        this.circuitBreaker = circuitBreaker;
    }

    public ResponseEntity<byte[]> forward(HttpServletRequest request) {
        try {
            return circuitBreaker.executeSupplier(() -> doForward(request));
        } catch (CallNotPermittedException e) {
            // Circuit is OPEN — fail fast, this exception is by the circuitbreaker itself
            return ResponseEntity.status(503)
                    .body("{\"message\":\"Service unavailable. HireTrack is down.\"}".getBytes());
        }

        catch (RuntimeException e) {
            // Backend failed (5xx), circuit breaker counted it, return 502 to indicate bad gateway and to show its not user's fault
            return ResponseEntity.status(502)
                    .body("{\"message\":\"Backend error.\"}".getBytes());
        }
    }

    private ResponseEntity<byte[]> doForward(HttpServletRequest request) {
        String path = request.getRequestURI();
        String query = request.getQueryString();
        String uri = query != null ? path + "?" + query : path;

        ResponseEntity<byte[]> response = webClient
                .method(HttpMethod.valueOf(request.getMethod()))
                .uri(uri)
                .headers(headers -> {
                    Collections.list(request.getHeaderNames()).forEach(header -> {
                        if (!header.equalsIgnoreCase("host")) {
                            headers.set(header, request.getHeader(header));
                        }
                    });
                })
                .retrieve()
                .onStatus(status -> true, resp -> Mono.empty())
                .toEntity(byte[].class)
                .block();

        // Count 5xx as failures for the circuit breaker
        if (response != null && response.getStatusCode().is5xxServerError()) {
            throw new RuntimeException("Backend returned " + response.getStatusCode());
        }

        return response;
    }
}