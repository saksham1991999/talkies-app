import 'package:talkies/net/api.dart';

typedef Route = Object? Function(Map<String, String>? query, Object? body);

/// An [Api] that answers from a table of routes (`GET /v1/friends`), and records every call. A route throws
/// an [ApiException] to fail. A path with no route is a 404.
class FakeApi implements Api {
  final routes = <String, Route>{};
  final calls = <String>[];
  final queries = <Map<String, String>?>[];
  final bodies = <Object?>[];

  int count(String key) => calls.where((c) => c == key).length;

  Object? _handle(String method, String path, Map<String, String>? query, Object? body) {
    calls.add('$method $path');
    queries.add(query);
    bodies.add(body);
    final route = routes['$method $path'];
    if (route == null) throw const ApiError(404, 'not_found', 'no route');
    return route(query, body);
  }

  @override
  Future<Object?> get(String path, {Map<String, String>? query}) async => _handle('GET', path, query, null);
  @override
  Future<Object?> post(String path, {Object? body}) async => _handle('POST', path, null, body);
  @override
  Future<Object?> put(String path, {Object? body}) async => _handle('PUT', path, null, body);
  @override
  Future<Object?> patch(String path, {Object? body}) async => _handle('PATCH', path, null, body);
  @override
  Future<Object?> delete(String path) async => _handle('DELETE', path, null, null);
}
