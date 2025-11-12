/*
 * PeopleChain Monitor • Java CRUD example (Java 11+)
 *
 * No external dependencies required. Uses java.net.http.HttpClient.
 * This example builds JSON strings manually for simplicity.
 *
 * Compile:
 *   javac java_crud_example.java
 * Run:
 *   java JavaCrudExample
 */

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

public class JavaCrudExample {
    static final String BASE = System.getenv().getOrDefault("PC_BASE", "http://127.0.0.1:8081");
    static final String COLLECTION = "notes";
    static final HttpClient client = HttpClient.newHttpClient();

    static String http(String method, String path, String jsonBody) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder().uri(URI.create(BASE + path)).method(method,
                jsonBody == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(jsonBody));
        b.header("Content-Type", "application/json");
        HttpResponse<String> res = client.send(b.build(), HttpResponse.BodyHandlers.ofString());
        if (res.statusCode() < 200 || res.statusCode() >= 300) {
            throw new RuntimeException(method + " " + path + " => " + res.statusCode() + "\n" + res.body());
        }
        return res.body();
    }

    public static void main(String[] args) throws Exception {
        System.out.println("1) Create two notes");
        String n1 = http("POST", "/api/db/" + COLLECTION, "{\"data\":{\"title\":\"First\",\"body\":\"Hello from Java\",\"tags\":[\"demo\",\"java\"]}} ");
        String n2 = http("POST", "/api/db/" + COLLECTION, "{\"data\":{\"title\":\"Second\",\"body\":\"Filter me\",\"tags\":[\"filter\"]}} ");
        System.out.println(n1); System.out.println(n2);

        System.out.println("\n2) List limit=10");
        System.out.println(http("GET", "/api/db/" + COLLECTION + "?limit=10", null));

        System.out.println("\n3) Filter q=filter");
        System.out.println(http("GET", "/api/db/" + COLLECTION + "?q=filter", null));

        // Extract id from n1 (very naive parsing for demo purposes)
        String id = n1.replaceAll(".*\"id\":\"([^\"]+)\".*", "$1");

        System.out.println("\n4) Read first by id");
        System.out.println(http("GET", "/api/db/" + COLLECTION + "/" + id, null));

        System.out.println("\n5) Replace with PUT");
        System.out.println(http("PUT", "/api/db/" + COLLECTION + "/" + id,
                "{\"data\":{\"title\":\"Updated\",\"body\":\"Replaced body\",\"tags\":[\"updated\"]}}"));

        System.out.println("\n6) Patch with PATCH");
        System.out.println(http("PATCH", "/api/db/" + COLLECTION + "/" + id,
                "{\"data\":{\"extra\":42,\"tags\":[\"updated\",\"patched\"]}}"));

        // Extract id of second doc
        String id2 = n2.replaceAll(".*\"id\":\"([^\"]+)\".*", "$1");
        System.out.println("\n7) Delete second");
        System.out.println(http("DELETE", "/api/db/" + COLLECTION + "/" + id2, null));

        System.out.println("\n8) List again");
        System.out.println(http("GET", "/api/db/" + COLLECTION, null));
    }
}
