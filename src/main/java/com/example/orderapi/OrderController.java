package com.example.orderapi;

import java.math.BigDecimal;
import java.util.List;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    // Fixed demo data for the first endpoint; no persistence is configured yet.
    private static final List<Order> ORDERS = List.of(
            new Order(1L, "Keyboard", 2, new BigDecimal("99.98"), "CREATED"));

    @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
    public List<Order> getOrders() {
        return ORDERS;
    }
}
