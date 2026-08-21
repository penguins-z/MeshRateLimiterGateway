package com.fd.MeshRateLimiterGateway.proxy;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Collections;

@Service
public class ProxyService {

    private final WebClient webClient;

    public ProxyService(@Value("${gateway.backend-url}") String backendUrl) {
        this.webClient = WebClient.builder()
                .baseUrl(backendUrl)
                .build();
    }

    public ResponseEntity<byte[]> forward(HttpServletRequest request) {
        String path = request.getRequestURI();
        String query = request.getQueryString();
        String uri = query != null ? path + "?" + query : path;

        return webClient
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
                .onStatus(status -> true, response -> Mono.empty())
                .toEntity(byte[].class)
                .block();
    }
}