// Captures the four canonical marketing screenshots from a Flutter WEB build
// running in demo mode — no emulator, no device, no LAN. Output lands in the
// same design/shots/0N-*.png files the framer (design/store.html, §3 of
// docs/MARKETING-ASSETS.md) already reads, so framing needs zero changes.
//
// Self-contained: builds web, serves build/web over http, drives headless
// Chrome via the DevTools Protocol (dart:io WebSocket — no python/node/puppeteer)
// and waits for Flutter to render AND the wordmark PNG to decode before each
// shot, which one-shot `chrome --screenshot` can't do reliably.
//
// Usage:  ~/fvm/versions/3.35.2/bin/dart run tool/capture_shots.dart
// Requires: fvm Flutter 3.35.2, Google Chrome. Override the browser with
// $CHROME; skip the (re)build with --no-build.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _httpPort = 8420;
const _dbgPort = 9222;

// A web canvas has no OS status bar; emulate a 450x1000 phone viewport at
// DSF 2.4 → a 1080x2400 shot (the framer's expected ~0.45 aspect). Demo mode
// injects safe-area padding (lib/app.dart) so nothing looks crammed.
const _vw = 450, _vh = 1000;
const _dsf = 2.4;

// go_router uses the hash URL strategy on web; deep-link straight to each
// screen (demo UUIDs are fixed in lib/demo/demo_mode.dart) instead of tapping.
const _screens = <(String, String)>[
  ('01-overview', '/#/'),
  ('02-home-theater', '/#/theater/RINCON_DEMO_ARC000001400'),
  ('03-group', '/#/group'),
  ('04-profiles', '/#/profiles'),
];

const _mime = <String, String>{
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

late final String _root;
final String _flutter = '${Platform.environment['HOME']}/fvm/versions/3.35.2/bin/flutter';
String get _chrome =>
    Platform.environment['CHROME'] ??
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

Future<void> main(List<String> args) async {
  _root = _repoRoot();
  final build = !args.contains('--no-build');

  if (build) {
    stdout.writeln('==> Building Flutter web (demo mode)…');
    final r = await Process.start(_flutter,
        ['build', 'web', '--release', '--dart-define=DEMO=true'],
        workingDirectory: _root, mode: ProcessStartMode.inheritStdio);
    if (await r.exitCode != 0) {
      stderr.writeln('web build failed');
      exit(1);
    }
  }

  final webDir = Directory('$_root/build/web');
  if (!webDir.existsSync()) {
    stderr.writeln('build/web missing — run without --no-build first');
    exit(1);
  }

  stdout.writeln('==> Serving build/web on :$_httpPort');
  final server = await _serve(webDir);

  stdout.writeln('==> Launching headless Chrome');
  final tmp = Directory.systemTemp.createTempSync('sonority-shots');
  final chrome = await Process.start(_chrome, [
    '--headless=new',
    '--hide-scrollbars',
    // CanvasKit needs a WebGL context or it falls back to CPU rendering, which
    // draws images (e.g. the wordmark PNG) blank. `--disable-gpu` would kill
    // WebGL; instead allow SwiftShader so CanvasKit gets its GPU path.
    '--enable-unsafe-swiftshader',
    '--remote-debugging-port=$_dbgPort',
    '--user-data-dir=${tmp.path}',
    'about:blank',
  ]);

  try {
    final wsUrl = await _pageWebSocketUrl();
    final cdp = await _Cdp.connect(wsUrl);
    await cdp.send('Page.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      'width': _vw,
      'height': _vh,
      'deviceScaleFactor': _dsf,
      'mobile': false,
    });

    final shotsDir = Directory('$_root/design/shots')..createSync(recursive: true);
    for (final (name, path) in _screens) {
      final url = 'http://localhost:$_httpPort$path';
      stdout.writeln('==> Capturing $name  ($path)');
      // Fresh boot per screen: about:blank → target URL fires a real load event
      // (a hash-only change wouldn't), so Flutter re-parses the route each time.
      await cdp.navigate('about:blank');
      await cdp.navigate(url);
      await cdp.waitForFlutterRender();
      final b64 = await cdp.send('Page.captureScreenshot', {'format': 'png'});
      final bytes = base64.decode((b64 as Map)['data'] as String);
      File('${shotsDir.path}/$name.png').writeAsBytesSync(bytes);
    }
    await cdp.close();
  } finally {
    chrome.kill();
    await chrome.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => 0);
    await server.close(force: true);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* Chrome may still hold a lock; harmless temp dir */}
  }
  stdout.writeln('==> Done. Four shots in design/shots/ — now run the framer (§3).');
  exit(0);
}

String _repoRoot() {
  final r = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  return (r.stdout as String).trim();
}

Future<HttpServer> _serve(Directory webDir) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _httpPort);
  server.listen((req) async {
    var p = req.uri.path;
    if (p == '/' || p.isEmpty) p = '/index.html';
    final file = File('${webDir.path}$p');
    if (!file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final ext = p.contains('.') ? p.substring(p.lastIndexOf('.')) : '';
    req.response.headers.contentType =
        ContentType.parse(_mime[ext] ?? 'application/octet-stream');
    await req.response.addStream(file.openRead());
    await req.response.close();
  });
  return server;
}

/// The debugger WebSocket URL of Chrome's initial page target.
Future<String> _pageWebSocketUrl() async {
  final client = HttpClient();
  for (var i = 0; i < 100; i++) {
    try {
      final req = await client.get('localhost', _dbgPort, '/json/list');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final targets = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
      final page = targets.firstWhere((t) => t['type'] == 'page',
          orElse: () => const {});
      final ws = page['webSocketDebuggerUrl'] as String?;
      if (ws != null) {
        client.close();
        return ws;
      }
    } catch (_) {/* Chrome not up yet */}
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('Could not reach Chrome DevTools on :$_dbgPort');
}

/// Minimal DevTools-Protocol client over a single page WebSocket.
class _Cdp {
  final WebSocket _ws;
  var _id = 0;
  final _pending = <int, Completer<Object?>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  _Cdp._(this._ws) {
    _ws.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      if (msg.containsKey('id')) {
        _pending.remove(msg['id'])?.complete(msg['result']);
      } else if (msg.containsKey('method')) {
        _events.add(msg);
      }
    });
  }

  static Future<_Cdp> connect(String wsUrl) async =>
      _Cdp._(await WebSocket.connect(wsUrl));

  Future<Object?> send(String method, [Map<String, Object?>? params]) {
    final id = ++_id;
    final c = Completer<Object?>();
    _pending[id] = c;
    _ws.add(jsonEncode({'id': id, 'method': method, 'params': params ?? {}}));
    return c.future;
  }

  Future<void> navigate(String url) async {
    final done = _events.stream
        .firstWhere((e) => e['method'] == 'Page.frameStoppedLoading')
        .timeout(const Duration(seconds: 30), onTimeout: () => {});
    await send('Page.navigate', {'url': url});
    await done;
  }

  /// Wait until Flutter has mounted its view, then settle so the wordmark PNG
  /// and icon fonts finish decoding before the shot.
  Future<void> waitForFlutterRender() async {
    for (var i = 0; i < 60; i++) {
      final r = await send('Runtime.evaluate', {
        'expression':
            "!!document.querySelector('flutter-view, flt-glass-pane')",
        'returnByValue': true,
      });
      if (((r as Map)['result'] as Map)['value'] == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await Future<void>.delayed(const Duration(milliseconds: 2500));
  }

  Future<void> close() => _ws.close();
}
