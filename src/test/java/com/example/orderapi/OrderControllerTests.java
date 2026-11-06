package com.example.orderapi;

import java.math.BigDecimal;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class OrderControllerTests {

    private final OrderController controller = new OrderController();

    @Test
    void returnsTheDemoOrderWithExpectedDetails() {
        assertThat(controller.getOrders()).containsExactly(
                new Order(1L, "Keyboard", 2, new BigDecimal("99.98"), "CREATED"));
    }
}
