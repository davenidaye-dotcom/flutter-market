import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Probe WebSocket endpoints. Run: dart run scripts/ws_probe.dart
Future<void> main(List<String> args) async {
  const base = 'http://207.148.105.182/api/v1';
  const clientId = 'flyroom';
  final wsCandidates = [
    'ws://207.148.105.182/ws/v1',
    'ws://207.148.105.182:9080/ws/v1',
    'ws://207.148.105.182:8080/ws/v1',
  ];
  if (args.isNotEmpty) {
    wsCandidates.clear();
    wsCandidates.addAll(args);
  }

  final token = await _login(base, 'player01', 'Pass1234');
  stdout.writeln('token=${token.isEmpty ? "FAIL" : "${token.substring(0, 20)}..."}');

  for (final wsBase in wsCandidates) {
    for (final path in ['member', 'owner']) {
      final uri = '$wsBase/$path?token=$token';
      stdout.write('TRY $uri ... ');
      try {
        final ws = await WebSocket.connect(uri).timeout(const Duration(seconds: 12));
        ws.add(jsonEncode({'action': 'PING'}));
        ws.add(jsonEncode({
          'action': 'SUBSCRIBE',
          'topic': 'room:900010001:game:JS_SC',
        }));
        final msgs = <String>[];
        final sub = ws.listen((e) => msgs.add('$e'));
        await Future<void>.delayed(const Duration(seconds: 3));
        await sub.cancel();
        await ws.close();
        stdout.writeln('OK received=${msgs.length} sample=${msgs.isEmpty ? "-" : msgs.first.substring(0, msgs.first.length.clamp(0, 80))}');
      } catch (e) {
        stdout.writeln('FAIL $e');
      }
    }
  }
}

Future<String> _login(String base, String user, String pwd) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$base/auth/member/login'));
    req.headers.set('clientid', 'flyroom');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode({
      'username': user,
      'password': pwd,
      'clientType': 'APP',
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final map = jsonDecode(body);
    if (map is Map && map['code'] == 200 && map['data'] is Map) {
      return '${map['data']['accessToken'] ?? ''}';
    }
  } catch (_) {}
  finally {
    client.close(force: true);
  }
  return '';
}
