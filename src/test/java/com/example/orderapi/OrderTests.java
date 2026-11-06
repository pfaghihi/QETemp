package com.example.orderapi;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertAll;
import static org.junit.jupiter.api.Assertions.assertEquals;

class OrderTests {

	@Test
	void preservesOrderDetails() {
		var order = new Order(42L, "Keyboard", 3, "SHIPPED");

		assertAll(
				() -> assertEquals(42L, order.id()),
				() -> assertEquals("Keyboard", order.product()),
				() -> assertEquals(3, order.quantity()),
				() -> assertEquals("SHIPPED", order.status()));
	}
}
