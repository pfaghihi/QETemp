package com.example.orderapi;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrderEndpointTests {

    @LocalServerPort
    private int port;

    @Test
    void getOrdersReturnsDemoOrdersAsJson() throws Exception {
        try (HttpClient client = HttpClient.newHttpClient()) {
            HttpResponse<String> response = client.send(request().GET().build(),
                    HttpResponse.BodyHandlers.ofString());

            assertThat(response.statusCode()).isEqualTo(200);
            assertThat(response.headers().firstValue("Content-Type")).hasValueSatisfying(
                    value -> assertThat(value).startsWith("application/json"));
            List<Map<String, Object>> orders = JsonPath.read(response.body(), "$");
            assertThat(orders).containsExactly(Map.of(
                    "id", 1, "product", "Keyboard", "quantity", 2,
                    "total", 99.98, "status", "CREATED"));
        }
    }

    @Test
    void postOrdersIsNotSupported() throws Exception {
        try (HttpClient client = HttpClient.newHttpClient()) {
            HttpResponse<String> response = client.send(
                    request().POST(HttpRequest.BodyPublishers.noBody()).build(),
                    HttpResponse.BodyHandlers.ofString());

            assertThat(response.statusCode()).isEqualTo(405);
            assertThat(response.headers().firstValue("Allow")).hasValueSatisfying(
                    value -> assertThat(value).contains("GET"));
        }
    }

    private HttpRequest.Builder request() {
        return HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api/orders"))
                .timeout(Duration.ofSeconds(10))
                .header("Accept", "application/json");
    }
}
