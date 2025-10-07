## Problem to Solve

When configuring routes in Relic, there's no way to specify a fallback handler for requests that don't match any defined routes. This becomes problematic when you need to:
1. Define specific route overrides (e.g., `/assets/packages/assets/json/config.json`)
2. Have all other unmatched requests handled by a catch-all handler (e.g., SPA serving)

Currently, the router doesn't backtrack by design, so once it matches a path prefix like `/assets/`, it won't fall back to a `/**` wildcard route if no exact match is found. This results in 404 errors for files that should be served by the catch-all handler.

## Proposal

Add a `Router.fallback()` method (or similar API) that allows developers to specify a fallback handler for requests that don't match any routes in the router. This would be exposed in the public API and integrate with the existing Pipeline/middleware pattern.

Example using Pipeline directly:

```dart
final handler = const Pipeline()
  .addMiddleware(routeWith(router))
  .addHandler(fallbackHandler); // Handles unmatched requests
```

This would allow proper handling of the "anything not matched by router" case without requiring backtracking, maintaining the current performance guarantees.

## Use Case

A common scenario is serving a Single Page Application (SPA) with specific file overrides:

```dart
// Specific override for dynamic configuration
pod.webServer.addRoute(
  AppConfigRoute(serverConfig: pod.config.apiServer),
  '/assets/packages/assets/json/config.json',
);

// Fallback handler for all other requests
pod.webServer.addRoute(
  RouteSinglePageApp(serverDirectory: 'app', basePath: '/'),
  Router.fallback(), // or similar API
);
```

This enables serving dynamically generated configuration files in production while allowing all other assets and SPA routes to be handled by the fallback handler. This is particularly useful for containerized applications where you want to use the same container across multiple environments with different API URLs.

Real-world example: An application needs to override a specific config file (`/assets/packages/assets/json/config.json`) to dynamically inject the API URL at runtime, while all other files under `/assets/` (like `/assets/packages/assets/logo/logo-vertical-light.svg`) should be served as static files. Without a fallback mechanism, these other files return 404 errors.

## Alternatives

1. **Backtracking router**: Implement backtracking so the router tries other routes if no match is found. However, this sacrifices the current performance guarantees.

2. **Workaround with manual route configuration**: Define explicit routes for all paths that need handling:

```dart
pod.webServer.addRoute(
  AppConfigRoute(serverConfig: pod.config.apiServer),
  '/assets/packages/assets/json/config.json',
);

pod.webServer.addRoute(
  RouteStaticDirectory(serverDirectory: 'app/assets'),
  '/assets/**',
);

pod.webServer.addRoute(
  RouteSinglePageApp(serverDirectory: 'app', basePath: '/'),
  '/**',
);
```

This works but is convoluted and error-prone, requiring developers to manually manage all path hierarchies.

3. **Direct Pipeline usage**: Use Pipeline directly with custom middleware, but this isn't currently exposed in Serverpod's public API.

## Additional context

- This feature has already been implemented (as evidenced by recent commits using `Router.fallback`)
- This is a retrospective issue to document the feature request that led to the implementation
- The community (Alexander, Viktor) suggested this should be well-documented with examples, as it's likely a common use case and potential source of confusion
- Tests exist at: `test/router/path_trie_tail_test.dart:108`
- The original issue was discovered when debugging route lookups that returned null for paths that should have matched the `/**` wildcard
