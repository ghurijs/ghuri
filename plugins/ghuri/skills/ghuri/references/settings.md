# Settings

`src/settings.ts`: `defineSettings((env) => ({...}))`, INSTALLED_APPS, MIDDLEWARE, DATABASES / STORAGES / CACHES adapters, reading settings and env at runtime, the request context, system checks.

## The settings file

```ts
// src/settings.ts
import { AdminConfig } from '@ghuri/admin'
import {
  AuthConfig, AuthenticationMiddleware, AuthTokenConfig, ContentTypesConfig, SessionMiddleware, SessionsConfig,
} from '@ghuri/auth'
import { SessionAuthentication, TokenAuthentication } from '@ghuri/auth/rest'
import {
  CommonMiddleware, CsrfMiddleware, defineSettings, kvCache, memoryCache, SecurityMiddleware, XFrameOptionsMiddleware,
} from '@ghuri/core'
import { d1, postgres } from '@ghuri/orm'
import { IsAuthenticatedOrReadOnly, PageNumberPagination } from '@ghuri/rest'
import { r2 } from '@ghuri/storage'
import { BlogConfig } from './blog/app'
import { urlpatterns } from './urls'

export default defineSettings((env) => ({
  SECRET_KEY: env.SECRET_KEY,
  DEBUG: env.DEBUG === 'true',                  // env values are strings on Workers: convert explicitly
  ALLOWED_HOSTS: env.ALLOWED_HOSTS ? String(env.ALLOWED_HOSTS).split(',') : ['*'],
  INSTALLED_APPS: [ContentTypesConfig, AuthConfig, SessionsConfig, AuthTokenConfig, AdminConfig, BlogConfig],
  MIDDLEWARE: [
    SecurityMiddleware, CommonMiddleware, SessionMiddleware, CsrfMiddleware, AuthenticationMiddleware,
    XFrameOptionsMiddleware,
  ],
  ROOT_URLCONF: urlpatterns,                    // the array itself, not 'mysite.urls'
  DATABASES: { default: env.DATABASE_URL ? postgres({ url: env.DATABASE_URL }) : d1('DB') },
  STORAGES: { default: r2('MEDIA') },
  MEDIA_URL: '/media/',
  CACHES: { default: env.CACHE ? kvCache('CACHE') : memoryCache() },
  AUTH_USER_MODEL: 'auth.User',
  REST_FRAMEWORK: {
    DEFAULT_AUTHENTICATION_CLASSES: [SessionAuthentication, TokenAuthentication],
    DEFAULT_PERMISSION_CLASSES: [IsAuthenticatedOrReadOnly],
    DEFAULT_PAGINATION_CLASS: PageNumberPagination,
    PAGE_SIZE: 20,
  },
  TIME_ZONE: 'UTC',
}))
```

Rules:
- Keys are `UPPER_SNAKE` (Django names); option objects passed to adapters/classes are camelCase.
- Values Django takes as dotted strings (`ROOT_URLCONF`, `INSTALLED_APPS`, `MIDDLEWARE`, backends, auth/permission classes) are imported values. Exception: `AUTH_USER_MODEL` is the string `'app_label.Model'`.
- `env` holds Worker vars, secrets and bindings (Cloudflare) or `process.env` (Node). Adapters take binding NAMES (`d1('DB')`, `r2('MEDIA')`, `kvCache('CACHE')`), so the same file runs on Workers and Node. For different environments branch on `env` inside the function; there is no `DJANGO_SETTINGS_MODULE` and no per-environment settings module.
- The CLI finds the file via `"ghuri": { "settings": "src/settings.ts" }` in `package.json` (fallback `src/settings.ts`, or `--settings <path>`).
- `INSTALLED_APPS` order matters: `ContentTypesConfig` before `AuthConfig` (AuthConfig refuses to start otherwise).
- `SECRET_KEY` is required unless `DEBUG`. Locally it lives in `.dev.vars` (git-ignored); in production `npx wrangler secret put SECRET_KEY` or an env var.

