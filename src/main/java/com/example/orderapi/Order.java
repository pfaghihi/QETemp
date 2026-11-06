package com.example.orderapi;

public record Order(long id, String product, int quantity, String status) {
}
