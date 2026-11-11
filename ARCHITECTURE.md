# Ghuri — Architecture & Package Contracts

> Ghuri is Django for TypeScript: class-based, app-structured, batteries included.
> Default stack: **Cloudflare Workers + Hono + Drizzle + D1 + R2**.
> Portable: the same project code runs on **Postgres / SQLite / Node / any VPS** by changing settings only.

This document is the source of truth every package is built against. When a package needs
something from another package, it uses **only** the contracts written here. If a contract is
missing, add it here first (and note it in the PR/commit), then implement.

---

## 1. Goals and non-goals

**Goals**

1. A Django developer should feel at home within an hour: `settings`, `INSTALLED_APPS`,
   `urls.ts` with `path()`/`include()`, `Model` classes with `objects` managers, migrations,
   `admin.site.register`, DRF-style serializers/viewsets/routers, `createsuperuser`.
2. Cloudflare first: zero-config D1 + R2 + KV, runs in `wrangler dev`, deploys with `wrangler deploy`.
3. Portability is a feature: no app code may touch `env.DB`, `env.BUCKET` directly. Databases,
   storage, cache and runtime sit behind adapters chosen in settings. Moving to Postgres is:
   change `DATABASES`, run `ghuri migrate`, run `ghuri dumpdata | ghuri loaddata`.
4. REST-first: every model can be exposed as a typed REST API with OpenAPI in a few lines.
5. Agent-ready: models and viewsets can be exposed as AI-agent tools and over MCP.
6. TypeScript-native: strict types, inferred model field types, ESM only.

**Non-goals (for 0.1)**: Django templates language (we use Hono JSX), i18n beyond plumbing,
GIS, multiple-database routing beyond aliases, raw sync APIs (everything DB-related is async).

---

## 2. Repositories and packages

One GitHub repo per package under `github.com/ghurijs`. npm scope `@ghuri`. All packages start at
`0.1.0-alpha.0` and publish with dist-tag `next`.

| Repo (`ghurijs/…`) | npm | Purpose | Depends on (peer) |
|---|---|---|---|
| `ghuri` | — (private) | Meta repo: this spec, roadmap, dev workspace, bootstrap script | — |
| `core` | `@ghuri/core` | settings, app registry, URLs, views, middleware, request context, signals, cache, commands base, testing client, Node adapter | `hono` |
| `orm` | `@ghuri/orm` | Model, fields, managers/QuerySets, relations, DB adapters (D1, Postgres, SQLite, PGlite), migrations + schema editor, ORM commands | `@ghuri/core`, `drizzle-orm` |
| `auth` | `@ghuri/auth` | User/Group/Permission, password hashers, sessions, tokens, JWT, auth middleware, REST auth classes, `createsuperuser` | core, orm, (optional) rest |
| `rest` | `@ghuri/rest` | Serializers, APIView, generics, ViewSets, Routers, permissions, pagination, filters, throttling, OpenAPI, browsable docs | core, orm |
| `storage` | `@ghuri/storage` | Storage API, R2 / S3 / filesystem / memory backends, `FileField`/`ImageField` | core, orm |
| `admin` | `@ghuri/admin` | Django-admin clone (SSR with Hono JSX + htmx) | core, orm, auth, (optional) storage |
| `agents` | `@ghuri/agents` | Agent classes, model/viewset tools, conversation memory, MCP server | core, orm, rest, `ai` |
| `cli` | `@ghuri/cli` | `ghuri` binary (`startproject`, `startapp`, `runserver`, `migrate`, …) | core, orm |
| `create-ghuri` | `create-ghuri` | `npm create ghuri@latest` → runs `startproject` | — |
| `docs` | — | Starlight docs site | — |
| `examples` | — | Example projects (blog API + admin) used as end-to-end tests | all |

Framework packages that keep global state (app registry, AsyncLocalStorage, model registry)
**must list `@ghuri/*` siblings as `peerDependencies`** (plus `devDependencies` for local dev)
so an application only ever has one copy.

### Local development workspace

The meta repo root is an npm workspace. Each package repo is cloned into `packages/<repo>`
(git-ignored by the meta repo); examples into `examples/`. `scripts/bootstrap.sh` clones all repos.
Sibling dependency ranges are `^0.1.0-alpha.0`, which npm workspaces resolve to the local clone.

---

## 3. Conventions (all packages)

- ESM only, `"type": "module"`, TypeScript `~5.9`, `strict: true`, target ES2022, `moduleResolution: bundler`.
- Build with `tsup` (esm + d.ts) to `dist/`. Subpath exports declared in `package.json#exports`.
- Tests: `vitest` (Node). DB tests run on SQLite (better-sqlite3), PGlite (Postgres dialect) and
  D1 (Miniflare) where relevant. Lint/format: Biome (root `biome.json`).
- Must run on Workers with `compatibility_flags: ["nodejs_compat"]`. Never import Node-only
  modules (`fs`, `path`, `better-sqlite3`, `pg`) from a package's main entry; put them behind a
  subpath (`@ghuri/orm/sqlite`, `@ghuri/core/node`, `@ghuri/storage/fs`) or dynamic import.
  `node:async_hooks` (AsyncLocalStorage) and `node:crypto`-free WebCrypto are allowed.
- Naming: classes `PascalCase`, options and fields `camelCase` (Django `max_length` → `maxLength`),
  settings keys stay `UPPER_SNAKE` like Django. DB columns are `snake_case` (auto-derived).
- Errors: every package exports its own error classes extending `GhuriError` from core.
- Public API is what is exported from `src/index.ts` (and declared subpaths). Everything else is internal.
- Each package has a README with a quick start, and a `CHANGELOG.md`.
- Commit messages: Conventional Commits (`feat(orm): …`).

---

## 4. `@ghuri/core`

### 4.1 Settings

```ts
// src/settings.ts (project)
import { defineSettings } from '@ghuri/core'
import { d1, postgres } from '@ghuri/orm'
import { r2 } from '@ghuri/storage'
import { AuthConfig } from '@ghuri/auth'
import { AdminConfig } from '@ghuri/admin'
import { BlogConfig } from './blog/app'
import { urlpatterns } from './urls'

export default defineSettings((env) => ({
  SECRET_KEY: env.SECRET_KEY,
  DEBUG: env.DEBUG === 'true',
  ALLOWED_HOSTS: ['*'],
  INSTALLED_APPS: [AuthConfig, AdminConfig, BlogConfig],
  MIDDLEWARE: [SecurityMiddleware, SessionMiddleware, CsrfMiddleware, AuthenticationMiddleware],
  ROOT_URLCONF: urlpatterns,
  DATABASES: { default: env.DATABASE_URL ? postgres({ url: env.DATABASE_URL }) : d1('DB') },
  STORAGES: { default: r2('MEDIA') },
  CACHES: { default: kvCache('CACHE') },
  AUTH_USER_MODEL: 'auth.User',
}))
```

