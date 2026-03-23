package com.example.order.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record OrderResponse(
    Long id,
    String orderNumber,
    String customerName,
    String status,
    BigDecimal totalAmount,
    String createdBy,
    String source,
    LocalDateTime createdAt
) {}
