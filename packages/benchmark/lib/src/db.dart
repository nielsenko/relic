import 'dart:io';

import 'package:postgres/postgres.dart';

/// The pool behind the /db route, 10 connections per isolate, as in the
/// reproduction of relic issue 445.
///
/// It connects on the first query, so a server that never serves /db
/// needs no database. RELIC_BENCH_PG_HOST, RELIC_BENCH_PG_PORT,
/// RELIC_BENCH_PG_DATABASE, RELIC_BENCH_PG_USER and
/// RELIC_BENCH_PG_PASSWORD name the server, a local postgres with
/// password postgres by default.
final Pool<void> dbPool = Pool.withEndpoints(
  [
    Endpoint(
      host: _env('HOST', '127.0.0.1'),
      port: int.parse(_env('PORT', '5432')),
      database: _env('DATABASE', 'postgres'),
      username: _env('USER', 'postgres'),
      password: _env('PASSWORD', 'postgres'),
    ),
  ],
  settings: const PoolSettings(
    maxConnectionCount: 10,
    sslMode: SslMode.disable,
  ),
);

/// Runs `SELECT 1` on [dbPool].
Future<void> selectOne() => dbPool.execute('SELECT 1');

String _env(String name, String fallback) =>
    Platform.environment['RELIC_BENCH_PG_$name'] ?? fallback;
