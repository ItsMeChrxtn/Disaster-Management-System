<?php
namespace App\Core;

final class Router
{
    private array $routes = [];
    private array $globalMiddleware = [];
    public function use(callable $middleware): void { $this->globalMiddleware[]=$middleware; }
    public function add(string $method, string $path, callable|array $handler, array $middleware = []): void {
        $this->routes[] = compact('method', 'path', 'handler', 'middleware');
    }
    public function get(string $path, callable|array $handler, array $middleware = []): void { $this->add('GET', $path, $handler, $middleware); }
    public function post(string $path, callable|array $handler, array $middleware = []): void { $this->add('POST', $path, $handler, $middleware); }
    public function put(string $path, callable|array $handler, array $middleware = []): void { $this->add('PUT', $path, $handler, $middleware); }
    public function delete(string $path, callable|array $handler, array $middleware = []): void { $this->add('DELETE', $path, $handler, $middleware); }
    public function dispatch(Request $request): never {
        foreach ($this->globalMiddleware as $middleware) $middleware($request);
        foreach ($this->routes as $route) {
            $regex = '#^' . preg_replace('/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/', '(?P<$1>[^/]+)', $route['path']) . '$#';
            if ($route['method'] !== $request->method() || !preg_match($regex, $request->path(), $matches)) continue;
            $request->params = array_filter($matches, 'is_string', ARRAY_FILTER_USE_KEY);
            foreach ($route['middleware'] as $middleware) $middleware($request);
            $handler = $route['handler'];
            if (is_array($handler)) $handler = [new $handler[0](), $handler[1]];
            $handler($request);
            Response::error('No response returned', 500);
        }
        Response::error('Route not found', 404);
    }
}
