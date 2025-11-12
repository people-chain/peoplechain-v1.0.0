// Demonstrates calling the Monitor Server REST endpoints and WebSocket stream.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final httpClient = HttpClient();
  final req = await httpClient.getUrl(Uri.parse('http://127.0.0.1:8080/api/info'));
  final res = await req.close();
  final body = await utf8.decodeStream(res);
  print('GET /api/info => $body');

  try {
    final ws = await WebSocket.connect('ws://127.0.0.1:8080/ws');
    ws.add(jsonEncode({'type': 'get_info'}));
    ws.listen((e) => print('WS: $e'));
    await Future.delayed(const Duration(seconds: 1));
    await ws.close();
  } catch (e) {
    print('WS error: $e');
  }
}
