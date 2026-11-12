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
| `graphql` | `@ghuri/graphql` | graphene-django-style GraphQL: model types, Relay connections and filters, serializer mutations, `GraphQLView` (section 15) | core, orm, `graphql`, (optional) rest |
| `realtime` | `@ghuri/realtime` | Channels-style WebSocket consumers, rooms (Durable Objects on Workers, in-process on Node), channel layer, test communicator | core, (optional) auth, rest |
| `oauth` | `@ghuri/oauth` | Passport.js-style strategies: OAuth2, OIDC, local, magic link, bearer; `authenticate()` views (section 17) | core, auth |
| `oauth-provider` | `@ghuri/oauth-provider` | django-oauth-toolkit-style OAuth 2.1 authorization server: PKCE, rotating refresh tokens, CIMD + dynamic registration, RFC 8707 JWT access tokens, admin; the authorization server for MCP (section 19) | core, orm, auth, oauth, (optional) rest, admin |
| `socialauth` | `@ghuri/socialauth` | django-allauth-style social login: providers, `SocialAccount`, signup/linking, admin (section 18) | core, orm, auth, oauth |
| `mail` | `@ghuri/mail` | `django.core.mail` clone: `sendMail`, `EmailMessage`, backends (Cloudflare Email Service, Resend, SMTP in `@ghuri/mail/smtp`, console, locmem, dummy), test outbox | core |
| `tenants` | `@ghuri/tenants` | Shared-schema multi-tenancy: `tenantModel()` factories, fail-closed tenant QuerySets, write checks, `TenantMiddleware` + resolvers, `tenantCache()`, leak tests | core, orm, `hono` |
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

`@ghuri/tasks` (Cloudflare Queues + Node worker), `@ghuri/forms` (standalone forms), i18n, Redis cache, read replicas / DB routers, `@ghuri/realtime`
(Durable Objects / WebSockets, specified in section 16), GraphQL.

---

## 14. As-built notes (supersede earlier sections where they conflict)

