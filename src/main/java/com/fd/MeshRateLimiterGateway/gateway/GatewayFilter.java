package com.fd.MeshRateLimiterGateway.gateway;

import com.fd.MeshRateLimiterGateway.proxy.ProxyService;
import com.fd.MeshRateLimiterGateway.ratelimit.RateLimiter;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
public class GatewayFilter extends OncePerRequestFilter {

    private final RateLimiter rateLimiter;
    private final ProxyService proxyService;

    @Value("${gateway.jwt-secret}")
    private String jwtSecret;

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
        String authHeader = request.getHeader("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            try {
                String token = authHeader.substring(7);
                Claims claims = Jwts.parser()
                        .verifyWith(Keys.hmacShaKeyFor(java.util.HexFormat.of().parseHex(jwtSecret)))
                        .build()
                        .parseSignedClaims(token)
                        .getPayload();
                String email = claims.getSubject();
                System.out.println("JWT CLIENT ID: " + email);
                return email;
            } catch (Exception e) {
                System.err.println("JWT PARSE ERROR: " + e.getClass().getName() + " - " + e.getMessage());
            }
        } else {
            System.out.println("NO AUTH HEADER - falling to IP");
        }
        return request.getRemoteAddr();
    }
}