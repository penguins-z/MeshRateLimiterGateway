package com.fd.MeshRateLimiterGateway.gateway;

import com.fd.MeshRateLimiterGateway.proxy.ProxyService;
import com.fd.MeshRateLimiterGateway.ratelimit.RateLimiter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
public class GatewayFilter extends OncePerRequestFilter {

    private final RateLimiter rateLimiter;
    private final ProxyService proxyService;

    public GatewayFilter(RateLimiter rateLimiter, ProxyService proxyService) {
        this.rateLimiter = rateLimiter;
        this.proxyService = proxyService;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {

        String clientId = extractClientId(request);

        if (!rateLimiter.allowRequest(clientId)) {
            response.setStatus(429);
            response.getWriter().write("Rate limit exceeded. Try again later.");
            return;
        }

        // Allowed — forward to HireTrack
        ResponseEntity<byte[]> backendResponse = proxyService.forward(request);

        // Write backend response back to client
        response.setStatus(backendResponse.getStatusCode().value());
        backendResponse.getHeaders().forEach((name, values) -> {
            if (!name.equalsIgnoreCase("Transfer-Encoding")
                    && !name.equalsIgnoreCase("Content-Length")) {
                values.forEach(value -> response.addHeader(name, value));
            }
        });

        byte[] body = backendResponse.getBody();
        if (body != null) {
            response.getOutputStream().write(body);
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return request.getRequestURI().equals("/status");
    }

    private String extractClientId(HttpServletRequest request) {
        String clientId = request.getHeader("X-Client-Id");
        if (clientId != null && !clientId.isBlank()) {
            return clientId;
        }
        return request.getRemoteAddr();
    }
}