## Core keys (`@ghuri/core`)

| Key | Default | Notes |
|---|---|---|
| `SECRET_KEY` | required | also `SECRET_KEY_FALLBACKS` (auth) for rotation |
| `DEBUG` | `false` | error pages, startup checks |
| `ALLOWED_HOSTS` | `['*']` | `.example.com` matches subdomains |
| `INSTALLED_APPS` | required | `AppConfig` classes (or instances) |
| `MIDDLEWARE` | `[]` | classes, configured instances, or plain Hono middleware; outermost first |
| `ROOT_URLCONF` | required | pattern array |
| `APPEND_SLASH` / `PREPEND_WWW` | `true` / `false` | |
| `TIME_ZONE` / `USE_TZ` | `'UTC'` / `true` | |
| `CACHES` | `{ default: memoryCache() }` | `memoryCache()`, `kvCache(binding)`, `cfCache()` |
| `CORS` | `false` | `{ allowOrigins, allowCredentials?, allowMethods?, allowHeaders?, exposeHeaders?, maxAge? }` used by `CorsMiddleware` |
| `API_PATH_PREFIXES` | `['/api']` | errors under these paths render as JSON |
| `SILENCED_SYSTEM_CHECKS` | `[]` | e.g. `['security.W004']` |
| `SECURE_*`, `X_FRAME_OPTIONS`, `USE_X_FORWARDED_HOST` | Django defaults | read by `SecurityMiddleware` / `XFrameOptionsMiddleware` |
| `CSRF_TRUSTED_ORIGINS`, `CSRF_COOKIE_*`, `CSRF_HEADER_NAME` | Django defaults | header default `X-CSRFToken` |

Built-in core middleware: `SecurityMiddleware`, `CommonMiddleware`, `CsrfMiddleware`, `XFrameOptionsMiddleware`, `CorsMiddleware`, `GZipMiddleware`. Session/auth middleware come from `@ghuri/auth` (`SessionMiddleware`, `AuthenticationMiddleware`).

## Databases (`@ghuri/orm`)

| Factory | Import | Runtime |
|---|---|---|
| `d1('DB')` | `@ghuri/orm` | Workers (and the CLI through wrangler). SQLite dialect, no rollback in `atomic()` |
| `postgres({ url, hyperdrive?, max?, driverOptions? })` | `@ghuri/orm` | Node and Workers; `postgres({ hyperdrive: 'HYPERDRIVE' })` on Workers |
| `sqlite({ filename, wal?, options? })` | `@ghuri/orm/sqlite` | Node only (better-sqlite3) |
| `pglite({ dataDir? })` | `@ghuri/orm/pglite` | Node only (embedded Postgres; tests, local dev) |

Several aliases are allowed (`DATABASES: { default: d1('DB'), pg: postgres({ url: env.DATABASE_URL }) }`) and used with `.using('pg')` / `--database pg`. There are no database routers. Never import `@ghuri/orm/sqlite`, `@ghuri/orm/pglite` or `@ghuri/storage/fs` statically into code bundled for Workers unless you know the bundle tolerates it; the blog example loads PGlite lazily with a non-literal dynamic import.

## Other packages' keys (see their reference files)

| Key | Package | File |
|---|---|---|
| `AUTH_USER_MODEL`, `AUTHENTICATION_BACKENDS`, `PASSWORD_HASHERS`, `AUTH_PASSWORD_VALIDATORS`, `LOGIN_URL`, `SESSION_*`, `JWT` (alias `SIMPLE_JWT`) | `@ghuri/auth` | auth.md |
| `REST_FRAMEWORK` | `@ghuri/rest` | rest.md |
| `STORAGES`, `MEDIA_URL`, `DELETE_FILES_ON_MODEL_DELETE` | `@ghuri/storage` | storage.md |
| `GRAPHQL` | `@ghuri/graphql` | graphql.md |
| `REALTIME` | `@ghuri/realtime` | realtime.md |
| `AGENTS` | `@ghuri/agents` | agents.md |
| `ADMIN_ASSETS` | `@ghuri/admin` | admin.md |