**core** (github.com/ghurijs/core): extra exports `urlpatterns(appName, list)`, `resolve`, `resolverMatch(c)`,
`registerConverter`, `handleException`, `registerExceptionHandler(ClassOrPredicate, fn)`, `wantsJson`,
`settingsFor(c)`, `XFrameOptionsMiddleware`, `toHonoMiddleware`, CSRF helpers (`csrfExempt`,
`ensureCsrfCookie`, `getCsrfToken`, `rotateCsrfToken`, `enforceCsrf`, `checkCsrf`, `CsrfFailure`; Django masked
token format), `onSchedule(cron|'*', fn)`, `onQueue(name|'*', fn)`, `setting(name, fallback)`,
`AppConfig.modules`, errors `MethodNotAllowed`, `DisallowedHost`. Testing: `registerTestClientHook('forceLogin'|'login'|'logout', fn)`.
Errors under `API_PATH_PREFIXES` (default `['/api']`) are always JSON.
`xframeOptionsExempt(view)` / `static xframeOptionsExempt = true` (Django's `xframe_options_exempt`) use a marker
like `csrfExempt`; a header the view sets itself always wins. `getRemoteAddr(c)` is Django's `REMOTE_ADDR` and reads
only unforgeable sources: `CF-Connecting-IP` on Cloudflare (`navigator.userAgent === 'Cloudflare-Workers'` or
`request.cf`), else the socket address `serve()` records with `setRemoteAddr(request, addr)` (a `WeakMap` keyed by the
`Request`, so `env` stays the settings env), else `c.env.incoming` (plain `@hono/node-server`), else `''`.

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

**rest** (as built): `RestFrameworkConfig` (app label `rest_framework`) only contributes the `generateschema` command
(DRF's: `--file`, `--format openapi|openapi-json`, `--title`, `--description`, `--api-version`, `--url`). It reuses the
first `SchemaView` routed in `ROOT_URLCONF` (its title/version/servers/patterns/prefix), so the file equals what that
view serves; a `--file` ending in `.json` defaults to JSON. YAML comes from a built-in emitter (no dependency).
`startproject` routes `api/schema/`, `api/docs/` (Swagger UI) and `api/reference/` (Scalar) before the router include.
**Deliberate difference from DRF:** throttles read `X-Forwarded-For` only when `NUM_PROXIES` is set (then DRF's rule:
the address `NUM_PROXIES` hops from the end, `0` ignores the header). DRF trusts the whole header when `NUM_PROXIES` is
`None`, which lets any client pick a fresh rate-limit bucket per request. Otherwise `getIdent()` uses core's
`getRemoteAddr(c)` (via the overridable `BaseThrottle.getRemoteAddr(request)`).

**mail** (as built, github.com/ghurijs/mail): `django.core.mail` with camelCase names and async sending: `sendMail`,
`sendMassMail`, `mailAdmins`, `mailManagers`, `EmailMessage`, `EmailMultiAlternatives`, `getConnection`,
`BaseEmailBackend`, `BadHeaderError`, `EmailSendError`. `EMAIL_BACKEND` is a `{ backend, create(env, options) }` config
like caches and storages: `cloudflareEmailBackend({ binding })`, `resendBackend({ apiKey })`, `consoleBackend()`,
`locmemBackend()`, `dummyBackend()`, and `smtpBackend()` from the Node-only subpath `@ghuri/mail/smtp` (reads Django's
`EMAIL_HOST*` / `EMAIL_PORT` / `EMAIL_USE_TLS|SSL`). Differences: no default SMTP backend (unset `EMAIL_BACKEND` means
console in `DEBUG`, `ImproperlyConfigured` otherwise); `message()` returns a `MIMEPart`; no `attachFile()`; `ADMINS` /
`MANAGERS` are address strings. `@ghuri/mail/testing`: `outbox`, `useOutbox()`, `restoreEmailBackend()`, `clearOutbox()`.

**tenants** (as built, github.com/ghurijs/tenants): shared-schema only (one database, a tenant FK per row), because
schema-per-tenant does not exist on D1/SQLite. `tenantModel({ field, to, relatedName, uuidPk })` / `TenantModel` give a
tenant FK, `objects` (`TenantManager`; the filter is added when the QuerySet runs, including as a subquery) and
`unscoped`. With no tenant active, queries and writes **fail closed** (`TenantNotSet`); writes and FKs that cross
tenants raise `CrossTenantError`. Context: `runAsTenant`, `withoutTenant`, `activateTenant`, `currentTenant`,
`requireTenant`, `tenantMode`. `TenantMiddleware` runs `TENANTS.RESOLVERS` (`HeaderResolver`, `SubdomainResolver`,
`HostResolver`, functions) and honours `TENANTS.REQUIRED`; `TenantNotFound` is an `Http404`. Also `tenantCache()`,
`uuid7()`, and `assertTenantIsolation()` in `@ghuri/tenants/testing`. Not yet: per-tenant database routing,
`dumpdata --tenant`, Postgres RLS, admin integration, a REST membership permission class.

---

## 15. `@ghuri/graphql` (graphene-django style)

```ts
import { ModelType, Query, Mutation, Schema, Field, List, ID, SerializerMutation, GraphQLView } from '@ghuri/graphql'

class PostType extends ModelType {
  static Meta = { model: Post, fields: ['id', 'title', 'body', 'author', 'tags', 'createdAt'], filterFields: { title: ['icontains'], published: ['exact'] }, interfaces: [Node] }
  static fields = { excerpt: Field(String, { resolve: (post) => post.body.slice(0, 100) }) }
}
class BlogQuery extends Query {
  static fields = {
    posts: List(PostType, { resolve: () => Post.objects.filter({ published: true }) }),
    post: Field(PostType, { args: { id: ID }, resolve: (_, { id }) => Post.objects.get({ id }) }),
    allPosts: ConnectionField(PostType),          // Relay connection + filters + ordering
  }
}
class CreatePost extends SerializerMutation { static Meta = { serializerClass: PostSerializer, permissionClasses: [IsAuthenticated] } }
class BlogMutation extends Mutation { static fields = { createPost: CreatePost.field() } }

export const schema = new Schema({ query: [BlogQuery], mutation: [BlogMutation] })   // merges app query classes
// urls.ts
path('graphql/', GraphQLView.asView({ schema, graphiql: true }))
```
- Code-first on `graphql` (graphql-js v17, peer dependency so there is one instance). Types are generated from ORM
  `_meta` / `Field` (`internalType` → GraphQL scalar, choices → enums, FK/M2M/reverse → object/list fields).
- N+1 safety: per-request DataLoaders for FK, reverse FK and M2M; optional `selectRelated`/`prefetchRelated` optimizer from the query AST.
- Relay: `Node` interface, global IDs, `ConnectionField` with cursor pagination, `filterFields` (ORM lookups as args), `orderBy`.
- Mutations: `SerializerMutation` / `ModelMutation` reusing `@ghuri/rest` serializers + permission classes (rest is an optional peer);
  errors returned as `errors: [{ field, messages }]` payload like graphene-django.
- Auth: request user from core `getUser(c)`; REST authentication classes usable via `GraphQLView.authenticationClasses`; `loginRequired`/`permissionRequired` resolver wrappers.
- HTTP: GraphQL-over-HTTP (GET for queries, POST JSON, `application/graphql-response+json`), GraphiQL from CDN when enabled, CSRF exemption only with token auth, depth/complexity limits, persisted query hook, introspection toggle.
- Settings `GRAPHQL: { SCHEMA, GRAPHIQL, MAX_DEPTH, MAX_COMPLEXITY, INTROSPECTION }`; command `graphql_schema` (prints SDL).
- Subscriptions are out of scope for 0.1 (later via `@ghuri/realtime`, section 16).

---

## 16. `@ghuri/realtime` (Channels-style WebSockets)

Status: **phase 1 built** (see 16.11 for where it differs from this text). Repo `ghurijs/realtime`, npm `@ghuri/realtime`, peers `@ghuri/core`
(required) and `@ghuri/auth`, `@ghuri/rest` (optional, for authentication and permission classes).

Django Channels gives Django developers consumers, groups and a channel layer. Ghuri keeps those names,
but its unit of fan-out is a **room**, because the Cloudflare primitive is a Durable Object (DO): one
globally unique, single-threaded object that holds a set of sockets. Every connection lives in exactly
one room, and the same rule applies on Node so code that works locally behaves the same on Workers.

```ts
// src/chat/consumers.ts
import { JsonWebSocketConsumer, type Scope } from '@ghuri/realtime'
import { IsAuthenticated } from '@ghuri/rest'

export class ChatConsumer extends JsonWebSocketConsumer {
  static room = (scope: Scope) => `chat.${scope.params.room}`   // which room (DO) owns this socket
  static permissionClasses = [IsAuthenticated]

  async connect() {
    await this.accept()
    await this.room.broadcast({ type: 'chat.joined', user: this.user.username }, { exclude: this })
  }
  async receiveJson(data: { text: string }) {
    const msg = await Message.objects.create({ room: this.scope.params.room, author: this.user.pk, text: data.text })
    await this.room.groupSend({ type: 'chat.message', id: msg.pk, text: msg.text, user: this.user.username })
  }
  async chatMessage(event: { id: number; text: string; user: string }) {   // 'chat.message' → chatMessage
    await this.sendJson(event)
  }
}

// src/chat/urls.ts — routed like any view; runs through MIDDLEWARE (session, auth) on the handshake
export const urlpatterns = [path('ws/chat/<slug:room>/', ChatConsumer.asView(), { name: 'chat-socket' })]

// anywhere else: a REST view, a signal receiver, a cron or queue handler
import { channelLayer } from '@ghuri/realtime'
await channelLayer.groupSend('chat.lobby', { type: 'chat.message', text: 'Server restarting in 5 minutes' })
```

```ts
// src/index.ts (Cloudflare) — the app plus the Durable Object class that hosts rooms
import { createApp } from '@ghuri/core'
import { createRoomClass } from '@ghuri/realtime/cloudflare'
import settings from './settings'
const app = createApp(settings)
export default app
export const GhuriRoom = createRoomClass(app)

// src/settings.ts (memoryLayer() on Node and in tests)
REALTIME: { LAYER: durableObjectLayer('REALTIME') }
```
```jsonc
// wrangler.jsonc
"durable_objects": { "bindings": [{ "name": "REALTIME", "class_name": "GhuriRoom" }] },
"migrations": [{ "tag": "realtime-v1", "new_sqlite_classes": ["GhuriRoom"] }]
```

### 16.1 Consumers

```ts
export abstract class WebSocketConsumer {
  static room: string | ((scope: Scope) => string | null | Promise<string | null>)   // null → 403
  static authenticationClasses?: AuthenticationClass[]   // default: the user MIDDLEWARE set (core getUser)
  static permissionClasses?: PermissionClass[]           // checked on the handshake, before connect()
  static subprotocols?: string[]                         // offered back in Sec-WebSocket-Protocol
  static asView(initkwargs?): ViewFunction

  readonly scope: Scope              // what the handshake established (below); survives hibernation
  readonly user: RequestUser         // from scope.user; see 16.5
  readonly room: Room                // the room this socket belongs to
  state: Record<string, unknown>     // per-connection JSON state; persisted after every handler

  connect(): Promise<void>           // default: accept()
  receive(message: { text?: string; bytes?: ArrayBuffer }): Promise<void>
  disconnect(code: number, reason: string): Promise<void>

  accept(subprotocol?: string): Promise<void>
  send(message: string | ArrayBuffer): Promise<void>
  close(code?: number, reason?: string): Promise<void>
  tag(...tags: string[]): Promise<void>   // labels inside the room, for broadcast filters
}
export abstract class JsonWebSocketConsumer extends WebSocketConsumer {
  receiveJson(data: unknown): Promise<void>
  sendJson(data: unknown): Promise<void>
}

export interface Scope {
  path: string; params: Record<string, string>; query: Record<string, string>
  routeName?: string; room: string; connectionId: string           // connectionId: random, stable for the socket's life
  headers: { origin?: string; userAgent?: string; subprotocols: string[] }
  user: UserSnapshot; sessionKey?: string; auth?: unknown          // auth: token payload from the auth class, if JSON-safe
}
```
- Group events are dispatched by `type`: dots and dashes become camelCase (`chat.message` → `chatMessage`).
  A missing handler logs a warning (DEBUG) and drops the event; Channels raises, but here the sender is
  often another request that should not fail.
- A consumer instance is **not** long-lived. It is rebuilt from `scope` + `state` for every event, because
  a hibernating DO drops its memory (16.3). Fields assigned on `this` other than `state` are lost between
  events. `state` plus `scope` must serialize to **≤ 2 KB** (Cloudflare's per-socket attachment limit);
  exceeding it throws `RealtimeStateTooLarge` on both backends.
- `connect()` that neither accepts nor closes is closed with 1011 once it returns. `close()` before
  `accept()` rejects the handshake with 403.
- Every handler runs inside a Ghuri context (`getContext()`, ORM connections, `getUser()` returning
  `this.user`), created per event like a request.

### 16.2 Routing and the handshake

`Consumer.asView()` returns an ordinary core view, so WebSocket routes live in `urls.ts`, support
`reverse()` and `include()`, and pass through `MIDDLEWARE` like any GET request. The handshake:

1. Not `Upgrade: websocket` → 426 Upgrade Required.
2. MIDDLEWARE runs as usual (host validation, session, `AuthenticationMiddleware`).
3. Origin check (Cross-Site WebSocket Hijacking protection): a browser `Origin` must match the request host,
   `CSRF_TRUSTED_ORIGINS` or `REALTIME.ALLOWED_ORIGINS`, else 403. Requests without `Origin` (non-browser
   clients) pass. CSRF tokens are not required: the upgrade is a GET.
4. `authenticationClasses` run against the handshake (same `BaseAuthentication` contract as REST). Browsers
   cannot set `Authorization` on a WebSocket, so a token may arrive as a subprotocol
   (`Sec-WebSocket-Protocol: ghuri, bearer.<token>`, default) or, opt-in, as `?token=` (it ends up in logs).
   Realtime copies it into `Authorization: <keyword> <token>` on the request handed to the classes;
   the keyword is `REALTIME.TOKEN_KEYWORD` (default `Bearer`).
5. `permissionClasses` run with `request.user`, `request.auth` and `request.scope` (room not yet resolved); failure → 401/403.
6. `room` is resolved; `null` → 403.
7. The socket is handed to the layer: on Workers, the view forwards the upgrade to the room's DO and returns
   its `101` response; on Node it is accepted in-process. `connect()` runs **in the room** (in the DO).

**Core change required:** a `101` response from a DO has immutable headers and carries a `webSocket`
property that cloning drops. Core must pass upgrade responses through untouched: `toHonoMiddleware` and the
built-in middleware skip header writes when `res.status === 101`, and core exports `isUpgradeResponse(res)`
for third-party middleware. `@ghuri/auth`'s `SessionMiddleware` must skip `Vary`/cookie writes on `101`
(a session modified during the handshake is still saved, but no cookie is set). Covered by a test that
runs the default `startproject` MIDDLEWARE stack against a DO upgrade in Miniflare.

### 16.3 Rooms and the channel layer

```ts
export interface Room {
  readonly name: string
  groupSend(event: { type: string; [k: string]: unknown }, opts?: BroadcastOptions): Promise<void>   // runs handlers
  broadcast(message: unknown, opts?: BroadcastOptions): Promise<void>   // raw send (JSON-encoded unless string/bytes)
  connections(opts?: { tag?: string }): Promise<ConnectionInfo[]>       // presence: id, user pk, tags, connectedAt
  count(opts?: { tag?: string }): Promise<number>
  storage: RoomStorage   // small durable per-room KV: get/put/delete/list; DO SQLite on Workers, memory on Node
}
interface BroadcastOptions { tag?: string; exclude?: WebSocketConsumer | string /* connectionId */ }

export const channelLayer: {
  room(name: string): Room                      // works outside a consumer: views, signals, cron, queues
  groupSend(room: string, event, opts?): Promise<void>
  send(connectionId: string, event): Promise<void>   // one socket; needs its room: ids are `<room>:<uuid>`
}
```
- `groupSend` runs the matching handler once per connection (each consumer decides what to send, e.g.
  filtering by `this.user`); `broadcast` sends the same frame to every socket without running consumer code,
  so prefer it for large rooms.
- Sending to a room with no connections is a no-op. Delivery is at-most-once; there is no replay. Clients
  that need history load it over REST on reconnect.
- Per-user notifications use a room per user:
  ``static room = (s) => s.user.isAuthenticated ? `user.${s.user.pk}` : null``,
  and ``channelLayer.groupSend(`user.${pk}`, …)`` from anywhere.
- Not supported (deliberately): one socket in several rooms. Clients open one socket per room, or the server
  fans out to the per-user room. Channels' `group_add`/`group_discard` map to `tag()` inside the room.

### 16.4 Layers

| | `durableObjectLayer(binding)` (Workers) | `memoryLayer()` (Node, tests) | `postgresLayer(alias?)` (Node, phase 2) |
|---|---|---|---|
| Room | one DO per room name (`idFromName`) | in-process map | in-process map per process |
| Cross-process send | DO RPC from any Worker | single process only | `LISTEN/NOTIFY` on the `DATABASES` alias |
| Survives deploys | sockets drop on DO code update; clients reconnect | no | no |

**Cloudflare.** `createRoomClass(app)` returns a DO class that:
- accepts sockets with the Hibernation API (`ctx.acceptWebSocket(ws, tags)`), stores `scope` + `state` with
  `ws.serializeAttachment()`, and rebuilds consumers in `webSocketMessage` / `webSocketClose` /
  `webSocketError`; tags are the room tags (Cloudflare allows 10 per socket, 256 chars each);
- runs each event through a new public core method `app.run(env, executionCtx, fn)` (today's private
  `withTaskContext`, used by `scheduled`/`queue`), so apps are populated once per DO and every event has a
  fresh context. The DO's `env` has the same bindings as the Worker, so D1, R2 and KV work in consumers;
- receives the handshake as an internal `fetch` with the scope in an `X-Ghuri-Scope` header (DOs are only
  reachable through the binding, so the header cannot be forged from outside), and `groupSend`/`broadcast`/
  `connections` as DO RPC methods;
- answers `ping` with `pong` without waking (`setWebSocketAutoResponse`), so idle sockets cost nothing.

A room is one single-threaded object: practical limits are a few thousand sockets and the CPU of one
isolate. Sharding a room is out of scope; very large audiences should use `broadcast`, not `groupSend`.

**Node.** `serve()` from `@ghuri/core/node` gains `{ websocket: true }` (automatic when `@ghuri/realtime` is
installed and `REALTIME` is set): it wires `@hono/node-ws` to the server `serve()` already returns, and the
consumer view accepts in-process. `memoryLayer` is the default and correct for one process; multi-process
or multi-machine deployments need `postgresLayer` (phase 2) or the Redis layer (later). `ghuri check`
warns when `memoryLayer` is used with `DEBUG = false`.

### 16.5 Users in consumers

- The handshake stores a `UserSnapshot` in the scope: `{ pk, username, isAuthenticated, isActive, isStaff, isSuperuser }`.
  `this.user` implements core's `RequestUser` from that snapshot; `hasPerm` / `hasPerms` load the real user
  on first use per event.
- **Core change required:** `registerUserLoader(fn: (pk) => Promise<RequestUser | null>)` and `loadUser(pk)`
  in core (next to `getUser`/`setUser`, 4.12). `@ghuri/auth` registers the loader in `ready()` using
  `getUserModel()`, so realtime never imports auth.
- Authentication is checked on the handshake only. `await this.refreshUser()` reloads the user and returns
  false (and closes with 4401) if they are gone or inactive. With `REALTIME.REVALIDATE_SECONDS` (default 0 =
  off), the consumer does this automatically before handling an event once the interval has passed.
  Logout does not close open sockets; apps can send ``channelLayer.groupSend(`user.${pk}`, { type: 'session.ended' })``
  from a `userLoggedOut` receiver.

### 16.6 Settings

```ts
REALTIME: {
  LAYER: durableObjectLayer('REALTIME') | memoryLayer() | postgresLayer('default'),  // { backend, create(env) } like caches
  ALLOWED_ORIGINS: [],                 // in addition to the host and CSRF_TRUSTED_ORIGINS
  TOKEN_SOURCES: ['subprotocol'],      // and/or 'query'
  TOKEN_KEYWORD: 'Bearer',             // 'Token' for authtoken
  MAX_MESSAGE_BYTES: 1_048_576,        // larger frames close the socket with 1009
  REVALIDATE_SECONDS: 0,
}
```

### 16.7 Testing

`@ghuri/realtime/testing` (memory layer, Node) mirrors Channels' `WebsocketCommunicator`:

```ts
const ws = new WebSocketCommunicator(app, '/ws/chat/lobby/', { user, headers: { origin: 'http://testserver' } })
const { connected, subprotocol } = await ws.connect()
await ws.sendJson({ text: 'hi' })
expect(await ws.receiveJson({ timeout: 1000 })).toMatchObject({ type: 'chat.message', text: 'hi' })
expect(await ws.receiveNothing()).toBe(true)
await ws.disconnect()
```
`user` uses the same `forceLogin` hook as the HTTP test client. The `examples` repo adds a chat app and
runs it in Miniflare against `durableObjectLayer` so the Workers path (hibernation, 101 pass-through,
DO RPC) is tested end to end; it joins the portability matrix (12) for Workers and Node + `memoryLayer`.

### 16.8 Changes in other packages

| Package | Change |
|---|---|
| core | `isUpgradeResponse(res)` + 101 pass-through in `toHonoMiddleware` and built-ins; public `app.run(env, execCtx, fn)`; `registerUserLoader` / `loadUser`; `serve({ websocket })` in `@ghuri/core/node` |
| auth | register the user loader; `SessionMiddleware` skips header writes on 101; `userLoggedOut` already exists for logout fan-out |
| cli | `startproject --realtime` adds the DO export, wrangler binding/migration and `REALTIME` settings; `startapp` template gets an empty `consumers.ts` |
| graphql | phase 2: subscriptions over the `graphql-transport-ws` protocol as a consumer (`GraphQLSubscriptionConsumer`), with `pubsub` backed by rooms |
| docs | topic "WebSockets", Channels cheat-sheet rows, Cloudflare deployment section for the DO binding |

### 16.9 Phases

1. **0.1**: `WebSocketConsumer`, `JsonWebSocketConsumer`, routing and handshake, rooms with `groupSend`/
   `broadcast`/tags/presence/storage, `durableObjectLayer`, `memoryLayer`, testing communicator, the core and
   auth changes above, chat example.
2. **0.2**: `postgresLayer`, GraphQL subscriptions, `EventStreamView` (server-sent events on the same rooms for
   one-way feeds), `broadcastModelChanges(Model, { room, serializer })` built on ORM `postSave`/`postDelete`.
3. **Later**: Redis layer, room sharding, message replay.

### 16.10 Decisions (were open questions)

- `static room` is optional and defaults to the request path (one room per URL).
- `groupSend` (including DO-to-DO RPC to another room) resolves after the room ran every handler. Callers that
  should not wait pass the promise to `executionCtx.waitUntil`.
- Hosting rooms in a Cloudflare Agents SDK `Agent` is deferred (phase 3).

### 16.11 As built (supersedes 16.1–16.8 where they conflict)

- **No core 101 pass-through was needed.** `durableObjectLayer` re-wraps the room's `101` in
  `new Response(null, { status: 101, webSocket, headers })`, whose headers are mutable, so the default MIDDLEWARE
  stack (Security, Session, Common, Csrf, Authentication, XFrameOptions) runs unchanged; verified in workerd.
  `isUpgradeResponse` and the `SessionMiddleware` change were dropped.
- **`memoryLayer()` is Node and tests only.** Workers forbid writing to a socket from another request's handler, so
  in-isolate rooms cannot fan out; on Workers `memoryLayer()` throws `ImproperlyConfigured` pointing to
  `durableObjectLayer`. `wrangler dev` runs Durable Objects locally, so projects use the DO layer in development too.
- **Node:** core `serve()` is unchanged. `@ghuri/realtime/node` exports `attachRealtime(server, app, { env })` (on
  `ws`), used with the server `serve()` returns. The handshake still runs through `app.fetch`; a `PendingUpgrade`
  registered for the `Request` lets the consumer view accept, and the upgrade completes only on accept.
- **Core changes shipped:** `app.run(env, execCtx, fn)`; `registerUserLoader` / `loadUser`. `@ghuri/auth` registers
  the loader in `AuthConfig.ready()` (only when core provides it).
- **Tags** are stored in the connection record, not Cloudflare hibernation tags (those are fixed at
  `acceptWebSocket` time). Limits stay 10 tags of ≤ 256 characters.
- **Handshake outcomes:** `connect()` that neither accepts nor closes rejects with 403 (not a 1011 close); a scope
  that would not fit in 2 KB is refused with 431 before reaching the room; `Origin: null` is refused.
- **The room DO** receives the scope URI-encoded in `X-Ghuri-Scope` (headers must be Latin-1), resolves the consumer
  class with core `resolve(scope.path)`, runs every event through `app.run`, and prefixes its storage keys with
  `room:`. RPC methods: `groupSend`, `broadcast`, `sendTo`, `connections`, `storageGet/Put/Delete/List`.
- Not yet: `ghuri check` warning for `memoryLayer` in production, `startproject --realtime`, the docs topic, the
  `examples` chat app.

---

## 17. `@ghuri/oauth` (Passport.js-style strategies)

Status: **phase 1 built** (as-built notes in 17.7). Repo `ghurijs/oauth`, npm `@ghuri/oauth`, peers `@ghuri/core`, `@ghuri/auth`
(login, sessions, signing, JWT pairs), `hono`.

The building blocks for any login system: a **strategy** turns a request into "this is user X", "this
request isn't for me", "redirect the browser there" or "fail with 401". Apps register strategies and mount
`authenticate('name')` views, the way Passport.js apps call `passport.use()` and `passport.authenticate()`.
`@ghuri/socialauth` (section 18) is built on this package; apps that want their own social login, a custom
identity provider, magic links or API keys use it directly.

```ts
// src/accounts/strategies.ts
import { OAuth2Strategy, OIDCStrategy, MagicLinkStrategy, strategies } from '@ghuri/oauth'

strategies.use('acme', new OIDCStrategy({
  issuer: 'https://login.acme.example',               // discovery: /.well-known/openid-configuration
  clientId: (env) => env.ACME_CLIENT_ID,
  clientSecret: (env) => env.ACME_CLIENT_SECRET,
  scope: ['openid', 'email', 'profile'],
}, async ({ profile }) => {                            // verify: profile → user (or null to fail)
  return (await User.objects.filter({ email: profile.email }).first()) ?? User.objects.create({ … })
}))

strategies.use('email', new MagicLinkStrategy({
  send: async ({ email, url }) => sendMail(email, 'Your login link', url),
}, async ({ email }) => User.objects.filter({ email }).first()))

// src/accounts/urls.ts
export const urlpatterns = [
  path('login/acme/', authenticate('acme')),                     // redirects to the provider
  path('login/acme/callback/', authenticate('acme', { successRedirect: '/', failureRedirect: '/login/' })),
  path('login/email/', authenticate('email')),                   // POST { email } → sends a link; GET ?token= → logs in
]
```

### 17.1 Strategies

```ts
export type StrategyResult =
  | { type: 'success'; user: AbstractBaseUser; info?: Record<string, unknown> }
  | { type: 'fail'; status?: number; challenge?: string; message?: string }   // challenge → WWW-Authenticate
  | { type: 'redirect'; url: string; status?: number }
  | { type: 'pass' }                                                          // not for me: try the next strategy
  | { type: 'error'; error: unknown }

export abstract class Strategy {
  abstract name: string
  abstract authenticate(c: Context, options: AuthenticateOptions): Promise<StrategyResult>
}
export const strategies: { use(name: string, s: Strategy): void; get(name: string): Strategy; unuse(name: string): void }
```
Built-ins:

| Strategy | Does |
|---|---|
| `OAuth2Strategy` | Authorization code flow: builds the authorize URL (state, PKCE S256 by default), exchanges the code, calls `profile(tokens)` to fetch and normalize the user, then `verify`. Options: `authorizationURL`, `tokenURL`, `clientId`, `clientSecret` (values or `(env) => value`), `scope`, `scopeSeparator`, `pkce`, `authorizationParams`, `tokenAuth: 'body' \| 'basic'`, `profile`. |
| `OIDCStrategy` | `OAuth2Strategy` plus discovery (cached per isolate), `nonce`, ID token validation (signature from JWKS: RS256/ES256/EdDSA via WebCrypto; `iss`, `aud`, `exp`, `iat`, `nonce`), userinfo; the profile comes from the claims. |
| `LocalStrategy` | Username/password from JSON or form fields; default `verify` is `@ghuri/auth`'s `authenticate()` (so `AUTHENTICATION_BACKENDS` apply). |
| `MagicLinkStrategy` | `POST { email }` sends a signed, single-use, expiring link (`TimestampSigner`; the signature covers the user's `lastLogin`, so it stops working after one login, like password reset tokens); `GET ?token=` logs in. |
| `BearerStrategy` | `Authorization: Bearer <token>` → `verify(token)`. For API keys and custom tokens. |
| `CustomStrategy` | `new CustomStrategy('name', (c) => result)` for one-off schemes. |

Every OAuth-flavoured strategy also exposes its pieces (`client.authorizationUrl()`, `client.exchangeCode()`,
`client.refresh()`, `client.revoke()`), so apps can run the flow by hand.

**Profiles** are normalized to one shape (what `@ghuri/socialauth` stores):
`{ provider, id, email?, emailVerified?, username?, name?, firstName?, lastName?, avatarUrl?, raw }`.

### 17.2 `authenticate(nameOrNames, options)` → view

```ts
export interface AuthenticateOptions {
  successRedirect?: string; failureRedirect?: string
  successReturnToOrRedirect?: string        // honor a safe ?next= kept across the round trip
  session?: boolean                          // default true: @ghuri/auth login(c, user)
  respond?: 'session' | 'jwt' | ((c, user, info) => Response | Promise<Response>)   // jwt → tokenPairForUser()
  scope?: string[]; state?: Record<string, string>   // per-request extras
}
```
- Several names try strategies in order until one does not `pass` (Passport's chain).
- Success: `login(c, user, 'ghuri.oauth:<name>')` (a backend name `@ghuri/auth` resolves through a small
  `StrategyBackend` that `@ghuri/oauth` registers), then redirect, or JSON `{ user }`, or a JWT pair.
- Failure: `failureRedirect` with `?error=`, or JSON 401 with `WWW-Authenticate` when the strategy sent a challenge.
- Errors from providers (`error=access_denied` on the callback) become a failure, not a 500.
- `authenticate()` is also callable as a function inside a view: `const result = await runStrategy(c, 'acme')`.

### 17.3 Round-trip state

OAuth needs `state`, the PKCE verifier, the OIDC `nonce` and `next` to survive the trip to the provider. They go
in a signed, encrypted, HttpOnly, `SameSite=Lax`, 10-minute cookie (`ghuri_oauth`, AES-GCM with a key derived
from `SECRET_KEY` via HKDF), so the flow works without sessions (SPAs, Workers with KV-less setups). One cookie
holds several pending flows (keyed by state) so two tabs don't break each other. The callback rejects missing,
expired or mismatched state with a failure (never a 500).

### 17.4 REST integration

`@ghuri/oauth/rest` exports `StrategyAuthentication(['api-key'])`: a REST authentication class that runs the named
strategies (`BearerStrategy`, `CustomStrategy`) and returns `[user, info]`. Same contract as section 7's classes.

### 17.5 Settings

```ts
OAUTH: {
  STATE_COOKIE: 'ghuri_oauth', STATE_MAX_AGE: 600,
  HTTP_TIMEOUT: 10_000,                 // provider requests
  CALLBACK_BASE_URL: undefined,         // default: the request origin (behind proxies, set this)
}
```

### 17.6 Testing

`@ghuri/oauth/testing`: `mockOAuthProvider({ profile, tokens })` intercepts the provider's token and userinfo
requests (a `fetch` stub scoped to the test), and `client.followOAuth('/login/acme/')` runs the redirect →
callback round trip through the test client.

### 17.7 As built (supersedes 17.1–17.6 where they conflict)

- **Results** gained `{ type: 'response', response }` (a strategy that answers itself, e.g. "we sent you a link").
- **`verify` is required** for `OAuth2Strategy` / `OIDCStrategy`; it may return a user, `{ user, info }` or null.
- **Login backend:** no `StrategyBackend`. `login()` stores the first `AUTHENTICATION_BACKENDS` entry that has
  `getUser` (normally `ModelBackend`), which loads any user of `AUTH_USER_MODEL` by pk.
- **Callback URL** defaults to the current request path, so one route serves both legs; `callbackURL` overrides it.
  `AuthenticateOptions.next` overrides the `?next=` parameter.
- **Magic links** are `<b64url pk>.<base36 ts>.<HMAC-SHA256>`; the MAC covers pk, password hash, `lastLogin` and email
  (salt `ghuri.oauth.MagicLinkStrategy`), with `SECRET_KEY_FALLBACKS`.
- **JWT:** RS256/384/512, PS256/384/512, ES256/384/512, EdDSA; HS* ID tokens are not accepted. JWKS cached an hour,
  refetched at most once a minute on an unknown `kid`; 60 s leeway.
- **Testing:** `followOAuth(client, startPath, provider, { deny?, method? })` is a function, not a client method; the
  mock answers any token-endpoint POST (`anyTokenEndpoint`) so provider-specific URLs work with `routes`.
- Verified on workerd: OIDC round trip (ES256 signing and verification, HKDF + AES-GCM state cookie, PKCE).

---

## 18. `@ghuri/socialauth` (django-allauth style social login)

Status: **phase 1 built** (as-built notes in 18.9). Repo `ghurijs/socialauth`, npm `@ghuri/socialauth`, peers `@ghuri/core`,
`@ghuri/orm`, `@ghuri/auth`, `@ghuri/oauth`; optional `@ghuri/admin`, `@ghuri/rest`.

"Log in with GitHub / Google / Facebook…" with nothing to write but settings, like django-allauth's
`socialaccount`: a provider catalog on top of `@ghuri/oauth`, models that link provider accounts to users,
signup and account-linking rules, URLs, admin, and a JSON API for SPAs and mobile apps.

```ts
// settings.ts
INSTALLED_APPS: [ContentTypesConfig, AuthConfig, SessionsConfig, SocialAuthConfig, …],
SOCIALACCOUNT: {
  PROVIDERS: {
    github: { APP: { clientId: env.GITHUB_CLIENT_ID, secret: env.GITHUB_SECRET }, SCOPE: ['read:user', 'user:email'] },
    google: { APP: { clientId: env.GOOGLE_CLIENT_ID, secret: env.GOOGLE_SECRET } },
  },
},
// urls.ts
path('accounts/', include(authUrls)),
path('accounts/', include(socialUrls)),     // /accounts/github/login/, /accounts/github/login/callback/, …
```
```html
<form method="post" action="/accounts/github/login/?next=/dashboard/">
  <input type="hidden" name="csrfmiddlewaretoken" value="…"><button>Continue with GitHub</button>
</form>
```

### 18.1 Providers

Built in: `github`, `google`, `facebook`, `microsoft` (Entra ID, `common` or a tenant), `apple` (client secret is
an ES256 JWT signed with the team key, created per request with WebCrypto), `discord`, `gitlab` (and self-hosted),
`twitter` (X, OAuth 2.0 + PKCE), `linkedin` (OIDC), `slack` (OIDC), plus `openid_connect` for any OIDC issuer
(Auth0, Okta, Keycloak, Cognito…), configured as several named apps. Each provider declares its `@ghuri/oauth`
strategy, default scopes, profile mapping and **whether its email is verified** (GitHub: `/user/emails`
primary + verified; Google/Microsoft/Apple/OIDC: `email_verified`; Facebook/Discord/X: per their fields, else
unverified). Custom providers: `registerProvider(new MyProvider())`.

Credentials come from settings (`PROVIDERS.<id>.APP`, usually from env) or from `SocialApp` rows managed in the
admin (allauth's two ways); settings win.

### 18.2 Models (app label `socialaccount`, allauth table names)

- `SocialApp`: `provider`, `providerId` (for several OIDC apps), `name`, `clientId`, `secret`, `key`,
  `settings` (JSON).
- `SocialAccount`: `user` → `AUTH_USER_MODEL`, `provider`, `uid`, `lastLogin`, `dateJoined`, `extraData` (JSON,
  the raw profile); unique `(provider, uid)`.
- `SocialToken` (only when `STORE_TOKENS`): `app`, `account`, `token`, `tokenSecret` (refresh token),
  `expiresAt`; encrypted at rest (AES-GCM, key from `SECRET_KEY`). `getAccessToken(account)` refreshes when
  expired.

### 18.3 The login flow

`<provider>/login/` starts the flow on **POST** (CSRF-protected; GET shows a one-button confirm page unless
`LOGIN_ON_GET`, which allauth also disables by default to stop login CSRF). `process=connect` links instead of
logging in. On the callback:

1. A `SocialAccount (provider, uid)` exists → update `extraData`/tokens, log its user in.
2. The visitor is logged in and `process=connect` → link the account to them (refused if it belongs to someone
   else).
3. `EMAIL_AUTHENTICATION` (default off) and the provider says the email is **verified** and exactly one user has
   that email → link and log in. Unverified emails never link to existing users.
4. Otherwise sign up: if `AUTO_SIGNUP` and the adapter's `populateUser()` produces a valid user (unique
   username derived from the profile, email unless it is taken) → create it with an unusable password, link,
   log in. Else redirect to `signup/` (HTML form or JSON) to collect what is missing.

The response is a redirect to `next` / `LOGIN_REDIRECT_URL`, or for SPAs (`LOGIN_RESPONSE: 'jwt'`) a redirect to
`FRONTEND_URL` with a one-time code that `POST token/` exchanges for a JWT pair (tokens never travel in URLs).

### 18.4 Adapter and signals

`SOCIALACCOUNT.ADAPTER` (class extending `SocialAccountAdapter`) customizes the flow, as in allauth:
`isOpenForSignup(c, login)`, `preSocialLogin(c, login)` (may throw `ImmediateResponse(res)`), `populateUser`,
`newUser`, `saveUser`, `isAutoSignupAllowed`, `getConnectRedirectUrl`, `authenticationError`. Signals:
`preSocialLogin`, `socialAccountAdded`, `socialAccountUpdated`, `socialAccountRemoved`.

### 18.5 URLs (`socialUrls`)

| Route | |
|---|---|
| `providers/` | JSON list of configured providers with login URLs (for SPA buttons). |
| `<provider>/login/` | Start login (POST; GET confirm page). `?next=`, `?process=connect`. |
| `<provider>/login/callback/` | OAuth callback. |
| `<provider>/token/` | **Mobile / native SDKs:** `POST { access_token \| id_token }` obtained by the app itself (Google Sign-In, Sign in with Apple); verified with the provider, then the same steps as the callback. |
| `token/` | Exchange the one-time code from an SPA redirect for a JWT pair. |
| `signup/` | Finish a signup that needs input. |
| `connections/` | List (GET) and disconnect (POST) the user's social accounts. Disconnecting the last login method of a user without a usable password is refused. |

### 18.6 Admin, REST, settings

Admin registers `SocialApp`, `SocialAccount`, `SocialToken` (secrets masked) when `@ghuri/admin` is installed.
`@ghuri/socialauth/rest` offers the same endpoints as DRF-style views for API-first projects.

```ts
SOCIALACCOUNT: {
  PROVIDERS: { <id>: { APP?, SCOPE?, AUTH_PARAMS?, VERIFIED_EMAIL?, … } },
  ADAPTER: SocialAccountAdapter,
  AUTO_SIGNUP: true, EMAIL_AUTHENTICATION: false, EMAIL_REQUIRED: false,
  LOGIN_ON_GET: false, STORE_TOKENS: false,
  LOGIN_RESPONSE: 'session',          // or 'jwt' (needs FRONTEND_URL)
  FRONTEND_URL: undefined,
}
```

### 18.7 Testing

`@ghuri/socialauth/testing`: `socialLogin(client, 'github', { id: '1', email: 'a@x.dev', emailVerified: true })`
runs the whole flow against a mocked provider (`@ghuri/oauth/testing`) and leaves the client logged in.

### 18.8 Phases

1. `@ghuri/oauth` (strategies, `authenticate`, state cookie, OIDC validation, testing) and `@ghuri/socialauth`
   with GitHub, Google, Facebook, Microsoft, Discord, GitLab, generic OIDC, models, flow, adapter, URLs, admin,
   SPA/JWT and native-token endpoints.
2. Apple, X, LinkedIn, Slack; `@ghuri/rest` views; refresh-token helpers; email confirmation for unverified
   signups (with `@ghuri/mail`).

### 18.9 As built (supersedes 18.1–18.8 where they conflict)

- **Native tokens:** `id_token` for OIDC providers (audience = client id or `settings.audiences`), `access_token` only
  where the provider can confirm it was issued to us: GitHub (`POST /applications/{client_id}/token`) and Facebook
  (`debug_token`). Discord refuses native tokens.
- **Emails:** Microsoft (Entra ID) and Facebook emails are unverified unless `VERIFIED_EMAIL: true`.
- **Pending signup** lives in an encrypted 10-minute cookie (`ghuri_social_signup`), not the session, so it works
  for SPAs and sessionless setups.
- **SPA codes** are sealed `{ uid, exp, jti }` (60 s); reuse is refused while the configured cache remembers the `jti`.
- **CSRF:** `<provider>/token/` and `token/` are CSRF-exempt and accept JSON bodies only (cross-site forms can't send
  JSON). Starting a login is a POST through `CsrfMiddleware`; GET shows a confirm page unless `LOGIN_ON_GET`.
- **Errors** in browser flows redirect to `LOGIN_ERROR_URL` (new setting, default `LOGIN_URL`) with `?error=`, or to
  `FRONTEND_URL#error=` in JWT mode; API flows answer `{ detail, code }`.
- **Admin** is opt-in: `import '@ghuri/socialauth/admin'` registers the three models (`@ghuri/admin` is an optional peer).
- **`@ghuri/auth` 0.1.0-alpha.2** exports `migrationsForUserModel`, so `socialaccount`'s migration follows
  `AUTH_USER_MODEL`.
- Not yet (phase 2): Apple, X, LinkedIn, Slack; `@ghuri/rest` views; email confirmation for unverified signups.

---

## 19. `@ghuri/oauth-provider` and MCP authorization (as built)

Goal: any Ghuri app can host a remote MCP server that Claude.ai, ChatGPT, Claude Code and Codex connect to with OAuth,
portably (D1 / Postgres / SQLite, Workers / Node). Follows the MCP authorization spec of revision 2026-07-28, OAuth 2.1,
RFC 8414, 7591, 7009, 8707, 9068, 9207, 9728, 8252 §7.3 and the Client ID Metadata Document draft. A separate package
from `@ghuri/oauth` (clients) the way django-oauth-toolkit is separate from allauth: it brings models, migrations and
optional `@ghuri/rest` / `@ghuri/admin` integration that login-only apps should not carry.

### 19.1 `@ghuri/oauth-provider`

- **App** `OAuth2ProviderConfig`, label `oauth2_provider`, settings `OAUTH2_PROVIDER`, tables `oauth2_provider_*`,
  command `cleartokens` (django-oauth-toolkit names). Migration follows `AUTH_USER_MODEL` (`migrationsForUserModel`).
- **Models:** `Application` (client; `registrationType` manual / dynamic / metadata_document; whitespace-separated
  `redirectUris` and `grantTypes`; `clientSecret` is `sha256$<b64url>`), `Grant`, `AuthorizationCode`, `RefreshToken`.
  **Deliberate difference:** django-oauth-toolkit's `Grant` is the authorization code; here `Grant` is the user's
  consent (user × client × scope × resource × `props`, `revoked`), the unit of revocation, and the code is
  `AuthorizationCode`. There is no `AccessToken` model.
- **Tokens:** access tokens are RFC 9068 JWTs (`typ: at+jwt`; `iss`, `sub`, `aud` = canonical resource, `client_id`,
  `scope`, `jti`, `iat`, `exp`, `gid` = grant). Default HS256 with a key derived by HKDF from `SECRET_KEY` (fallbacks
  verify); ES256 / RS256 / EdDSA with `ACCESS_TOKEN_SIGNING_KEY` (JWK) and `/.well-known/jwks.json`.
  `verifyAccessToken(token, { audience })` also checks the grant is active (`CHECK_GRANT_ON_ACCESS`, one indexed query),
  so revocation is immediate. Codes (60 s, single use via conditional `UPDATE`; replay revokes the grant) and refresh
  tokens (rotated on every use; reuse revokes the grant; `REFRESH_TOKEN_GRACE_PERIOD_SECONDS`) are stored as SHA-256
  hashes. Revoking any token (RFC 7009) revokes its grant.
- **Endpoints:** `oauth2ProviderUrls` (namespace `oauth2_provider`: `authorize`, `token`, `revoke-token`, `register`) and
  `oauth2WellKnownUrls` (RFC 8414 metadata at `/.well-known/oauth-authorization-server[/<issuer path>]`, JWKS). PKCE
  `S256` only; `iss` on every authorization response; errors before the client and redirect URI are verified render a
  page and never redirect; token / revoke / register are CSRF-exempt, form-encoded (register: JSON), `no-store`, CORS
  `*`. Issuer = `ISSUER` or the request origin. Resource indicators are canonicalised (lowercase scheme / host, no
  default port, fragment or trailing slash) and limited to the issuer's origin unless `RESOURCES` says otherwise
  (`invalid_target`).
- **Consent:** default server-rendered page (client name, scopes, redirect host, loopback warning, `X-Frame-Options:
  DENY`, CSRF) or `CONSENT_HANDLER` / `authorizationView({ consent })`, which gets `{ request, client, user, scopes,
  pending, action, form, approve({ scope, props }), deny() }`. The pending request round-trips sealed (AES-GCM,
  `seal()` from `@ghuri/oauth`) and bound to the user. Auto-approval when an active grant covers the scopes
  (`REQUEST_APPROVAL_PROMPT: 'auto'`) or `skipAuthorization`.
- **Clients:** CIMD for `https://` client ids with a path (exact `client_id` match, `none` auth, https / loopback
  redirect URIs; https only on 443, no IP literals / localhost / single-label / internal suffixes, no redirects, 5 KB,
  5 s; cached as `Application` rows by `Cache-Control`, clamped 5 min – 24 h; `CLIENT_METADATA_ALLOWED_HOSTS`,
  `CLIENT_METADATA_POLICY`). Workers cannot resolve DNS before fetching, so DNS-rebinding to private addresses is not
  detectable there; the allowlist is the mitigation. RFC 7591 registration (`ALLOW_DYNAMIC_REGISTRATION`, per-IP
  `REGISTRATION_RATE` on the default cache; `grant_types` defaults to code + refresh). Loopback redirect URIs match on
  any port; everything else is an exact string match.
- **Integrations:** `@ghuri/oauth-provider/rest` (`OAuth2Authentication` with an `audience`, `TokenHasScope` +
  `requiredScopes`), `@ghuri/oauth-provider/admin` (revoke-grants action; hashes never shown).
- `@ghuri/oauth` now exports `sha256` and `timingSafeEqual` for it.

### 19.2 `@ghuri/agents` OAuth mode and protocol 2026-07-28

- `McpServer({ oauth: { verifyAccessToken, authorizationServers?, resource?, scopesSupported?, requiredScopes?,
  impliedScopes?, hideUnauthorizedTools?, resourceName?, resourceDocumentation? } })`. The verifier is a plain function
  (`@ghuri/agents` does not depend on `@ghuri/oauth-provider`). The audience is the canonical MCP URL of the request
  (or `resource`).
- `server.wellKnownUrls` / `mcpWellKnownUrls(...servers)`: RFC 9728 metadata at `/.well-known/oauth-protected-resource`
  and `/.well-known/oauth-protected-resource/<mcp path>` (a suffix is served only when it routes to that server).
- 401 `WWW-Authenticate: Bearer resource_metadata="…", scope="<requiredScopes>"` (`error="invalid_token"` when a token
  was presented); 403 `error="insufficient_scope", scope="<granted ∪ needed>"` for tools (and `requiredScopes`) the
  token does not cover. Tools carry `scopes` (`tool({ scopes })`, toolkit option `scopes`, `requireScopes()`); hidden
  from `tools/list` unless `hideUnauthorizedTools: false`.
- Protocol: `2026-07-28` is served next to the legacy revisions on one endpoint (dual-era). A request is modern when its
  `MCP-Protocol-Version` header is ≥ 2026-07-28 or its `_meta` carries `io.modelcontextprotocol/protocolVersion`.
  Modern requests: no `initialize` / session; `_meta` version + client capabilities required (`-32602`, 400); header
  checks (`-32020`, 400; `=?base64?…?=` decoded); unsupported version `-32022` (400, `data.supported` / `requested`);
  `server/discover`; `resultType: 'complete'` and `serverInfo` in `_meta`; `ttlMs` / `cacheScope` on lists (`private`
  in OAuth mode); unknown or removed methods (`ping`, `logging/setLevel`) 404 / `-32601`; batches refused. `initialize`
  negotiates the newest legacy revision (`2025-11-25`). No SSE (subscriptions/listen, MRTR, tasks not implemented).
