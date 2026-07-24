// Captures the four canonical marketing screenshots from a Flutter WEB build
// running in demo mode — and, with --frame, renders every framed store graphic
// from them too. No emulator, no device, no LAN. Raw shots land in
// design/shots/0N-*.png; framed graphics land in design/play/* and
// design/appstore/* (the same files docs/MARKETING-ASSETS.md §2–3 describe).
//
// Self-contained: builds web, serves build/web over http, and drives headless
// Chrome via the DevTools Protocol (dart:io WebSocket — no python/node/puppeteer).
// It waits for Flutter to render AND the wordmark PNG to decode before each
// shot, which one-shot `chrome --screenshot` can't do reliably. Framing renders
// design/store.html (a static page) the same headless way.
//
// Usage:  ~/fvm/versions/3.44.6/bin/dart run tool/capture_shots.dart [flags]
//   --frame        also render the framed Play + App Store graphics
//   --no-capture   skip the shot capture (re-frame existing design/shots)
//   --no-build     reuse an existing build/web (skip the web build)
// Requires: fvm Flutter 3.44.6, Google Chrome ($CHROME overrides the browser).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _httpPort = 8420;
const _dbgPort = 9222;

// Match a recent large iPhone (6.9" / 15–17 Pro Max class): a 430x932 logical
// viewport at DPR 3 → a 1290x2796 shot, which is also Apple's exact App Store
// 6.9" screenshot size (the framer's ios69 target). Real iPhone density (DPR 3,
// ~430pt wide) makes the UI scale like the device, not zoomed-out. Demo mode
// injects safe-area padding (lib/app.dart) so nothing looks crammed.
const _vw = 430, _vh = 932;
const _dsf = 3.0;

// Wide (tablet / desktop) capture. The app has ONE responsive "wide" layout
// (single breakpoint kWideLayoutBreakpoint=720 — nothing distinguishes tablet
// from desktop), so a single wide shot set serves iPad, Mac and Play tablet;
// only the store frame/canvas size differs. 1280x800 logical @ DPR 2 →
// 2560x1600 px, which is exactly Apple's macOS screenshot size and cover-fits
// the other landscape canvases. ≥720 logical width renders the NavigationRail
// + multi-column layout (lib/app.dart).
const _wideVw = 1280, _wideVh = 800;
const _wideDsf = 2.0;

// go_router uses the hash URL strategy on web; deep-link straight to each
// screen (demo UUIDs are fixed in lib/demo/demo_mode.dart) instead of tapping.
const _screens = <(String, String)>[
  ('01-overview', '/#/'),
  ('02-home-theater', '/#/theater/RINCON_DEMO_ARC000001400'),
  ('03-group', '/#/group'),
  ('04-profiles', '/#/profiles'),
];

// The four source shots, in `design/store.html`'s `i` order — used to name the
// per-screen framed outputs (i=0 → "1-overview", …).
const _shotNames = ['overview', 'home-theater', 'group', 'profiles'];

/// One framed-graphic render: a `design/store.html` mode + output size + which
/// source shot (`i`) + where it lands. Mirrors §3 of docs/MARKETING-ASSETS.md.
typedef _FrameJob = ({String mode, int w, int h, int i, String out});

// Landscape store graphics (tablet7/tablet10/mac/ipad13) all render the WIDE
// shots via design/store.html's framedLandscape — one wide capture set serves
// Play tablet, Mac and iPad; only the canvas size differs. Portrait phone
// graphics (phone/ios69) use the phone shots.
List<_FrameJob> _frameJobs() => [
      (mode: 'feature', w: 1024, h: 500, i: 0, out: 'design/play/feature-graphic.png'),
      (mode: 'tablet7', w: 1920, h: 1080, i: 0, out: 'design/play/tablet-7in.png'),
      (mode: 'tablet10', w: 2560, h: 1440, i: 0, out: 'design/play/tablet-10in.png'),
      for (var i = 0; i < 4; i++)
        (mode: 'phone', w: 1080, h: 1920, i: i, out: 'design/play/phone-${i + 1}-${_shotNames[i]}.png'),
      for (var i = 0; i < 4; i++)
        (mode: 'ios69', w: 1290, h: 2796, i: i, out: 'design/appstore/iphone69-${i + 1}-${_shotNames[i]}.png'),
      for (var i = 0; i < 4; i++)
        (mode: 'mac', w: 2560, h: 1600, i: i, out: 'design/appstore/mac-${i + 1}-${_shotNames[i]}.png'),
      // iPad 13" landscape (2752×2064) — 0.6.0 ships native iPad support, so the
      // App Store needs a distinct iPad set; the wide layout is what renders.
      for (var i = 0; i < 4; i++)
        (mode: 'ipad13', w: 2752, h: 2064, i: i, out: 'design/appstore/ipad13-${i + 1}-${_shotNames[i]}.png'),
    ];

