package com.example.orderapi;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class OrderControllerTests {

	private final OrderController controller = new OrderController();

	@Test
	void getOrdersReturnsTheSampleOrder() {
		assertThat(controller.getOrders())
				.containsExactly(new Order(1L, "Laptop", 1, "CREATED"));
	}
}
