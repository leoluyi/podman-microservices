package com.example.user.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;

@RestController
public class UserController {
    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "healthy", "service", "api-user");
    }

    @GetMapping("/")
    public Map<String, String> root() {
        return Map.of("status", "ok", "service", "api-user");
    }
}
