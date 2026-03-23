package com.example.product.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;

@RestController
public class ProductController {
    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "healthy", "service", "api-product");
    }

    @GetMapping("/")
    public Map<String, String> root() {
        return Map.of("status", "ok", "service", "api-product");
    }
}