## Reading settings and env at runtime

```ts
import { getContext, getEnv, getSettings, setting, settingsFor, tryGetContext } from '@ghuri/core'
import type { Context } from 'hono'

export function handler(c: Context) {
  const debug = getSettings().DEBUG
  const perPage = setting('BLOG_POSTS_PER_PAGE', 20)        // getattr(settings, 'X', default)
  const ai = getEnv().AI                                     // raw binding no adapter wraps (e.g. Workers AI)
  getContext().executionCtx?.waitUntil(Promise.resolve())    // work after the response (Workers)
  const maybe = tryGetContext()?.settings                    // undefined outside a context
  return c.json({ debug, perPage, hasAi: Boolean(ai), maybe: Boolean(maybe), viaHono: Boolean(settingsFor(c)) })
}
```

- `getSettings()` / `setting()` need a Ghuri context: inside a request, cron/queue handler, management command, or a test after `app.setup(env)`. Calling them at module top level throws `ImproperlyConfigured` (on Workers there is no env until the first request). Read settings inside functions, never at import time.
- Prefer adapters (`DATABASES`, `STORAGES`, `CACHES`) to `getEnv().DB` etc. Code that touches `env.DB` / `env.MEDIA` directly breaks the move to Postgres/S3.

Declare custom keys for type checking:

```ts
declare module '@ghuri/core' {
  interface GhuriSettings {
    BLOG_POSTS_PER_PAGE?: number
  }
}
```

## System checks

```ts
import { checks } from '@ghuri/core'

checks.register(
  ({ settings }) =>
    settings.BLOG_POSTS_PER_PAGE === 0 ? [checks.error('BLOG_POSTS_PER_PAGE must be positive.', { id: 'blog.E001' })] : [],
  { tags: ['blog'] },
)
```

Register from `AppConfig.ready()`. Run with `npx ghuri check` / `npx ghuri check --deploy`. Checks also run at startup with `DEBUG` (skip with `createApp(settings, { checks: false })`). `npx ghuri diffsettings` shows non-default settings.

## Entry points

```ts
// src/index.ts (Workers: fetch, scheduled and queue handlers)
import { createApp } from '@ghuri/core'
import settings from './settings'

export default createApp(settings)
```

```ts
// src/server.ts (Node / VPS / Docker)
import { createApp } from '@ghuri/core'
import { serve } from '@ghuri/core/node'
import settings from './settings'

serve(createApp(settings), { port: Number(process.env.PORT ?? 8000), env: process.env })
```

## Gotchas

- Writing `settings.py`-style top-level constants or reading `process.env` at import time: export `defineSettings((env) => ({...}))` and read from `env`.
- Dotted strings for `INSTALLED_APPS: ['blog']`, `ROOT_URLCONF: 'mysite.urls'`, `MIDDLEWARE: ['django.middleware...']`, `DEFAULT_PERMISSION_CLASSES: ['rest_framework.permissions.IsAuthenticated']`: import the classes.
- `DATABASES = {'default': {'ENGINE': ..., 'NAME': ...}}`: use `d1('DB')` / `postgres({ url })`.
- `DEBUG: env.DEBUG` (a truthy string `'false'`): write `env.DEBUG === 'true'`; `Number(env.X)` for numbers.
- `from django.conf import settings` at module scope: call `getSettings()` inside the function that needs it.
- Forgetting `nodejs_compat` in `wrangler.jsonc` (the request context uses `AsyncLocalStorage`).
- Adding an app module but not its `AppConfig` to `INSTALLED_APPS` (models get no app label, no migrations, no admin, no commands).
