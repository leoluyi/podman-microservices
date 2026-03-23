package com.example.order.controller;

import com.example.order.dto.CreateOrderRequest;
import com.example.order.dto.OrderResponse;
import com.example.order.service.OrderService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "healthy", "service", "api-order");
    }

    @PostMapping("/orders")
    public ResponseEntity<OrderResponse> create(
            @Valid @RequestBody CreateOrderRequest req,
            @RequestHeader(value = "X-User-Id", required = false) String userId,
            @RequestHeader(value = "X-Partner-ID", required = false) String partnerId) {
        CallerInfo caller = resolveCaller(userId, partnerId);
        return ResponseEntity.status(201).body(orderService.create(req, caller.id(), caller.source()));
    }

    @GetMapping("/orders")
    public List<OrderResponse> list(
            @RequestHeader(value = "X-User-Id", required = false) String userId,
            @RequestHeader(value = "X-Partner-ID", required = false) String partnerId) {
        CallerInfo caller = resolveCaller(userId, partnerId);
        return orderService.list(caller.id(), caller.source());
    }

    @GetMapping("/orders/{id}")
    public OrderResponse getById(@PathVariable Long id) {
        return orderService.getById(id);
    }

    @PatchMapping("/orders/{id}/status")
    public OrderResponse updateStatus(@PathVariable Long id, @RequestBody Map<String, String> body) {
        return orderService.updateStatus(id, body.get("status"));
    }

    private record CallerInfo(String id, String source) {}

    private CallerInfo resolveCaller(String userId, String partnerId) {
        if (partnerId != null) return new CallerInfo(partnerId, "PARTNER");
        if (userId != null) return new CallerInfo(userId, "INTERNAL");
        throw new IllegalArgumentException("No caller identity in request headers");
    }
}
