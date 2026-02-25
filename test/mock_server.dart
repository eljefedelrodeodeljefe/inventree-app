import "dart:async";
import "dart:convert";
import "dart:io";

/// A recorded HTTP request captured by the mock server.
class RecordedRequest {
  RecordedRequest({required this.method, required this.path, this.body});

  final String method;
  final String path;
  final Map<String, dynamic>? body;

  @override
  String toString() => "$method $path${body != null ? " $body" : ""}";
}

/// A canned response to return for a matched route.
class _RouteResponse {
  _RouteResponse({
    required this.method,
    required this.pathPattern,
    required this.statusCode,
    required this.body,
  });

  final String method;
  final RegExp pathPattern;
  final int statusCode;
  final dynamic body; // Map or List
}

/// A lightweight mock HTTP server for testing InvenTreeAPI calls.
///
/// Binds to 127.0.0.1 on a random port. Records every incoming request and
/// returns configurable responses per method+path pattern.
class MockInvenTreeServer {
  HttpServer? _server;
  final List<RecordedRequest> requests = [];
  final List<_RouteResponse> _routes = [];

  /// The port the server is listening on. Only valid after [start].
  int get port => _server?.port ?? 0;

  /// The base URL for this mock server, e.g. "http://127.0.0.1:12345/".
  String get baseUrl => "http://127.0.0.1:$port/";

  /// Start the mock server on a random port.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
  }

  /// Stop the mock server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Clear recorded requests and configured routes.
  void reset() {
    requests.clear();
    _routes.clear();
  }

  /// Register a canned response for requests matching [method] and [pathPattern].
  ///
  /// [pathPattern] is a regex string matched against the request URI path.
  /// Later registrations take priority (checked in reverse order).
  void respondTo(
    String method,
    String pathPattern, {
    int statusCode = 200,
    dynamic body = const <String, dynamic>{},
  }) {
    _routes.add(
      _RouteResponse(
        method: method.toUpperCase(),
        pathPattern: RegExp(pathPattern),
        statusCode: statusCode,
        body: body,
      ),
    );
  }

  /// Return all recorded requests matching [method] and [pathPattern].
  List<RecordedRequest> requestsTo(String method, String pathPattern) {
    final regex = RegExp(pathPattern);
    return requests.where((r) {
      return r.method == method.toUpperCase() && regex.hasMatch(r.path);
    }).toList();
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final String path = req.uri.path;
    final String method = req.method.toUpperCase();

    // Read request body
    Map<String, dynamic>? body;
    try {
      final bodyStr = await utf8.decoder.bind(req).join();
      if (bodyStr.isNotEmpty) {
        body = json.decode(bodyStr) as Map<String, dynamic>;
      }
    } catch (_) {
      // Ignore body parse errors (e.g. multipart uploads)
    }

    requests.add(RecordedRequest(method: method, path: path, body: body));

    // Find a matching route (last registered wins)
    _RouteResponse? matched;
    for (int i = _routes.length - 1; i >= 0; i--) {
      final route = _routes[i];
      if (route.method == method && route.pathPattern.hasMatch(path)) {
        matched = route;
        break;
      }
    }

    final statusCode = matched?.statusCode ?? 200;
    final responseBody = matched?.body ?? <String, dynamic>{};

    req.response.statusCode = statusCode;
    req.response.headers.contentType = ContentType.json;
    req.response.write(json.encode(responseBody));
    await req.response.close();
  }
}