```ts
export interface GhuriSettings {           // augmented by other packages via declaration merging
  SECRET_KEY: string
  DEBUG?: boolean
  ALLOWED_HOSTS?: string[]
  INSTALLED_APPS: Array<AppConfigClass | AppConfig>
  MIDDLEWARE?: Array<MiddlewareClass | MiddlewareHandler>
  ROOT_URLCONF: UrlPatterns
  APPEND_SLASH?: boolean                     // default true
  TIME_ZONE?: string; USE_TZ?: boolean      // default 'UTC', true
  CACHES?: Record<string, CacheConfig>
  CSRF_TRUSTED_ORIGINS?: string[]
  CORS?: { allowOrigins: string[] | '*'; allowCredentials?: boolean } | false
  [key: string]: unknown
}
// other packages add their keys:
declare module '@ghuri/core' { interface GhuriSettings { DATABASES: Record<string, DatabaseConfig> } }

export type Env = Record<string, any>
export interface SettingsFactory { (env: Env): GhuriSettings; readonly __ghuriSettings: true }
export function defineSettings(fn: (env: Env) => GhuriSettings): SettingsFactory
export function getSettings(): GhuriSettings        // from current context; throws ImproperlyConfigured
```
Settings are resolved once per `env` object (WeakMap cache) and validated (`checks`).

### 4.2 Request context (AsyncLocalStorage)

```ts
export interface GhuriContext {
  env: Env
  settings: GhuriSettings
  executionCtx?: { waitUntil(p: Promise<unknown>): void; passThroughOnException?(): void }
  request?: Request
  hono?: import('hono').Context
  state: Map<string | symbol, unknown>   // per-request cache: DB connections, user, etc.
}
export function getContext(): GhuriContext          // throws if none
export function tryGetContext(): GhuriContext | undefined
export function runWithContext<T>(ctx: GhuriContext, fn: () => T): T
export function setGlobalContext(ctx: GhuriContext | undefined): void // fallback for CLI/tests/scripts
export function getEnv(): Env
```
`state` is how packages cache per-request things (`orm` stores connections under a symbol).

### 4.3 Apps

