package com.example.orderapi;

import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

	@GetMapping
	public List<Order> getOrders() {
		return List.of(new Order(1L, "Laptop", 1, "CREATED"));
	}
}
