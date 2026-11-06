package com.example.orderapi;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(OrderController.class)
class OrderControllerWebTests {

    @Autowired
    private MockMvc mvc;

    @Test
    void getOrdersReturnsJsonWithExpectedFields() throws Exception {
        mvc.perform(get("/api/orders").accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].id").value(1))
                .andExpect(jsonPath("$[0].product").value("Keyboard"))
                .andExpect(jsonPath("$[0].quantity").value(2))
                .andExpect(jsonPath("$[0].total").value(99.98))
                .andExpect(jsonPath("$[0].status").value("CREATED"));
    }

    @Test
    void unsupportedResponseFormatReturnsNotAcceptable() throws Exception {
        mvc.perform(get("/api/orders").accept(MediaType.APPLICATION_XML))
                .andExpect(status().isNotAcceptable());
    }

    @Test
    void creatingAnOrderIsNotSupported() throws Exception {
        mvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"product\":\"Mouse\",\"quantity\":1}"))
                .andExpect(status().isMethodNotAllowed());
    }
}