```ts
export abstract class AppConfig {
  abstract name: string                 // e.g. 'blog' — also the default label
  label?: string                        // unique app label; defaults to name
  verboseName?: string
  path?: string                         // set to import.meta.dirname; used by CLI only (migrations dir)
  models?: Record<string, unknown> | unknown[]   // `import * as models from './models'`
  migrations?: Record<string, unknown>  // `import * as migrations from './migrations'` (index generated by makemigrations)
  admin?: unknown                       // `import * as admin from './admin'` — importing registers ModelAdmins
  commands?: Record<string, CommandClass>
  ready?(): void | Promise<void>
}
export type AppConfigClass = new () => AppConfig

export const apps: {
  populate(installed: Array<AppConfigClass | AppConfig>): Promise<void> // idempotent per isolate
  readonly ready: boolean
  getAppConfigs(): AppConfig[]
  getAppConfig(label: string): AppConfig
  isInstalled(label: string): boolean
  // model registry is filled by @ghuri/orm through these hooks:
  registerModel(appLabel: string, model: unknown): void
  getModels(): unknown[]
  getModel(dotted: string): unknown          // 'blog.Post' (case-insensitive model name)
  onPopulate(hook: (apps) => void | Promise<void>): void  // packages hook in (orm assigns app labels)
}
```
`populate` iterates `INSTALLED_APPS`, instantiates configs, walks each config's `models`
values and calls `onPopulate` hooks (the ORM registers every value that is a Model class with the
config's label), then calls `ready()` on every config in order.

### 4.4 URLs and views

```ts
import { path, include, rePath } from '@ghuri/core'
export const urlpatterns: UrlPatterns = [
  path('', homeView, { name: 'home' }),
  path('admin/', admin.site.urls),                    // UrlPatterns from other packages
  path('api/', include(router.urls)),
  path('blog/', include(blogUrls, { namespace: 'blog' })),
  path('posts/<int:id>/', PostDetailView.asView(), { name: 'post-detail' }),
  path('legacy/', someHonoApp),                       // escape hatch: mount any Hono app
]
```
- Converters: `<int:x>` `<str:x>` (default) `<slug:x>` `<uuid:x>` `<path:x>`, compiled to Hono
  route patterns (`/posts/:id{[0-9]+}/`). Typed params available via `c.req.param()`; `int` values
  are also exposed parsed via `kwargs(c)`.
- `APPEND_SLASH` (default true): GET request to `/x` that 404s but `/x/` matches → 301.
- `reverse(name: string, params?: Record<string, string|number>): string` supports namespaces
  (`'blog:post-detail'`). `include(patterns, { namespace })` or patterns exporting `appName`.
- A **view** is `(c: Context) => Response | Promise<Response>` (Hono `Context`).
- Class-based views: `abstract class View { static asView(initkwargs?): ViewFunction; dispatch(c);
  get?/post?/put?/patch?/delete?/head?/options?(c) }` — 405 with `Allow` header for missing methods.
  Also `TemplateView` (JSX render), `RedirectView`.
- Shortcuts: `json(c, data, status?)`, `redirect(c, toNameOrUrl, params?)`, `getObjectOr404(qs, lookup)` (lives in orm),
  `Http404`, `PermissionDenied`, `BadRequest`, `SuspiciousOperation` error classes → mapped to responses
  (JSON for `Accept: application/json` / `/api`, HTML otherwise; DEBUG shows stack).

```ts
export type UrlPatterns = UrlEntry[]
export interface UrlEntry { route: string; view?: ViewFunction; app?: import('hono').Hono;
  children?: UrlPatterns; name?: string; namespace?: string; methods?: string[] }
```

### 4.5 Middleware

```ts
export abstract class Middleware {
  // Django-style: wraps the rest of the chain
  abstract handle(c: Context, next: () => Promise<void>): Promise<Response | void>
}
export type MiddlewareClass = new () => Middleware
```
Built-ins in core: `SecurityMiddleware` (security headers, HSTS when https), `CommonMiddleware`
(APPEND_SLASH, ALLOWED_HOSTS), `CorsMiddleware`, `CsrfMiddleware` (Origin/Referer check against host
and `CSRF_TRUSTED_ORIGINS` + double-submit token cookie `csrftoken` / header `X-CSRFToken` / form
field `csrfmiddlewaretoken`; exempt views via `csrfExempt(view)`; helper `getCsrfToken(c)`),
`GZipMiddleware` (no-op on Workers). Session/Authentication middlewares live in `@ghuri/auth`.

### 4.6 Application entry

```ts
// src/index.ts (project) — Worker entry (the "wsgi.py")
import { createApp } from '@ghuri/core'
import settings from './settings'
export default createApp(settings)

// src/server.ts — Node / VPS entry
import { serve } from '@ghuri/core/node'
serve(createApp(settings), { port: 8000, env: process.env })
```
```ts
export interface GhuriApp {
  fetch(request: Request, env: Env, ctx?: ExecutionContext): Promise<Response>
  scheduled?(event, env, ctx): Promise<void>       // dispatches to registered cron handlers
  queue?(batch, env, ctx): Promise<void>
  setup(env: Env): Promise<GhuriContext>             // populate apps without a request (CLI/tests)
  hono(env: Env): Promise<Hono>                      // built router (for testing / composition)
}
export function createApp(settings: SettingsFactory, options?: { hono?: (app: Hono) => void }): GhuriApp
```
Per isolate on first request: resolve settings → `apps.populate` → build Hono app (middleware in
order, then URL patterns, then error handler). Every request runs inside `runWithContext`.
`c.set('ghuri', ctx)` is also available on the Hono context.

### 4.7 Signals

```ts
export class Signal<A = Record<string, unknown>> {
  connect(receiver: (args: A & { sender: unknown }) => void | Promise<void>, opts?: { sender?: unknown; uid?: string }): void
  disconnect(receiverOrUid): boolean
  send(sender: unknown, args: A): Promise<void>      // awaits receivers sequentially
}
export const requestStarted: Signal; export const requestFinished: Signal
```
ORM defines `preSave`, `postSave`, `preDelete`, `postDelete`, `m2mChanged` (exported from `@ghuri/orm`).

### 4.8 Cache

`caches.get(alias='default')` / `cache` (default) with `get/set(key, value, ttlSeconds?)/delete/getOrSet/has/clear?`.
Backends: `memoryCache()`, `kvCache(binding)` (Workers KV), `cfCache()` (Cache API). Config objects
have shape `{ backend: string; create(env): CacheBackend }` — same pattern as DB/storage configs.

### 4.9 Management commands

```ts
export abstract class BaseCommand {
  static help: string
  addArguments?(parser: ArgumentParser): void    // minimal parser: .argument(name, opts) / .option(flag, opts)
  abstract handle(args: Record<string, unknown>, io: CommandIO): Promise<void | number>
}
export interface CommandIO { stdout(msg: string): void; stderr(msg: string): void; style: { success, warning, error, notice }; prompt?(q: string, opts?: { password?: boolean }): Promise<string> }
export const commandRegistry: { register(name, cls), get(name), all() }
```
Commands come from: CLI built-ins, `@ghuri/orm` (`makemigrations`, `migrate`, `showmigrations`,
`sqlmigrate`, `dumpdata`, `loaddata`, `flush`, `dbshell`?), and each `AppConfig.commands`.

### 4.10 Errors & checks

`GhuriError`, `ImproperlyConfigured`, `ValidationError` (holds `{ field: string[] }` or `string[]`;
`ValidationError.messageDict`), `ObjectDoesNotExist`, `MultipleObjectsReturned`, `Http404`,
`PermissionDenied`, `BadRequest`, `SuspiciousOperation`.
`checks.register(fn)`; `runChecks()` used by `ghuri check` and at startup when `DEBUG`.

### 4.11 Testing

`@ghuri/core/testing`: `createTestClient(app, { env })` → `client.get/post/put/patch/delete(path, { json, form, headers })`
returning `Response` plus `.json()` helpers; keeps cookies between requests (sessions/CSRF);
`client.forceLogin(user)` (implemented via hook registered by auth).

### 4.12 Request user contract (used by rest/admin/agents without importing auth)

```ts
export interface RequestUser {
  pk: unknown; isAuthenticated: boolean; isAnonymous: boolean
  isActive?: boolean; isStaff?: boolean; isSuperuser?: boolean
  hasPerm(perm: string, obj?: unknown): Promise<boolean>
  hasModulePerms?(appLabel: string): Promise<boolean>
}
export function getUser(c?: Context): RequestUser     // AnonymousUser if none set
export function setUser(c: Context, user: RequestUser): void
declare module 'hono' { interface ContextVariableMap { user: RequestUser; ghuri: GhuriContext } }
```

---

## 5. `@ghuri/orm`

### 5.1 Defining models

```ts
import { Model, CharField, TextField, BooleanField, DateTimeField, ForeignKey, ManyToManyField, CASCADE, Manager } from '@ghuri/orm'
import { User } from '@ghuri/auth'

export class Tag extends Model({
  name: new CharField({ maxLength: 50, unique: true }),
}) { toString() { return this.name } }

export class Post extends Model({
  title: new CharField({ maxLength: 200 }),
  slug: new SlugField({ unique: true }),
  body: new TextField({ blank: true }),
  published: new BooleanField({ default: false }),
  author: new ForeignKey(() => User, { onDelete: CASCADE, relatedName: 'posts' }),
  tags: new ManyToManyField(() => Tag, { blank: true, relatedName: 'posts' }),
  createdAt: new DateTimeField({ autoNowAdd: true }),
  updatedAt: new DateTimeField({ autoNow: true }),
}) {
  static Meta = { ordering: ['-createdAt'], verboseNamePlural: 'posts', indexes: [{ fields: ['slug'] }] }
  declare static objects: Manager<Post>          // optional: types results as Post (custom methods)
  toString() { return this.title }
}
```
- `Model(fields)` returns an abstract-ish base class whose instances have typed properties inferred
  from the fields. `BaseModel` is the real root class (use for `instanceof`).
- Implicit `id: new BigAutoField({ primaryKey: true })` unless a field has `primaryKey: true`.
- `static Meta`: `dbTable` (default `${appLabel}_${modelname lowercase}`), `ordering`, `verboseName`,
  `verboseNamePlural`, `uniqueTogether`, `indexes`, `constraints`, `abstract`, `permissions`,
  `defaultPermissions` (default `['add','change','delete','view']`), `getLatestBy`, `appLabel` (override).
- Abstract models: `Meta = { abstract: true }`; subclasses created with `Model({...}, { extends: Base })`
  or by spreading `Base.fields`. Swappable user model via `AUTH_USER_MODEL` and `getUserModel()` in auth.
- `Post._meta`: `{ appLabel, modelName, objectName, dbTable, pk: Field, fields: Field[], concreteFields,
  localFields, manyToMany: Field[], relatedObjects: RelatedObject[], getField(name), ordering,
  verboseName, verboseNamePlural, label ('blog.Post'), labelLower }`. Public & stable — admin, rest,
  agents, cli rely on it.

### 5.2 Fields

Classes (all extend `Field<T>`): `AutoField`, `BigAutoField`, `SmallAutoField`, `CharField`,
`TextField`, `SlugField`, `EmailField`, `URLField`, `UUIDField`, `GenericIPAddressField`,
`IntegerField`, `BigIntegerField`, `SmallIntegerField`, `PositiveIntegerField`,
`PositiveSmallIntegerField`, `FloatField`, `DecimalField` (string values; text in SQLite, numeric in PG),
`BooleanField`, `DateField` (`'YYYY-MM-DD'` string), `DateTimeField` (`Date`), `TimeField`,
`DurationField` (ms number), `JSONField`, `BinaryField`, `ForeignKey`, `OneToOneField`,
`ManyToManyField`. Storage adds `FileField`, `ImageField`.

Common options: `null`, `blank`, `default` (value or function), `choices`
(`[value, label][]` or enum object), `primaryKey`, `unique`, `dbIndex`, `dbColumn`, `editable`,
`helpText`, `verboseName`, `validators: Validator[]`, `errorMessages`, `dbDefault`.
Field-specific: `maxLength`, `maxDigits`/`decimalPlaces`, `autoNow`/`autoNowAdd`, relations:
`to: () => ModelClass | 'app.Model'`, `onDelete` (`CASCADE`, `PROTECT`, `RESTRICT`, `SET_NULL`, `SET_DEFAULT`,
`DO_NOTHING`), `relatedName`, `relatedQueryName`, `toField`, `through` (M2M), `limitChoicesTo`.

Field public API (consumed by rest/admin/agents/migrations):
```ts
abstract class Field<T = unknown> {
  name: string; attname: string; column: string; model: ModelClass
  readonly internalType: string            // 'CharField', 'ForeignKey', ...
  null: boolean; blank: boolean; primaryKey: boolean; unique: boolean; editable: boolean
  choices?: Array<[unknown, string]>; helpText?: string; verboseName: string; maxLength?: number
  isRelation: boolean; manyToOne?: boolean; oneToOne?: boolean; manyToMany?: boolean
  relatedModel?: ModelClass                 // resolved lazily
  hasDefault(): boolean; getDefault(): unknown
  toDb(value: T, dialect: Dialect): unknown; fromDb(value: unknown, dialect: Dialect): T
  toPython(value: unknown): T               // coerce from form/JSON input; throws ValidationError
  validate(value: T, instance: BaseModel): void   // runs built-in + custom validators
  deconstruct(): FieldDeconstruction        // JSON-able {type, options} used by migrations
  column(dialect): DrizzleColumnBuilder     // build drizzle column
  formHint(): { widget: 'text'|'textarea'|'number'|'checkbox'|'select'|'date'|'datetime'|'time'|'email'|'url'|'json'|'file'|'select-multiple'|'hidden'|'password'; [k: string]: unknown }
  jsonSchema(): Record<string, unknown>     // OpenAPI/JSON Schema fragment (used by rest + agents)
}
```
FK attname is `${name}Id` (column `${name}_id`). Instance: `post.authorId` (raw) and `post.author`
(see 5.4). Validators: `MinValueValidator`, `MaxValueValidator`, `MinLengthValidator`,
`MaxLengthValidator`, `RegexValidator`, `EmailValidator`, `URLValidator`, `validateSlug`.

### 5.3 Managers and QuerySets (all async, lazy, chainable, immutable)

```ts
Post.objects.all()
Post.objects.filter({ published: true, title__icontains: 'ghuri', author__username: 'bob' })
           .exclude({ createdAt__lt: cutoff }).orderBy('-createdAt', 'title')
           .selectRelated('author').prefetchRelated('tags').slice(0, 10)
await qs                       // QuerySet is thenable → T[]
for await (const p of qs) {}   // async iterable
await qs.get({ id: 1 })        // throws Post.DoesNotExist / Post.MultipleObjectsReturned
await qs.first(); await qs.last(); await qs.count(); await qs.exists()
await qs.values('id', 'title'); await qs.valuesList('id', { flat: true })
await qs.update({ published: true }); await qs.delete()          // returns counts
await Post.objects.create({ title, author: user })
await Post.objects.getOrCreate({ slug }, { defaults: { title } })  // [obj, created]
await Post.objects.updateOrCreate({ slug }, { defaults: {...} })
await Post.objects.bulkCreate([...]); await qs.inBulk([1,2,3])
await qs.aggregate({ total: Count('id'), avg: Avg('views') })
qs.annotate({ numComments: Count('comments') }).filter({ numComments__gt: 2 })
qs.filter(Q({ a: 1 }).or(Q({ b: 2 })).and(Q.not({ c: 3 })))
Post.objects.filter({ id: 1 }).update({ views: F('views').add(1) })
qs.distinct(); qs.only('id','title'); qs.defer('body'); qs.none(); qs.union(other) (optional)
```
Lookups: `exact`, `iexact`, `contains`, `icontains`, `in`, `gt`, `gte`, `lt`, `lte`, `startswith`,
`istartswith`, `endswith`, `iendswith`, `range`, `isnull`, `regex` (PG only; SQLite best-effort),
`date`, `year`, `month`, `day`. Spanning relations with `__` across FK, reverse FK, M2M.
Custom managers: `class PublishedManager extends Manager<Post> { getQueryset() { return super.getQueryset().filter({ published: true }) } }`
attached as `static published = new PublishedManager()`.

Typing: filter keys are `string` with autocompletion for direct field names; values `unknown`.
Results are typed instances.

### 5.4 Instances and relations

```ts
const p = new Post({ title: 'Hi', authorId: 1 }); await p.save(); await p.save({ updateFields: ['title'] })
await p.delete(); await p.refreshFromDb(); await p.fullClean()  // throws ValidationError{field: msgs}
p.pk; p.toJSON(); Post.fromRow(row)
// FK forward
p.authorId                     // raw id
await p.author                 // related instance (cached after first load or selectRelated); throws if not set
p.author = user                // sets authorId
// reverse FK / M2M managers
await user.posts.all(); await user.posts.filter({ published: true }).count()
await p.tags.add(tag1, tag2); await p.tags.remove(tag1); await p.tags.set([t]); await p.tags.clear(); await p.tags.all()
```
`ON DELETE` is emulated in the ORM (like Django) — not relying on DB FK actions — so behavior
is identical on D1, SQLite and Postgres. `PROTECT` raises `ProtectedError`.

### 5.5 Database adapters

```ts
export interface DatabaseConfig { vendor: 'd1' | 'postgresql' | 'sqlite' | 'pglite'; dialect: 'sqlite' | 'postgresql'; connect(env: Env): Promise<Connection> | Connection; options?: Record<string, unknown> }
export function d1(binding: string): DatabaseConfig                                   // main entry
export function postgres(opts: { url?: string; hyperdrive?: string; max?: number }): DatabaseConfig // main entry, uses `postgres` (postgres.js) via dynamic import; works on Workers via Hyperdrive or TCP
export function sqlite(opts: { filename: string }): DatabaseConfig                   // '@ghuri/orm/sqlite' (better-sqlite3, Node only)
export function pglite(opts?: { dataDir?: string }): DatabaseConfig                  // '@ghuri/orm/pglite' (tests/dev)

export interface Connection {
  alias: string; vendor: string; dialect: 'sqlite' | 'postgresql'
  drizzle: any                                 // the drizzle db instance (escape hatch)
  execute(sql: string, params?: unknown[]): Promise<{ rows: Record<string, unknown>[]; rowsAffected?: number; lastInsertId?: unknown }>
  batch?(statements: Array<{ sql: string; params?: unknown[] }>): Promise<void>
  transaction<T>(fn: (conn: Connection) => Promise<T>): Promise<T>
  supportsTransactions: boolean                // false for D1 (uses batch / best-effort)
  close(): Promise<void>
}
export const connections: { get(alias?: string): Promise<Connection>; closeAll(): Promise<void> }
export function atomic<T>(fn: () => Promise<T>, opts?: { using?: string }): Promise<T>  // nested savepoints where supported
export function getDrizzle(alias?: string): Promise<any>
Post.table(dialect?)            // the generated drizzle table object (escape hatch)
```
Connections are cached per request in `GhuriContext.state` (Workers forbid sharing I/O across
requests) and per process in Node/CLI. The `QuerySet` compiler builds queries with drizzle's
query builder / `sql` template so both dialects share one compiler with dialect hooks.
D1 caveat: no interactive transactions — `atomic()` runs the callback, collecting writes where
possible into `batch`; documented clearly.

### 5.6 Migrations (Django-style, dialect-neutral)

- Files: `src/<app>/migrations/0001_initial.ts` + generated `migrations/index.ts`.
```ts
import { Migration, operations as ops } from '@ghuri/orm/migrations'
export default new Migration({
  dependencies: [['auth', '0001_initial']],
  operations: [
    ops.CreateModel({ name: 'Post', fields: { id: { type: 'BigAutoField', primaryKey: true }, title: { type: 'CharField', maxLength: 200 }, author: { type: 'ForeignKey', to: 'auth.User', onDelete: 'CASCADE' } }, options: { ordering: ['-createdAt'] } }),
  ],
})
```
- Operations: `CreateModel`, `DeleteModel`, `RenameModel`, `AlterModelTable`, `AlterModelOptions`,
  `AddField`, `RemoveField`, `AlterField`, `RenameField`, `AddIndex`, `RemoveIndex`,
  `AddConstraint`, `RemoveConstraint`, `AlterUniqueTogether`, `RunSQL({ sqlite?, postgresql?, reverse? })`,
  `RunCode(async (apps, conn) => {})` (data migrations using historical models).
- `ProjectState` built by replaying operations; `autodetector` diffs it against current models →
  operations (with rename questions answered via CLI prompt or flags).
- `SchemaEditor` per dialect (`SqliteSchemaEditor` — uses table-rebuild for ALTER like Django;
  `PostgresSchemaEditor`) turns operations into SQL.
- `MigrationExecutor` applies/unapplies and records in table `ghuri_migrations(id, app, name, applied)`.
- Programmatic API used by CLI and tests: `makeMigrations(opts)`, `migrate(opts)`, `showMigrations()`,
  `sqlMigrate(app, name, dialect)`; `@ghuri/orm/commands` exports the BaseCommand classes.
- D1 remote: `ghuri migrate --remote` executes through wrangler's `getPlatformProxy` remote bindings;
  `ghuri sqlmigrate --all --dialect sqlite --out migrations-sql/` also emits wrangler-compatible SQL files.

### 5.7 Serialization / portability

`dumpdata` → JSON fixtures `[{ model: 'blog.post', pk: 1, fields: {...} }]` (Django-compatible shape);
`loaddata` inserts in dependency order, then resets PG sequences. This is the D1 → Postgres path.

### 5.8 Testing helpers

`@ghuri/orm/testing`: `setupTestDatabase({ using: 'sqlite' | 'pglite' | 'd1' })` creates a fresh DB,
runs migrations (or creates tables directly from models when no migrations exist), and returns
`{ teardown, flush }`.

---

## 6. `@ghuri/auth`

- `AuthConfig` app (label `auth`) with models `User` (AbstractUser fields: `username`, `email`,
  `firstName`, `lastName`, `password`, `isStaff`, `isActive`, `isSuperuser`, `lastLogin`, `dateJoined`,
  M2M `groups`, `userPermissions`), `Group`, `Permission` (`codename`, `name`, `contentType` → `ContentType`
  model with `appLabel`, `model`), `Session`, `Token`.
- `AbstractUser` / `AbstractBaseUser` field sets for custom user models; `getUserModel()` honors `AUTH_USER_MODEL`.
- Default permissions created post-migrate for every model (`add_post`, `change_post`, `delete_post`, `view_post`).
- Password hashing via WebCrypto: `PBKDF2PasswordHasher` (default, **Django-compatible format**
  `pbkdf2_sha256$<iter>$<salt>$<b64hash>` so Django users can migrate), plus `ScryptPasswordHasher`
  optional. `makePassword`, `checkPassword`, `user.setPassword`, `user.checkPassword`,
  `PASSWORD_HASHERS`, `AUTH_PASSWORD_VALIDATORS` (min length, common, numeric, similarity).
- `authenticate(c, credentials)`, `login(c, user)`, `logout(c)`; `AUTHENTICATION_BACKENDS` (`ModelBackend`).
- `SessionMiddleware` with `SESSION_ENGINE`: `db` (default), `kv`, `signedCookie`; `c.get('session')`.
- `AuthenticationMiddleware` sets `c.set('user', …)` (via core `setUser`).
- Decorators/helpers: `loginRequired(view)`, `permissionRequired(perm)(view)`, `staffMemberRequired`.
- Tokens: `Token` model (DRF authtoken style) and JWT (`hono/jwt` based) with refresh tokens.
- REST integration (`@ghuri/auth/rest`): `SessionAuthentication`, `TokenAuthentication`,
  `JWTAuthentication`, `BasicAuthentication`, plus views `obtainAuthToken`, `TokenObtainPairView`,
  `TokenRefreshView`.
- Commands: `createsuperuser`, `changepassword`. Admin integration: `UserAdmin`, `GroupAdmin` registered by admin package if auth installed.

---

## 7. `@ghuri/rest` (DRF clone)

```ts
class PostSerializer extends ModelSerializer<Post> {
  static Meta = { model: Post, fields: ['id', 'title', 'body', 'author', 'tags', 'createdAt'], readOnlyFields: ['author'] }
  authorName = new CharField({ source: 'author.username', readOnly: true })
  validateTitle(value: string) { if (value.includes('spam')) throw new ValidationError('No spam'); return value }
  validate(attrs) { return attrs }
}
class PostViewSet extends ModelViewSet<Post> {
  queryset = Post.objects.all()
  serializerClass = PostSerializer
  permissionClasses = [IsAuthenticatedOrReadOnly]
  filterBackends = [SearchFilter, OrderingFilter, FieldFilter]
  searchFields = ['title', 'body']; orderingFields = ['createdAt']; filtersetFields = ['published']
  async performCreate(serializer) { await serializer.save({ author: this.request.user }) }
  @action({ detail: true, methods: ['post'] }) async publish(c) { ... }
}
const router = new DefaultRouter()
router.register('posts', PostViewSet)   // → /posts/, /posts/<pk>/, /posts/<pk>/publish/
export const urlpatterns = [path('api/', include(router.urls))]
```
- Serializers: `Serializer`, `ModelSerializer`, `HyperlinkedModelSerializer` (optional), `ListSerializer`,
  nested serializers (read; writable nested via override), fields (`CharField`, `IntegerField`, `FloatField`,
  `DecimalField`, `BooleanField`, `DateTimeField`, `DateField`, `EmailField`, `URLField`, `UUIDField`,
  `ChoiceField`, `MultipleChoiceField`, `ListField`, `DictField`, `JSONField`, `FileField`, `ImageField`,
  `SerializerMethodField`, `PrimaryKeyRelatedField`, `SlugRelatedField`, `StringRelatedField`,
  `HiddenField`, `ReadOnlyField`), `isValid({ raiseException })`, `validatedData`, `errors`,
  `save()`, `create()`, `update()`, `data` (async: `await serializer.getData()` since relations are async —
  document: `data` is available after `await serializer.resolve()`; simplest API: `await serializer.toRepresentationAsync()`).
  Validators: `UniqueValidator`, `UniqueTogetherValidator`.
- Views: `APIView` (content negotiation JSON, parsers JSON/form/multipart, `request.data`, `request.query`,
  `request.user`), `GenericAPIView` (`getQueryset`, `getObject`, `getSerializer`, pagination, filters),
  mixins (`ListModelMixin`, `CreateModelMixin`, `RetrieveModelMixin`, `UpdateModelMixin`, `DestroyModelMixin`),
  concrete generics (`ListAPIView`, `ListCreateAPIView`, `RetrieveUpdateDestroyAPIView`, …),
  `ViewSet`, `GenericViewSet`, `ReadOnlyModelViewSet`, `ModelViewSet`, `@action`, function views via `apiView(['GET'])(fn)`.
  `Response`-like helper `new APIResponse(data, status)` or plain `Response`.
- Routers: `SimpleRouter`, `DefaultRouter` (adds API root view + `.json` format suffix optional).
- Permissions: `AllowAny`, `IsAuthenticated`, `IsAdminUser`, `IsAuthenticatedOrReadOnly`,
  `ModelPermissions`, `ModelPermissionsOrAnonReadOnly`, `ObjectPermissions`; composable with `and/or/not`.
- Authentication: `BaseAuthentication` interface (`authenticate(c): Promise<[RequestUser, token] | null>`,
  `authenticateHeader?`); concrete classes in `@ghuri/auth/rest`.
- Pagination: `PageNumberPagination`, `LimitOffsetPagination`, `CursorPagination`.
- Filtering: `SearchFilter`, `OrderingFilter`, `FieldFilter` (query params → ORM lookups, e.g. `?createdAt__gte=`).
- Throttling: `AnonRateThrottle`, `UserRateThrottle`, `ScopedRateThrottle` using core cache.
- Exceptions: `APIException`, `ValidationError`(rest), `NotFound`, `PermissionDenied`, `NotAuthenticated`,
  `AuthenticationFailed`, `MethodNotAllowed`, `Throttled`, `ParseError`; DRF error shapes.
- Settings key `REST_FRAMEWORK` with DRF names (`DEFAULT_AUTHENTICATION_CLASSES`, `DEFAULT_PERMISSION_CLASSES`,
  `DEFAULT_PAGINATION_CLASS`, `PAGE_SIZE`, `DEFAULT_FILTER_BACKENDS`, `DEFAULT_THROTTLE_RATES`, …).
- OpenAPI 3.1: `generateSchema(urlpatterns)`, `SchemaView`, `SwaggerUIView`/`ScalarView` (CDN).
- Introspection API (used by agents): `router.registry` entries expose viewset class, basename, actions,
  serializer JSON Schema via `serializer.jsonSchema()`.

---

## 8. `@ghuri/storage`

```ts
export abstract class Storage {
  abstract save(name: string, content: Blob | ArrayBuffer | ReadableStream | string, opts?: { contentType?: string }): Promise<string> // returns final (unique) name
  abstract open(name: string): Promise<StoredFile | null>   // { body: ReadableStream, size, contentType, etag, arrayBuffer(), text() }
  abstract delete(name: string): Promise<void>
  abstract exists(name: string): Promise<boolean>
  abstract size(name: string): Promise<number>
  abstract url(name: string): string                          // public URL (MEDIA_URL or presigned)
  listdir(prefix: string): Promise<{ dirs: string[]; files: string[] }>
  generateFilename(name: string): string; getAvailableName(name: string): Promise<string>
}
export const storages: { get(alias?: string): Storage }; export function defaultStorage(): Storage
export function r2(binding: string, opts?: { publicUrl?: string }): StorageConfig     // Workers R2 binding
export function s3(opts: { endpoint, bucket, accessKeyId, secretAccessKey, region?, publicUrl? }): StorageConfig  // aws4fetch; works for R2 S3 API, AWS, MinIO
export function memoryStorage(): StorageConfig
// '@ghuri/storage/fs': fileSystemStorage({ location, baseUrl })   (Node only)
```
- `FileField({ uploadTo: 'avatars/' | (instance, filename) => string, storage?: alias })` and `ImageField`
  (extends FileField; validates image mime). Value on instance is a `FieldFile { name, url, size(), open(), save(name, content), delete() }`;
  stored in DB as the name (varchar 100 default).
- `serveMedia()` view to stream files from storage at `MEDIA_URL` in DEBUG/when no public URL.
- Settings: `STORAGES`, `MEDIA_URL`.

---

## 9. `@ghuri/admin`

```ts
// src/blog/admin.ts
import { admin, ModelAdmin, TabularInline } from '@ghuri/admin'
class CommentInline extends TabularInline { model = Comment; extra = 1 }
@admin.register(Post)
export class PostAdmin extends ModelAdmin<Post> {
  listDisplay = ['title', 'author', 'published', 'createdAt']
  listFilter = ['published', 'createdAt']
  searchFields = ['title', 'body']
  prepopulatedFields = { slug: ['title'] }
  readonlyFields = ['createdAt']
  fieldsets = [[null, { fields: ['title', 'slug', 'body'] }], ['Meta', { fields: ['author', 'tags', 'published'], classes: ['collapse'] }]]
  inlines = [CommentInline]
  actions = [makePublished]
  listPerPage = 50; ordering = ['-createdAt']; dateHierarchy = 'createdAt'; rawIdFields = ['author']
}
// urls.ts → path('admin/', admin.site.urls)
```
- SSR with `hono/jsx`, progressive enhancement with htmx (CDN by default, `ADMIN_ASSETS` override),
  a single embedded CSS file (Django-admin look, light/dark). No build step for users.
- Pages: login/logout/password change, index (apps & models grouped), app index, changelist
  (columns, sorting, search, filters sidebar, date hierarchy, pagination, bulk actions incl.
  "delete selected" with confirmation), add/change form (fields from `Field.formHint()`, fieldsets,
  inlines, validation errors, `Save` / `Save and add another` / `Save and continue`), delete
  confirmation listing cascaded objects, object history (`LogEntry` model), FK selects with
  autocomplete for `autocompleteFields`/`rawIdFields`, M2M multi-select, file upload when storage installed.
- Permissions: staff only; per-model `hasViewPermission/hasAddPermission/hasChangePermission/hasDeletePermission(c, obj?)`
  default to auth perms. CSRF protected.
- `AdminSite` class (custom sites), `admin.site.register(Model, AdminClass?)`, `admin.site.unregister`,
  `siteHeader`, `siteTitle`, `indexTitle`.
- Auth models registered automatically (`UserAdmin` with password hashing form, `GroupAdmin`).

---

## 10. `@ghuri/agents`

```ts
import { Agent, ModelTools, ViewSetTools, tool, AgentRouter } from '@ghuri/agents'
import { z } from 'zod'

export class SupportAgent extends Agent {
  model = 'workers-ai:@cf/meta/llama-3.3-70b-instruct-fp8-fast'   // or 'anthropic:claude-…', 'openai:…', or an AI SDK LanguageModel
  instructions = 'You help customers with their orders.'
  tools = [
    new ModelTools(Order, { actions: ['list', 'retrieve'], serializer: OrderSerializer, filter: (qs, user) => qs.filter({ customer: user.pk }) }),
    new ViewSetTools(TicketViewSet, { actions: ['create'] }),
  ]
  permissionClasses = [IsAuthenticated]
  @tool({ description: 'Refund an order', input: z.object({ orderId: z.number() }) })
  async refund({ orderId }) { ... }
}
const agents = new AgentRouter()
agents.register('support', SupportAgent)   // POST /agents/support/chat (SSE stream), GET /agents/support/conversations/…
export const urlpatterns = [path('agents/', include(agents.urls)), path('mcp/', agents.mcp())]
```
- Built on the Vercel AI SDK (`ai`) for provider-agnostic models: Workers AI (`workers-ai-provider`,
  binding from `AGENTS.AI_BINDING` default `'AI'`), Anthropic, OpenAI. Model strings `provider:model`.
- Tools from models/viewsets reuse REST serializers and permission classes and run as the request user.
- `AgentsConfig` app with models `Conversation`, `Message` (ORM-backed memory; portable).
- MCP: Streamable HTTP endpoint exposing all registered tools (JSON-RPC 2.0: `initialize`,
  `tools/list`, `tools/call`), authenticated via REST authentication classes.
- Settings `AGENTS: { DEFAULT_MODEL, AI_BINDING, PROVIDERS: { anthropic: { apiKey } … }, MAX_STEPS }`.
- `agent.run(input, { user, conversationId })` programmatic API (usable from queues/cron).

---

## 11. `@ghuri/cli` and `create-ghuri`

`ghuri <command>`; locates the project by `package.json#ghuri.settings` (default `src/settings.ts`),
loads TS with `jiti`, builds `env` from `wrangler.jsonc` bindings via `wrangler`'s `getPlatformProxy()`
(local by default, `--remote` for remote D1/R2) merged with `.dev.vars` / `process.env`, then
`app.setup(env)` and runs the command. Built-ins:
`startproject <name> [--db d1|postgres|sqlite]`, `startapp <name>`, `runserver` (wraps `wrangler dev`,
or Node server with `--node`), `shell` (REPL with models preloaded), `check`, `test` (vitest),
`deploy` (wrangler deploy), `version`, `help`, plus commands from orm (`makemigrations`, `migrate`,
`showmigrations`, `sqlmigrate`, `dumpdata`, `loaddata`, `flush`) and apps (`createsuperuser`, …).

Project layout generated by `startproject mysite`:
```
mysite/
  package.json        # scripts: dev, deploy, migrate, makemigrations, test; "ghuri": { "settings": "src/settings.ts" }
  wrangler.jsonc      # nodejs_compat, d1 DB, r2 MEDIA, kv CACHE, vars
  tsconfig.json  .dev.vars.example  .gitignore  README.md
  src/
    index.ts          # export default createApp(settings)
    server.ts         # Node entry (VPS)
    settings.ts
    urls.ts
    <app>/            # created by `ghuri startapp blog`
      app.ts models.ts views.ts urls.ts serializers.ts admin.ts tests.ts migrations/index.ts
```

---

## 12. Portability matrix (must stay green in CI of `examples`)

| Concern | Cloudflare (default) | Node / VPS | Switch by |
|---|---|---|---|
| Runtime | Workers | `@ghuri/core/node` (Hono node-server) | entry file |
| DB | D1 (`d1('DB')`) | Postgres (`postgres({url})`), SQLite | `DATABASES` |
| PG on Workers | Hyperdrive (`postgres({ hyperdrive: 'HYPERDRIVE' })`) | — | `DATABASES` |
| Files | R2 (`r2('MEDIA')`) | S3 / filesystem | `STORAGES` |
| Cache | KV | memory / (redis later) | `CACHES` |
| Sessions | DB / KV / signed cookie | DB / signed cookie | `SESSION_ENGINE` |
| Data move | `ghuri dumpdata` → `ghuri loaddata` | | CLI |

## 13. Roadmap after 0.1

`@ghuri/tasks` (Cloudflare Queues + Node worker), `@ghuri/mail` (Email Workers / SMTP / Resend),
`@ghuri/forms` (standalone forms), i18n, Redis cache, read replicas / DB routers, `@ghuri/realtime`
(Durable Objects / WebSockets), GraphQL.

---

## 14. As-built notes (supersede earlier sections where they conflict)

**core** (github.com/ghurijs/core): extra exports `urlpatterns(appName, list)`, `resolve`, `resolverMatch(c)`,
`registerConverter`, `handleException`, `registerExceptionHandler(ClassOrPredicate, fn)`, `wantsJson`,
`settingsFor(c)`, `XFrameOptionsMiddleware`, `toHonoMiddleware`, CSRF helpers (`csrfExempt`,
`ensureCsrfCookie`, `getCsrfToken`, `rotateCsrfToken`, `enforceCsrf`, `checkCsrf`, `CsrfFailure`; Django masked
token format), `onSchedule(cron|'*', fn)`, `onQueue(name|'*', fn)`, `setting(name, fallback)`,
`AppConfig.modules`, errors `MethodNotAllowed`, `DisallowedHost`. Testing: `registerTestClientHook('forceLogin'|'login'|'logout', fn)`.
Errors under `API_PATH_PREFIXES` (default `['/api']`) are always JSON.

**orm** (github.com/ghurijs/orm):
- QuerySet compiles with its own SQL builder (not drizzle `sql`); drizzle tables still exist (`getTable`, `getSchema`).
- Drizzle column builder is `field.drizzleColumn(dialect)` (`field.column` is the column name).
- Default reverse accessor is camelCase `${modelName}Set` (e.g. `user.postSet`) with query name `post`; use `relatedName`.
- `inBulk()` returns a `Map`; `qs.delete()` returns `[total, perModel]`.
- D1 `atomic()` has no rollback; use `connection.batch()` for all-or-nothing.
- Results typed as the subclass need `declare static objects: Manager<Post>`.
- Extra exports: `Prefetch`, `Value`, `Lower`, `Upper`, `Length`, `Coalesce`, `Concat`, `Now`, `RawSQL`, `Func`,
  `captureQueries`, `onQuery`, `onCommit`, `getListOr404`, `IntegrityError`, `ProtectedError`, `RestrictedError`, `FieldError`.
- Historical models: `createModelClass(name, fields, { meta, registry: new ModelRegistry({ isolated: true }) })`.
- `@ghuri/orm/testing`: `setupTestDatabase`, `createTablesForModels`, `setTestSchemaCreator`, `testBackends`.

**Decided after review:**
- ORM commands take Django's `--database <alias>` option. Moving data between databases:
  `DATABASES = { default: d1('DB'), pg: postgres({ url }) }` then `ghuri migrate --database pg` and
  `ghuri dumpdata --database default > data.json && ghuri loaddata data.json --database pg`
  (plus a convenience `ghuri copydata --from default --to pg`).
- REST: `serializer.isValid()` is async (`await s.isValid({ raiseException: true })`), output via `await s.getData()`.
- Permission composition: `IsAuthenticated.or(IsAdminUser)`, `.and()`, `.not()` static helpers returning a permission class.

**orm migrations** (as built): `preMigrate`/`postMigrate` from `@ghuri/orm` (sender = AppConfig, args `{ appConfig, using, plan }`);
`@ghuri/orm/migrations` is Workers-safe and exports `Migration`, `operations`, `ProjectState`, `MigrationLoader/Graph/Executor/Recorder`,
`MigrationAutodetector`, `MigrationWriter`, `makeMigrations`, `migrate`, `showMigrations`, `sqlMigrate`, `sqlMigrateAll`, `dumpData`,
`loadData`, `flushDatabase`, `copyData`. `@ghuri/orm/commands` (Node) exports `registerOrmCommands()` and `setMigrationImporter()`.
One-off defaults are stored as `oneOffDefault`; index names are always explicit; SQLite/D1 rebuilds copy via a temp table (D1 can't
disable FKs); `sqlmigrate --all` SQL files record their own `ghuri_migrations` rows; `postMigrate` also fires after `flush` and
`setupTestDatabase`. Not yet: `squashmigrations`, `inspectdb`, swappable-dependency markers, PK/auto-field changes.

**auth** (as built): app labels `contenttypes`, `auth`, `sessions`, `authtoken`, `token_blacklist`; Django table names
(`auth_user`, `django_content_type`, `django_session`, …); hashes/signing/sessions byte-compatible with Django; default PBKDF2
100,000 iterations (higher counts verified via JS fallback and rehashed on login). REST auth classes in `@ghuri/auth/rest`.

**storage** (as built): `FieldFile.toJSON()` returns the stored name; assign uploads with `upload(file)`; `presignedUrl()` (S3 only).