// The extensions a `flutter build web` output actually contains; anything else
// falls back to octet-stream below.
const _mime = <String, String>{
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

late final String _root;
final String _flutter = '${Platform.environment['HOME']}/fvm/versions/3.44.6/bin/flutter';
String get _chrome =>
    Platform.environment['CHROME'] ??
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

Future<void> main(List<String> args) async {
  _root = _repoRoot();
  final noBuild = args.contains('--no-build');
  final doCapture = !args.contains('--no-capture');
  final doFrame = args.contains('--frame');

  if (doCapture && !noBuild) {
    stdout.writeln('==> Building Flutter web (demo mode)…');
    final r = await Process.start(_flutter,
        ['build', 'web', '--release', '--dart-define=DEMO=true'],
        workingDirectory: _root, mode: ProcessStartMode.inheritStdio);
    if (await r.exitCode != 0) {
      stderr.writeln('web build failed');
      exit(1);
    }
  }

  // Only the shot capture needs the built web app served over http; framing
  // reads design/store.html straight off disk via file://.
  HttpServer? server;
  if (doCapture) {
    final webDir = Directory('$_root/build/web');
    if (!webDir.existsSync()) {
      stderr.writeln('build/web missing — run without --no-build first');
      exit(1);
    }
    stdout.writeln('==> Serving build/web on :$_httpPort');
    server = await _serve(webDir);
  }

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
    final cdp = await _Cdp.connect(await _pageWebSocketUrl());
    await cdp.send('Page.enable');
    if (doCapture) await _capture(cdp);
    if (doFrame) await _frame(cdp);
    await cdp.close();
  } finally {
    chrome.kill();
    await chrome.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => 0);
    await server?.close(force: true);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* Chrome may still hold a lock; harmless temp dir */}
  }
  stdout.writeln('==> Done.');
  exit(0);
}

/// Screenshots the four canonical screens twice: once at iPhone scale
/// (design/shots/0N-*.png) and once at the wide tablet/desktop profile
/// (design/shots/0N-*-wide.png). The same routes render responsively, so the
/// wide pass yields the NavigationRail + multi-column layout.
Future<void> _capture(_Cdp cdp) async {
  await _captureAt(cdp, vw: _vw, vh: _vh, dsf: _dsf, suffix: '');
  await _captureAt(cdp, vw: _wideVw, vh: _wideVh, dsf: _wideDsf, suffix: '-wide');
}

Future<void> _captureAt(_Cdp cdp,
    {required int vw,
    required int vh,
    required double dsf,
    required String suffix}) async {
  await cdp.send('Emulation.setDeviceMetricsOverride',
      {'width': vw, 'height': vh, 'deviceScaleFactor': dsf, 'mobile': false});
  final shotsDir = Directory('$_root/design/shots')..createSync(recursive: true);
  for (final (name, path) in _screens) {
    stdout.writeln('==> Capturing $name$suffix  ($path)');
    // Fresh boot per screen: about:blank → target URL fires a real load event
    // (a hash-only change wouldn't), so Flutter re-parses the route each time.
    await cdp.navigate('about:blank');
    await cdp.navigate('http://localhost:$_httpPort$path');
    await cdp.waitForFlutterRender();
    await _writeShot(cdp, '${shotsDir.path}/$name$suffix.png');
  }
}

/// Renders every framed Play + App Store graphic from design/store.html.
Future<void> _frame(_Cdp cdp) async {
  final base = Uri.file('$_root/design/store.html');
  for (final job in _frameJobs()) {
    stdout.writeln('==> Framing ${job.out}  (${job.mode} ${job.w}x${job.h})');
    // DSF 1 so the PNG is exactly the window size; size the viewport per job
    // BEFORE loading so store.html's layout JS reads the right dimensions.
    await cdp.send('Emulation.setDeviceMetricsOverride',
        {'width': job.w, 'height': job.h, 'deviceScaleFactor': 1, 'mobile': false});
    final url = base.replace(
        queryParameters: {'mode': job.mode, 'i': '${job.i}'}).toString();
    await cdp.navigate(url);
    await cdp.waitForImages();
    final out = File('$_root/${job.out}')..parent.createSync(recursive: true);
    await _writeShot(cdp, out.path);
  }
}

Future<void> _writeShot(_Cdp cdp, String path) async {
  final res = await cdp.send('Page.captureScreenshot', {'format': 'png'});
  File(path).writeAsBytesSync(base64.decode((res as Map)['data'] as String));
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
    // Stay inside build/web (defensive — the tool drives its own loopback server).
    if (p.contains('..')) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
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
  try {
    for (var i = 0; i < 100; i++) {
      try {
        final req = await client.get('localhost', _dbgPort, '/json/list');
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        final targets = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
        final page = targets.firstWhere((t) => t['type'] == 'page',
            orElse: () => const {});
        final ws = page['webSocketDebuggerUrl'] as String?;
        if (ws != null) return ws;
      } catch (_) {/* Chrome not up yet */}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Could not reach Chrome DevTools on :$_dbgPort');
  } finally {
    client.close();
  }
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
        final c = _pending.remove(msg['id']);
        // Surface CDP errors instead of completing null → a misleading
        // "Null is not a Map" cast crash downstream hides the real message.
        if (msg.containsKey('error')) {
          c?.completeError(StateError('CDP error: ${msg['error']}'));
        } else {
          c?.complete(msg['result']);
        }
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
  Future<void> waitForFlutterRender() =>
      _pollThenSettle("!!document.querySelector('flutter-view, flt-glass-pane')",
          const Duration(milliseconds: 2500));

  /// Wait until every <img> on a static page (design/store.html) has decoded.
  Future<void> waitForImages() => _pollThenSettle(
      'Array.from(document.images).every(im => im.complete && im.naturalWidth > 0)',
      const Duration(milliseconds: 400));

  Future<void> _pollThenSettle(String expression, Duration settle) async {
    for (var i = 0; i < 60; i++) {
      final r = await send('Runtime.evaluate',
          {'expression': expression, 'returnByValue': true});
      if (((r as Map)['result'] as Map)['value'] == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await Future<void>.delayed(settle);
  }

  Future<void> close() => _ws.close();
}
