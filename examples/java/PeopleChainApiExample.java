// Minimal Java 11+ client for PeopleChain monitor REST + WebSocket
//
// Compile & run (Linux/macOS):
//   javac PeopleChainApiExample.java && BASE_URL=http://192.168.1.50:8081 java PeopleChainApiExample
// Defaults to http://127.0.0.1:8081 if BASE_URL is not provided.

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.WebSocket;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;

public class PeopleChainApiExample {
    static final String BASE_URL = System.getenv().getOrDefault("BASE_URL", "http://127.0.0.1:8081");

    static String get(String path) throws Exception {
        var client = HttpClient.newHttpClient();
        var req = HttpRequest.newBuilder(URI.create(BASE_URL + path))
                .timeout(Duration.ofSeconds(10))
                .GET()
                .build();
        var res = client.send(req, HttpResponse.BodyHandlers.ofString());
        if (res.statusCode() >= 200 && res.statusCode() < 300) return res.body();
        throw new RuntimeException("HTTP " + res.statusCode());
    }

    static void restDemo() throws Exception {
        System.out.println("== REST: /api/info");
        System.out.println(get("/api/info"));

        System.out.println("\n== REST: /api/peers");
        System.out.println(get("/api/peers?limit=10"));

        System.out.println("\n== REST: /api/blocks");
        System.out.println(get("/api/blocks?from=tip&count=3"));
    }

    static void wsDemo() throws Exception {
        String wsUrl = BASE_URL.replace("http://", "ws://").replace("https://", "wss://") + "/ws";
        System.out.println("\n== WS: connecting to " + wsUrl);
        var latch = new CountDownLatch(1);
        var client = HttpClient.newHttpClient();
        WebSocket ws = client.newWebSocketBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .buildAsync(URI.create(wsUrl), new WebSocket.Listener() {
                    int count = 0;
                    @Override
                    public void onOpen(WebSocket webSocket) {
                        webSocket.sendText("{\"type\":\"get_info\"}", true);
                        WebSocket.Listener.super.onOpen(webSocket);
                    }
                    @Override
                    public CompletableFuture<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
                        System.out.println("WS: " + data);
                        if (++count >= 5) webSocket.sendClose(WebSocket.NORMAL_CLOSURE, "bye");
                        return WebSocket.Listener.super.onText(webSocket, data, last);
                    }
                    @Override
                    public CompletableFuture<?> onClose(WebSocket webSocket, int statusCode, String reason) {
                        latch.countDown();
                        return WebSocket.Listener.super.onClose(webSocket, statusCode, reason);
                    }
                    @Override
                    public void onError(WebSocket webSocket, Throwable error) {
                        error.printStackTrace();
                        latch.countDown();
                    }
                }).join();
        latch.await();
    }

    public static void main(String[] args) throws Exception {
        System.out.println("Using BASE_URL=" + BASE_URL);
        restDemo();
        wsDemo();
    }
}
