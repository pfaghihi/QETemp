package com.example.orderapi;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrderEndpointTests {

	@Value("${local.server.port}")
	private int port;

	@ParameterizedTest
	@ValueSource(strings = {"POST", "PUT", "PATCH", "DELETE"})
	void unsupportedWriteMethodsReturnMethodNotAllowed(String method) throws Exception {
		try (var client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build()) {
			var request = HttpRequest.newBuilder()
					.uri(URI.create("http://localhost:" + port + "/api/orders"))
					.timeout(Duration.ofSeconds(10))
					.method(method, HttpRequest.BodyPublishers.noBody())
					.build();

			var response = client.send(request, HttpResponse.BodyHandlers.ofString());

			assertThat(response.statusCode()).isEqualTo(405);
			assertThat(response.headers().firstValue("Allow").orElseThrow().split(",\\s*"))
					.contains("GET");
		}
	}

	@Test
	void getOrdersReturnsSampleOrderAsJson() throws Exception {
		try (var client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build()) {
			var request = HttpRequest.newBuilder()
					.uri(URI.create("http://localhost:" + port + "/api/orders"))
					.header("Accept", "application/json")
					.timeout(Duration.ofSeconds(10))
					.GET()
					.build();

			var response = client.send(request, HttpResponse.BodyHandlers.ofString());

			assertThat(response.statusCode()).isEqualTo(200);
			var contentType = MediaType.parseMediaType(response.headers()
					.firstValue("Content-Type").orElseThrow());
			assertThat(contentType.isCompatibleWith(MediaType.APPLICATION_JSON)).isTrue();
			var json = JsonPath.parse(response.body());
			assertThat(json.read("$.length()", Integer.class)).isEqualTo(1);
			assertThat(json.read("$[0].id", Long.class)).isEqualTo(1L);
			assertThat(json.read("$[0].product", String.class)).isEqualTo("Laptop");
			assertThat(json.read("$[0].quantity", Integer.class)).isEqualTo(1);
			assertThat(json.read("$[0].status", String.class)).isEqualTo("CREATED");
		}
	}
}
