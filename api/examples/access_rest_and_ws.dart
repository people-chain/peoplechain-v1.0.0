import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  // REST: GET /api/info
  final http = HttpClient();
  final req = await http.getUrl(Uri.parse('http://127.0.0.1:8080/api/info'));
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  print('INFO: $text');

  // WebSocket: /ws
  final ws = await WebSocket.connect('ws://127.0.0.1:8080/ws');
  ws.add(jsonEncode({'type': 'get_info'}));
  ws.listen((data) {
    print('WS: $data');
  });
}
