package com.example.orderapi;

import java.math.BigDecimal;

public record Order(long id, String product, int quantity, BigDecimal total, String status) {
}
