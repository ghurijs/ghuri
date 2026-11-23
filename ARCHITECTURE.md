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
| `tasks` | `@ghuri/tasks` | `django.tasks`-style background tasks: `task()`, `TaskResult`, Cloudflare Queues / database / immediate / dummy backends, retries, periodic tasks, `db_worker` (section 20) | core, orm, (optional) admin |
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

`@ghuri/tasks` (Cloudflare Queues + Node worker; specified in section 20), `@ghuri/forms` (standalone forms), i18n, Redis cache, read replicas / DB routers, `@ghuri/realtime`
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
`setupTestDatabase`. Not yet: `squashmigrations`, `inspectdb`, PK/auto-field changes.

**orm swappable models** (as built): `Meta.swappable = 'SETTING'` (dotted names read nested settings,
`'AGENTS.CONVERSATION_MODEL'`); `_meta.swapped` is the other label when the setting names another model, read from the
current settings (historical models never are). A swapped model is skipped by `ModelRegistry.register` (so not in
`apps`, the autodetector, test databases or dumpdata), its relations wire no reverse relations, and its managers throw
Django's "Manager isn't available" (as `ImproperlyConfigured`). `getSwappableModel(setting, default)` generalises
`getUserModel()`. Migration markers: `swappableModel(setting, default)` as a field's `to` (a getter on the normalized
options, so every reader sees a string) and `swappableDependency(setting, default)` (an array whose `[0]` is a getter).
**Deliberate differences from Django:** the dependency resolves to the migration that `CreateModel`s the swapped-in
model (Django: always `__first__`), falling back to `__first__` when that migration depends on the origin; edges from
it are ignored by the consistency check (an applied migration may precede a model swapped in later); own-app
`__first__` dependencies are ignored; swapped models are not returned by `apps.getModel()` (as `auth.User` already
wasn't). The loader drops a swapped model's operations (`CreateModel` with `options.swappable` and later ops on that
model) instead of keeping them in state with no database effect. `makemigrations` emits the markers for relations to
any model named by a swappable setting and records `swappable` in `CreateModel` options (not an `AlterModelOptions`
key). `@ghuri/auth` keeps its own `migrationsForUserModel()` adapter for its bundled files.

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
`HostResolver`, functions) and honours `TENANTS.REQUIRED`, except for views marked `tenantNotRequired(view)` (Django's
`login_not_required`; marker `Symbol.for('ghuri.tenantNotRequired')`, set by `@ghuri/billing`'s webhook without an
import), which run with no tenant; `TenantNotFound` is an `Http404`, `CrossTenantError` a
`PermissionDenied` (403). Host resolvers read core's `getHost()` (`X-Forwarded-Host` only with `USE_X_FORWARDED_HOST`).
`tenantModel({ extends })` inherits an abstract model (e.g. `AbstractBaseUser`) for per-tenant users, which get their
own JWT classes through `@ghuri/auth`'s `JWTToken.userModel()` / `tokenType`. `uuid7()` is monotonic per process. Also `tenantCache()`,
`uuid7()`, and `assertTenantIsolation()` in `@ghuri/tenants/testing`. Not yet: per-tenant database routing,
`dumpdata --tenant`, Postgres RLS, admin integration, a REST membership permission class.

**Context carriers** (core, no Django equivalent): `registerContextCarrier({ name, capture, restore })`,
`captureContext()` → `Record<string, string>`, `restoreContext(captured, fn)`. Lets request-scoped state cross a queue
or service boundary without the sender importing the package that owns it. `@ghuri/tenants` registers `tenant`
(pk; `restore` loads the tenant under `withoutTenant()` and runs `runAsTenant()`, `TenantNotFound` when gone;
`withoutTenant()` is deliberately not carried). Unknown keys are ignored. Siblings read these functions off the core
namespace (`(core as any).captureContext?.()`) so they keep working with older core releases.

**agents, gateway and traces** (as built): `AgentJob.carried` holds `captureContext()` and the queue consumer runs
inside `restoreContext()`, so queued runs keep their tenant. `resolveModel(model, env?, run?)` passes
`ProviderContext.run = { agent, user, carried }` (model resolution still happens before the conversation exists, so
no conversation id), and `PROVIDERS[name].headers` may be a function of that context. Built-in `ghuri-ai:` provider:
`<alias>` → `<baseURL>/v1/chat/completions` (OpenAI-compatible), `anthropic/<id>` and `openai/<id>` → pass-through
routes `<baseURL>/v1/anthropic` / `/v1/openai` with the provider SDKs; headers `x-ghuri-agent`, `x-ghuri-user`,
`x-ghuri-<carrier>`. The chat view maps provider `APICallError`s (also inside `RetryError`): 429 → `Throttled` with
`Retry-After`, 401/402/403 → `ModelUnavailable` (503); API exceptions are never remapped. `runFinished` signal after
every run (robust: receiver errors are logged). Opt-in `AGENTS.TRACE_RUNS` writes `agents.Run` (migration
`0002_run`; tenant kept as the carried JSON, not a FK, so agents does not depend on tenants); a failed trace write
warns once and never fails the run. `agents.Conversation` is swappable with `AGENTS.CONVERSATION_MODEL`
(`conversationFields`, `AbstractConversation`, `getConversationModel()`); memory, views, `Message.conversation` and
`Run.conversation` follow it, so a `StoreModel({ ...conversationFields })` scopes conversations to the tenant (another
store's is a 404). `Message` is not swappable: messages are reached through their conversation. The agents migrations
use the swappable markers instead of the old load-time `AUTH_USER_MODEL` adapter. Swapping on an existing database:
the project model sets `dbTable: 'agents_conversation'` and its migration adopts the table (`managed: false`
`CreateModel` + `AlterModelOptions`, then a `RunCode` that adds the tenant column, or creates the table on a new
database), with no dependency on `agents`.

**agents evals** (as built): `@ghuri/agents/evals` (separate entry, test-time only): `defineEval` / `runEval` /
`formatEvalReport`, deterministic checks plus `judge()` (a model grades against a rubric; verdict parsed from a JSON
object in its answer). Attempts run sequentially with `memory: false`, the model swapped by assigning
`agent.model`; usage is the run total; cost from per-suite `prices` ($/MTok, cache reads separate). `ghuri eval`
writes `node_modules/.ghuri/vitest.eval.config.mjs` (the project's vitest config with `include` replaced by the eval
globs, `fileParallelism: false`, `silent: false`, long timeouts) and passes options as `GHURI_EVAL_*` env vars. No
Django equivalent.

**agents tool shaping** (as built, all opt-in): `toolSearch` registers every tool in the AI SDK tool set plus
`find_tools`, and limits what is sent with `activeTools` / `prepareStep` to `alwaysLoaded` + `find_tools` + names
found in earlier `find_tools` results in the messages (so loads persist across turns through stored history, with no
extra state). Search is plain word scoring over name, title and description (trailing plural stripped), no
embeddings. `strictToolInput` checks only the top level of the JSON Schema; problems are recorded in `validate` and
thrown from `execute` (a `WeakMap` on the arguments object) so the model gets the plain `ToolInputError` text rather
than the AI SDK's wrapped validation error, and the history keeps the raw arguments. `resultFields` / `compact`
shape results after `invoke()` (rows of `results` for paginated lists). `examples` are rendered into the
description (portable across providers) rather than provider-specific input-example fields.

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

## 20. `@ghuri/tasks` (Django 6.0 `django.tasks` style background tasks)

Status: **0.1 built** (see 20.11 for where it differs from this text). Repo `ghurijs/tasks`, npm `@ghuri/tasks`, peers `@ghuri/core` (required) and
`@ghuri/orm` (optional: the `tasks` app, result storage and the database backend).

Django 6.0 added `django.tasks`: a `@task` decorator, `task.enqueue()`, pluggable backends chosen in the `TASKS`
setting, `TaskResult` objects and three signals. Django ships only the `ImmediateBackend` and `DummyBackend`; the
`django-tasks` package adds a `DatabaseBackend` and the `db_worker` command. Ghuri implements that API, with the same
names, and adds what a Cloudflare-first framework needs:

- a **Cloudflare Queues** backend (the default on Workers),
- a **database** backend that runs on Postgres, SQLite and D1 (the default on Node),
- **retries** and **periodic tasks**, which `django.tasks` leaves to backends and Celery beat,
- **context carriers** (tenant, …) restored around every run, as agents already do (§14).

It replaces the queue code in `@ghuri/agents` (`enqueueRun` / `consumeAgentQueue`) with ordinary tasks.

```ts
// src/blog/tasks.ts
import { task } from '@ghuri/tasks'
import { sendMail } from '@ghuri/mail'
import { Post } from './models'

export const notifySubscribers = task(async (postId: number) => {
  const post = await Post.objects.get({ pk: postId })
  await sendMail({ subject: `New post: ${post.title}`, message: post.summary, recipientList: await post.subscriberEmails() })
  return { notified: true }
}, { queueName: 'emails', maxAttempts: 3 })

export const cleanUpDrafts = task(async () => {
  await Post.objects.filter({ status: 'draft', updatedAt__lt: daysAgo(30) }).delete()
})

// src/blog/app.ts — tasks are registered like models: '<app label>.<export name>' ('blog.notifySubscribers')
import { AppConfig } from '@ghuri/core'
import { periodicTask } from '@ghuri/tasks'
import * as tasks from './tasks'
import { cleanUpDrafts } from './tasks'
export class BlogConfig extends AppConfig {
  name = 'blog'
  tasks = tasks
  ready() {
    periodicTask('0 3 * * *', cleanUpDrafts)       // also listed in wrangler.jsonc "triggers.crons"
  }
}

// a view, a signal receiver, an agent tool…
const result = await notifySubscribers.enqueue(post.pk)          // TaskResult, status READY
const later = await notifySubscribers.using({ runAfter: inMinutes(10) }).enqueue(post.pk)
const fresh = await notifySubscribers.getResult(result.id)       // needs a backend with supportsGetResult
```

```ts
// src/settings.ts
TASKS: {
  default: env.TASKS_QUEUE ? cloudflareQueues({ queues: { default: 'TASKS_QUEUE', emails: 'EMAILS_QUEUE' } })
                           : database(),                           // Node + Postgres / SQLite
},
INSTALLED_APPS: [..., TasksConfig],                                // result rows, admin, db backend tables
```
```jsonc
// wrangler.jsonc
"queues": {
  "producers": [{ "binding": "TASKS_QUEUE", "queue": "mysite-tasks" }, { "binding": "EMAILS_QUEUE", "queue": "mysite-emails" }],
  "consumers": [{ "queue": "mysite-tasks", "max_retries": 5 }, { "queue": "mysite-emails", "max_retries": 5 }]
},
"triggers": { "crons": ["0 3 * * *"] }
```

### 20.1 Tasks

```ts
export function task<A extends JsonValue[], R>(
  fn: (...args: A) => R | Promise<R>,                    // or (context: TaskContext, ...args) with takesContext
  options?: {
    name?: string                  // required when the task is not exported from an app's `tasks` module
    priority?: number              // -100..100, default 0 (DEFAULT_TASK_PRIORITY)
    queueName?: string             // default 'default' (DEFAULT_TASK_QUEUE_NAME)
    backend?: string               // TASKS alias, default 'default'
    runAfter?: Date | null
    takesContext?: boolean
    maxAttempts?: number           // Ghuri: default 1 (no retries, as Django)
    retryDelay?: number | ((attempt: number) => number)   // Ghuri: seconds, default exponential 2^attempt capped at 1 h
  },
): Task<A, R>

export class Task<A, R> {
  readonly name: string            // 'blog.notifySubscribers' — Django's module_path
  readonly priority, queueName, backend, runAfter, takesContext, maxAttempts
  using(overrides: { priority?, queueName?, runAfter?, backend? }): Task<A, R>   // returns a copy
  enqueue(...args: A): Promise<TaskResult<R>>       // Django's enqueue + aenqueue (all I/O is async)
  getResult(id: string): Promise<TaskResult<R>>     // Django's get_result / aget_result
  call(...args: A): Promise<R>                      // run now, in-process (Django's task.call)
}
```

- **Names.** Workers have no module paths, so a task is identified by `<app label>.<export name>`, filled in when
  `apps.populate()` walks `AppConfig.tasks` (new optional property, next to `models`). A task outside an app passes
  `name`. Enqueuing an unnamed task raises `InvalidTask`. Two tasks with one name raise `ImproperlyConfigured` at
  populate. The worker looks tasks up by name, so renaming a task strands messages already queued (documented).
- **Arguments** are positional and must round-trip through JSON unchanged (Django's rule, minus kwargs). `Date`,
  `Map`, model instances and `undefined` raise `InvalidTask` at enqueue. Pass primary keys, not instances.
- **Validation** at enqueue, as Django: `InvalidTask` when the backend lacks `supportsDefer` and `runAfter` is set,
  lacks `supportsPriority` and `priority` is not 0, or `queueName` is not in the backend's `QUEUES`.
- **Context.** `takesContext: true` passes `TaskContext { taskResult, attempt }` as the first argument.
- **Carriers.** `enqueue()` stores `captureContext()` (§14) with the task and the worker runs inside
  `restoreContext()`, so a task enqueued during a tenant's request runs as that tenant. The request **user is not
  carried** (as in Django); pass a user pk. Deliberate difference: Django has no carriers.
- **Transactions.** Enqueue after the data a task reads is committed: `onCommit(() => notify.enqueue(post.pk))`
  (`@ghuri/orm`). Not automatic, as in Django.

### 20.2 Results

```ts
export enum TaskResultStatus { READY = 'READY', RUNNING = 'RUNNING', FAILED = 'FAILED', SUCCESSFUL = 'SUCCESSFUL' }

export class TaskResult<R> {
  readonly id: string                       // uuid7
  readonly task: Task<any, R>
  readonly status: TaskResultStatus
  readonly enqueuedAt, startedAt, finishedAt, lastAttemptedAt: Date | null
  readonly args: JsonValue[]
  readonly backend: string
  readonly errors: TaskError[]              // { exceptionClassPath, traceback } — one per failed attempt
  readonly workerIds: string[]
  readonly attempts: number
  readonly isFinished: boolean
  get returnValue(): R                      // throws `TaskResultNotReady` until SUCCESSFUL (Django: ValueError)
  refresh(): Promise<void>                  // Django's refresh / arefresh
}
```

Return values must be JSON; a value that is not fails the task. Results are stored in `tasks.DBTaskResult`
(table `tasks_dbtaskresult`, django-tasks' columns in snake_case, `task_name` for `task_path`) when the `tasks` app is
installed. Without it, only `immediate()` and `dummy()` can answer `getResult()`.

### 20.3 Backends

```ts
interface TaskBackend {
  alias: string
  readonly supportsDefer: boolean
  readonly supportsGetResult: boolean
  readonly supportsPriority: boolean
  enqueue(task, args): Promise<TaskResult>
  getResult(id): Promise<TaskResult>
  check(): CheckMessage[]
}
export const taskBackends: { get(alias): TaskBackend; all(): TaskBackend[] }   // like `caches`
export const defaultTaskBackend: TaskBackend
```

| | `immediate()` | `dummy()` | `cloudflareQueues(opts)` | `database(opts)` |
|---|---|---|---|---|
| Django name | `ImmediateBackend` | `DummyBackend` | — | `django-tasks` `DatabaseBackend` |
| Runs | inside `enqueue()` | never (stores) | Queue consumer (`app.queue`) | `ghuri db_worker` (Node) or a cron drain (Workers) |
| `supportsDefer` | no | yes | yes, up to 12 h (Queues' `delaySeconds` limit; later raises `InvalidTask`) | yes |
| `supportsPriority` | no | yes | no | yes |
| `supportsGetResult` | yes | yes | with the `tasks` app | yes |
| Retries | no | — | `msg.retry({ delaySeconds })` | `run_after` set to the retry time |
| Default for | `DEBUG` and tests | tests | Workers | Node |

**`cloudflareQueues({ queues: { <queueName>: <producer binding> }, results?: boolean })`.**
- Sends `{ type: 'ghuri.tasks.run', task, id, args, attempt, carried }` (128 KB message limit → `InvalidTask`).
- Registers one `onQueue('*')` consumer that handles only messages of that type, so agent jobs and the app's own
  messages pass through untouched.
- Each message is acked on success. On failure it is retried with `retryDelay` until `maxAttempts`, then marked
  `FAILED` and acked, so Cloudflare's `max_retries` is a safety net, not the policy.
- `ghuri check` warns when a consumer's `max_retries` (read from wrangler.jsonc) is lower than a task's
  `maxAttempts - 1`.
- Consumers get 15 minutes of wall time per batch. Longer work should be split into tasks that enqueue the next one
  (Cloudflare Workflows support is phase 3).

**`database({ alias?: 'default', pollInterval?: 1, batchSize?: 1 })`.**
- Stores tasks in `tasks_dbtaskresult` on any `DATABASES` alias, so it is in the portability matrix.
- Claims work atomically:
  - Postgres: `SELECT … FOR UPDATE SKIP LOCKED`, any number of workers.
  - SQLite: `UPDATE … WHERE id = (SELECT …) RETURNING`, one worker per database file is recommended.
  - D1: the same `UPDATE … RETURNING`, run by `drainTasks({ seconds: 25 })`, which the app registers under a cron
    (`onSchedule('* * * * *', drainTasks)`). That gives apps that do not use Queues background work with minute
    granularity.
- `ghuri db_worker [--queue-name …] [--interval 1] [--batch 1] [--max-tasks N] [--worker-id …] [--beat]` (Node,
  `@ghuri/tasks/commands`). It stops after the current task on SIGTERM and records its id in `workerIds`.
- `ghuri prune_db_task_results [--min-age-days 14] [--only-complete]` as in django-tasks.
- A task found `RUNNING` past `OPTIONS.STALE_AFTER` (default 1 h; its worker died) is retried or failed by the next
  worker.

### 20.4 Periodic tasks (Ghuri; Django has none)

- `periodicTask(cron, task, { args?, inline? })` registers an `onSchedule(cron)` handler that enqueues the task (or
  runs it in the handler with `inline: true`). The task is enqueued with `runAfter` unset and the carriers of
  no request.
- **Workers:** the cron must be listed in `triggers.crons`. `ghuri check` reports `tasks.E003` for one that is
  missing.
- **Node:** core gains a scheduler in `@ghuri/core/node`, `startScheduler(app)`, which fires every cron registered
  with `onSchedule` (using `croner`, Node-only). `serve({ scheduler: true })` and `ghuri db_worker --beat` start it.
  Like Celery beat, **run it in exactly one process**. This also makes plain `onSchedule()` work on Node, which it
  does not today.

### 20.5 Signals and admin

- Signals (`@ghuri/tasks`): `taskEnqueued` (sender: backend class, `{ taskResult }`), `taskStarted`, `taskFinished`
  (`{ taskResult }`, status final). Same names as Django's `task_enqueued` / `task_started` / `task_finished`.
- `@ghuri/tasks/admin` registers `DBTaskResult`:
  - read-only, with list filters on status, queue and task, and search by id;
  - actions "Run again" (enqueue a copy) and "Mark failed".

### 20.6 Settings and checks

```ts
TASKS: {
  default: cloudflareQueues({ queues: { default: 'TASKS_QUEUE' } }) | database() | immediate() | dummy(),
  // per backend: QUEUES (allowed queue names; default ['default']), OPTIONS
}
```
Missing `TASKS` means `{ default: immediate() }`, as Django.

Checks:
- `tasks.E001` unknown backend.
- `tasks.E002` a task's `queueName` is not in its backend's `QUEUES`.
- `tasks.E003` a periodic cron is not in wrangler.jsonc.
- `tasks.W001` `immediate()` with `DEBUG = false`.
- `tasks.W002` Queues `max_retries` is below a task's `maxAttempts - 1`.
- `tasks.W003` `database()` without the `tasks` app.

Errors (extend `GhuriError`): `InvalidTask`, `InvalidTaskBackend`, `TaskResultDoesNotExist`, `TaskResultMismatch`,
`TaskResultNotReady`.

### 20.7 Testing

- `@ghuri/tasks/testing`:
  - `useTaskBackend(dummy())` for a test, then `backend.results`, `backend.clear()`;
  - `await backend.runPending()` (Ghuri: runs the stored tasks in-process, with carriers and retries);
  - `captureTasks(fn)` returns the tasks enqueued while `fn` ran.
- Package tests:
  - the database backend on SQLite, PGlite and D1 (Miniflare), including concurrent claims on PGlite;
  - `cloudflareQueues` against Miniflare queues (send, delay, retry, final failure, carriers).
- `examples/blog` adds `notifySubscribers` and a nightly cleanup. `scripts/portability.sh` runs one task through the
  database backend on Node + Postgres and through Queues on Workers.

### 20.8 Changes in other packages

| Package | Change |
|---|---|
| core | `AppConfig.tasks`, registered at populate through an `onPopulate` hook; `startScheduler(app)` and `serve({ scheduler })` in `@ghuri/core/node` |
| agents | `agent.enqueue()` becomes the task `agents.run` when `@ghuri/tasks` is installed (retries, results, the database backend on Node); `consumeAgentQueue` stays for one minor version, deprecated |
| mail | optional `sendMail({ …, defer: true })` via a `mail.send` task (phase 2) |
| cli | `startproject` adds `TASKS` settings and, with `--cloudflare`, the Queue producer/consumer and an empty `triggers.crons`; `startapp` adds an empty `tasks.ts` and `tasks = tasks` in `app.ts` |
| docs | topic "Background tasks", `django.tasks` and Celery cheat-sheet rows, Cloudflare Queues deployment section |

### 20.9 Phases

1. **0.1**:
   - `task()`, `Task`, `TaskResult`, signals;
   - `immediate`, `dummy`, `cloudflareQueues` and `database` backends, `db_worker`, `prune_db_task_results`;
   - the `tasks` app with admin, periodic tasks, the core Node scheduler, testing helpers, checks, the blog example.
2. **0.2**: agents on tasks, `mail` deferred sending, unique tasks (`unique: (args) => key`, skipped while one is
   pending), task chaining (`.then(otherTask)`).
3. **Later**: Redis backend, AWS SQS backend, Cloudflare Workflows for durable multi-step tasks, rate limits per queue.

### 20.10 Open questions (proposed answers)

- **Default retries.** Django has none, so `maxAttempts` defaults to 1. *Proposed:* keep 1. Queued agent runs set 3.
- **Command name.** `db_worker` (django-tasks) breaks Ghuri's habit of commands without underscores. *Proposed:*
  keep `db_worker` and `prune_db_task_results` for parity, and add `ghuri worker` as an alias that picks the worker
  for the default backend.
- **Results on Queues.** Writing a `DBTaskResult` row per task costs three D1 writes. *Proposed:* on when the `tasks`
  app is installed. `cloudflareQueues({ results: false })` turns it off for high-volume, fire-and-forget queues.

### 20.11 As built (supersedes 20.1–20.10 where they conflict)

- **Peers:** `@ghuri/orm` is required (the `DBTaskResult` model is in the main entry); `@ghuri/admin` is optional
  (`@ghuri/tasks/admin`). The main entry imports nothing Node-only; `db_worker --beat` and the wrangler checks use
  dynamic imports with computed specifiers.
- **Names:** `task.modulePath` is the id (`'blog.notifySubscribers'`); `task.name` is the export name, as Django's
  `name` is the function name. `runAfter` is not a `task()` option, only `using({ runAfter })` (as Django), and is
  a `Date` or seconds after enqueue.
- **Backend flags** follow Django's table: `immediate()` supports priority (no effect), not defer or `getResult()`;
  `dummy()` supports defer and priority, not `getResult()`. Unsupported `getResult()` throws `NotImplementedError`
  (exported). Flags are getters, so `cloudflareQueues()` reports `supportsGetResult` only when results are stored.
- **`TaskError`** is `{ exceptionClassPath, traceback }` (class name, stack).
- **Table:** column `task_path` (django-tasks' name), plus `max_attempts`, `attempts`, `carried`; index
  `tasks_dbtaskresult_ready_idx (status, queue_name, priority)`. Ids are UUIDv7, strictly increasing per process, so
  tasks enqueued in one millisecond run in enqueue order.
- **Claiming** is a compare-and-set `UPDATE … WHERE pk = ? AND status = 'READY'` after selecting the next row
  (priority desc, `enqueuedAt`, id), not `SKIP LOCKED`: one code path for Postgres, SQLite and D1. Racing workers are
  tested on all three. `database({ database, staleAfter })`.
- **Queues:** the maximum `delaySeconds` is 24 hours (not 12); the default consumer `max_retries` is 3. The consumer
  is one `onQueue('*')` registered by `cloudflareQueues()`. A message that is not a task is left to other handlers,
  and retried when the queue has no other handler (core's rule for unhandled queues).
- **Checks:** `tasks.E004` (was W003) for `database()` without the app, plus `tasks.E005` (producer binding missing
  from wrangler.jsonc) and `tasks.W004` (queue without a consumer).
- **Commands:** `db_worker [--backend] [--queue-name] [--interval] [--batch] [--max-tasks] [--worker-id] [--beat]`;
  `prune_db_task_results [--backend] [--queue-name] [--min-age-days] [--only-failed] [--dry-run]`. The `ghuri
  worker` alias is not built.
- **Core** (unreleased): `parseCron` / `isValidCron` with Cloudflare semantics (UTC, day of week 1-7 with 1 = Sunday,
  names, `L`, `W`, `#`; both day fields restricted → either matches), `startScheduler(app, opts)` and
  `serve({ scheduler })` in `@ghuri/core/node`, `taskHandlers.crons()`, `AppConfig.tasks`.
- **Agents on tasks:** `@ghuri/tasks` publishes `globalThis[Symbol.for('ghuri.tasks.interop')] = { version: 1, task,
  getTask }`. `@ghuri/agents` does not depend on it (a missing package breaks a Workers bundle even behind a dynamic
  import): an `onPopulate` hook defines the `agents.run` task (`maxAttempts: 3`) when the interop object exists, and
  `agent.enqueue()` uses it unless `AGENTS.ENQUEUE: 'queue'`, `AGENTS.QUEUE_BINDING` or `opts.binding` asks for the
  Queue path. It returns `{ conversationId, taskResult, taskResultId }`. Workers find agents by name in a global
  registry filled by `AgentRouter.register()` / `registerAgent()`. `consumeAgentQueue` is **not** deprecated: it is
  the background path without `@ghuri/tasks`.
- **CLI and example:** `startproject` installs `TasksConfig` with `TASKS: { default: env.TASKS_QUEUE ?
  cloudflareQueues(...) : database() }` (`database()` for `--db sqlite`), an `npm run worker` script, a
  `<name>-tasks` queue and an empty `triggers.crons` in `wrangler.jsonc`; `startapp` writes `tasks.ts` and
  `tasks = tasks`. Generated code does not use `serve({ scheduler })` while the template's core range predates it.
  `examples/blog` has `publishPost` / `purgeRejectedComments` (periodic, `0 3 * * *`), background agent runs, and
  `scripts/portability.sh` runs a task with `ghuri db_worker` on PGlite before serving on Node.
- **Workers start-up (0.1.0-alpha.1):** nothing may make random values, set timers or do I/O while a module loads
  (workerd refuses the whole Worker). 0.1.0-alpha.0 made the backends' worker id at module scope and no Worker with
  `@ghuri/tasks` could start; the id is now made on first use. `test/workerd.test.ts` bundles a project and runs it in
  workerd with D1 and a real Miniflare Queue producer and consumer (enqueue in a request → `queue()` handler →
  `SUCCESSFUL`), so start-up and Queues are tested end to end.

---

## 21. `@ghuri/vectors` (embeddings, vector stores and retrieval)

Status: **0.1 built** (see 21.11 for where it differs from this text). Repo `ghurijs/vectors`, npm `@ghuri/vectors`,
peers `@ghuri/core` and `@ghuri/orm` (required) and `@ghuri/agents` (optional: `@ghuri/vectors/agents`).

AI SaaS apps need retrieval: embed documents, store the vectors, find the chunks closest to a question and hand them
to a model. D1 has no vector type, so Cloudflare apps use **Vectorize**; Node apps use **pgvector**. Ghuri puts both
behind adapters chosen in settings, like `CACHES` and `TASKS`, so the same app code runs on Workers + D1 + Vectorize
and on Node + Postgres + pgvector.

Django has no vector store. The closest analogues, whose names Ghuri borrows, are:

- **django-haystack** for indexes of models: `SearchIndex` → `ModelIndex`, `index_queryset` → `indexQueryset`,
  the realtime signal processor → `autoIndex`, and the commands `update_index`, `clear_index` and `rebuild_index`;
- **pgvector-python** (`pgvector.django`) for pgvector: `vector(n)` columns, the `hnsw` / `ivfflat` index types with
  `m`, `ef_construction` and `lists`, and the `vector_cosine_ops` / `vector_l2_ops` / `vector_ip_ops` opclasses.
  Its `VectorField` and `CosineDistance` / `L2Distance` / `MaxInnerProduct` belong to phase 2 (21.9).

```ts
// src/settings.ts
import { pgvector, vectorize, VectorsConfig } from '@ghuri/vectors'
export default defineSettings((env) => ({
  INSTALLED_APPS: [..., VectorsConfig],          // the document manifest (and the databaseStore() table)
  VECTORS: {
    default: env.VECTORIZE
      ? vectorize('VECTORIZE', { embedding: 'workers-ai:@cf/baai/bge-base-en-v1.5' })      // Workers
      : pgvector({ database: 'default', embedding: 'openai:text-embedding-3-small' }),     // Node + Postgres
  },
}))
```
```jsonc
// wrangler.jsonc
"vectorize": [{ "binding": "VECTORIZE", "index_name": "mysite-default" }],   // wrangler vectorize create … --dimensions=768 --metric=cosine
"ai": { "binding": "AI" }
```
```ts
// src/blog/vectors.ts
import { ModelIndex, VectorIndex } from '@ghuri/vectors'
import { Post } from './models'

export const posts = new ModelIndex(Post, {
  name: 'blog.posts',
  text: (post) => `${post.title}\n\n${post.body}`,
  metadata: (post) => ({ status: post.status, authorId: post.authorId, year: post.createdAt.getFullYear() }),
  indexQueryset: (qs) => qs.filter({ status: 'published' }),   // only these rows are indexed
  chunk: { size: 1200, overlap: 200 },
  // autoIndex: true — re-index on postSave / postDelete (in the background when @ghuri/tasks is installed)
})

export const handbook = new VectorIndex('blog.handbook')        // plain documents, not models

// a view, a task, an agent tool…
await handbook.index({ key: 'refunds', text: refundPolicy, metadata: { section: 'billing' } })
const hits = await posts.search('how do I cancel?', { k: 5, filter: { status: 'published', year__gte: 2025 } })
hits[0].object     // the Post (one `filter({ pk__in })` query for all hits)
hits[0].text       // the matching chunk
hits[0].score      // cosine similarity

// src/blog/agents.ts
import { searchTool } from '@ghuri/vectors/agents'
export class SupportAgent extends Agent {
  tools = [searchTool(handbook, { description: 'Search the support handbook.' })]
}
```

### 21.1 Stores

A store is one vector index on one backend. Its API is Vectorize's, which every other backend implements:

```ts
type MetadataValue = string | number | boolean
interface VectorRecord { id: string; values: number[]; namespace?: string; metadata?: Record<string, MetadataValue> }
interface VectorMatch { id: string; score: number; namespace?: string; metadata?: Record<string, MetadataValue>; values?: number[] }

interface VectorStore {
  readonly alias: string
  readonly backend: string                         // 'vectorize' | 'pgvector' | 'database' | 'memory'
  readonly metric: 'cosine' | 'euclidean' | 'dot-product'
  readonly dimensions: number | undefined
  readonly embedding: Embedder                     // 21.2
  upsert(records: VectorRecord[]): Promise<void>
  query(vector: number[], opts: { topK: number; namespace?: string; filter?: Filter; returnValues?: boolean }): Promise<VectorMatch[]>
  getByIds(ids: string[]): Promise<VectorRecord[]>
  deleteByIds(ids: string[]): Promise<void>
  deleteDocuments?(namespace: string, keys: string[]): Promise<void>   // native delete by document (not Vectorize)
  clearNamespace?(namespace: string): Promise<void>
  setup?(): Promise<void>                          // createvectortable
  check(): CheckMessage[]
}
export const vectorStores: { get(alias?): VectorStore; aliases(): string[]; all(): VectorStore[]; override(alias, config) }
```

| | `vectorize(binding, opts)` | `pgvector(opts)` | `databaseStore(opts)` | `memoryStore(opts)` |
|---|---|---|---|---|
| Runs on | Workers (Vectorize binding) | Postgres with the `vector` extension (postgres.js, Hyperdrive, PGlite + `@electric-sql/pglite-pgvector`) | any `DATABASES` alias: D1, SQLite, Postgres | the process |
| Search | ANN (Vectorize) | `ORDER BY embedding <=> $1` with an `hnsw` (default) or `ivfflat` index | exact, in JS, over the namespace's rows | exact, in JS |
| Metadata filters | Vectorize filter (needs metadata indexes) | `jsonb` predicates in SQL | in JS | in JS |
| Delete a document | through the manifest (needs the `vectors` app) | `DELETE … WHERE namespace AND document` | the same | native |
| Table | — | `vectors_pgembedding` (raw SQL, `ghuri createvectortable`) | `vectors_vectorembedding` (model + migration) | — |
| For | Workers production | Node production | small apps (a few thousand chunks per namespace), tests | tests, scripts |

- **Options shared by all factories:** `embedding` (21.2; optional in the types, but a store without one raises
  `InvalidVectorStore` on use and fails `vectors.E004`; indexes have no embedding option of their own), `dimensions`
  (default: known for built-in model ids, else measured on the first embedding), `metric` (default `'cosine'`).
- **`vectorize(binding, { embedding, metric })`.** `upsert` sends batches of 500 (the binding takes 1000). Vectorize
  is eventually consistent: a vector is searchable a few seconds after `upsert` returns (documented). Metadata filters
  need `wrangler vectorize create-metadata-index` for each filtered key (documented, not checked).
- **`pgvector({ database: 'default', table: 'vectors_pgembedding', dimensions, metric, index: 'hnsw' | 'ivfflat' | null, m, efConstruction, lists })`.**
  Columns: `id text primary key`, `namespace text`, `document text`, `chunk integer`, `embedding vector(n)`,
  `metadata jsonb`, index on `(namespace, document)`. The opclass follows the metric (`vector_cosine_ops`,
  `vector_l2_ops`, `vector_ip_ops`).
- **`databaseStore({ database: 'default' })`** stores embeddings as base64 float32 in a `TextField`, so it is
  portable to every database Ghuri supports. Queries read every row of one namespace; it warns (`vectors.W002`) when
  used with `DEBUG = false`.
- **Scores** follow Vectorize: cosine similarity, euclidean distance (lower is closer) or the dot product. Matches are
  always returned best first. `minScore` works for cosine and dot-product only.

### 21.2 Embeddings

```ts
interface Embedder {
  readonly modelId: string                          // 'workers-ai:@cf/baai/bge-base-en-v1.5'
  readonly dimensions: number | undefined
  readonly maxBatch: number
  embed(texts: string[], opts?: { kind?: 'query' | 'document' }): Promise<number[][]>
}
export async function resolveEmbedding(spec: string | EmbeddingModelV2 | Embedder, opts?: { env?; providerOptions?; dimensions? }): Promise<Embedder>
export function registerEmbeddingProvider(name: string, factory: (modelId, ctx) => Embedder | Promise<Embedder>): void
export async function embed(text, opts?: { store?; kind? }): Promise<number[]>          // kind: 'query' | 'document' (default)
export async function embedMany(texts, opts?: { store?; kind? }): Promise<number[][]>
```

- `embedding` is a `'<provider>:<model id>'` string, as agent models are (§10), an AI SDK embedding model (called
  through its `doEmbed`, so `ai` is not a dependency), or an `Embedder`.
- Built-in providers, none needing a package:
  - `workers-ai:` calls the AI binding (`env[AGENTS.AI_BINDING ?? 'AI']`) as `ai.run(model, { text })`;
  - `openai:` posts to `/v1/embeddings` (`OPENAI_API_KEY`; `OPENAI_BASE_URL` or `baseURL` for compatible APIs);
  - `ghuri-ai:` posts to the gateway's OpenAI-compatible `/v1/embeddings` (`GHURI_AI_URL`, `GHURI_AI_API_KEY`) with
    the `x-ghuri-*` headers of the carried context, as agents do.
- Provider options (`apiKey`, `baseURL`, `headers`) are one object: the store's `providerOptions` when it has them,
  else `AGENTS.PROVIDERS[name]`. The store's options replace the `AGENTS` entry entirely (no merge), and environment
  variables then fill each key the object lacks. Vectors reads the `AGENTS` setting but does not import
  `@ghuri/agents`, so one API key serves both.
- `prefixes: { query?, document? }` on a `VectorIndex` (`VectorIndexOptions`, so on a `ModelIndex` too, not on a
  store), for models that want them (`'query: '` for e5).

### 21.3 Indexes

```ts
export class VectorIndex {
  constructor(name: string, opts?: {
    store?: string                                // VECTORS alias, default 'default'
    chunk?: ChunkOptions | false | ((text: string) => string[])   // default { size: 1000, overlap: 200 }
    tenant?: 'auto' | boolean                     // 21.4, default 'auto'
    storeText?: boolean                           // keep chunk text in metadata (default true)
    prefixes?: { query?: string; document?: string }
  })
  readonly name: string
  index(docs: Document | Document[], opts?: { namespace?; force?; background? }): Promise<IndexResult>
  delete(keys: Key | Key[], opts?: { namespace?; background? }): Promise<void>
  clear(opts?: { namespace? }): Promise<void>
  keys(opts?: { namespace? }): Promise<string[]>   // indexed document keys, from the manifest (needs the `vectors` app)
  search(query: string | number[], opts?: SearchOptions): Promise<SearchHit[]>
}
interface Document { key: string | number; text: string; metadata?: Record<string, MetadataValue> }
interface SearchOptions { k?: number /* 4 */; filter?: Filter; exclude?: Filter; namespace?: string; minScore?: number; includeValues?: boolean }
interface SearchHit { id: string; key: string; chunk: number; score: number; text: string | null; metadata: Record<string, MetadataValue>; values?: number[] /* with includeValues */ }

export class ModelIndex<M> extends VectorIndex {
  constructor(model: M, opts: VectorIndexOptions & {
    name?: string                                  // default '<app label>.<model name>'
    text: ((obj) => string) | string[]             // a function or field names joined with blank lines
    metadata?: (obj) => Record<string, MetadataValue>
    indexQueryset?: (qs) => QuerySet               // haystack's index_queryset: rows outside it are not indexed
    autoIndex?: boolean                            // default true
    background?: boolean | 'auto'                  // default 'auto'
  })
  index(objs: Instance | Instance[]): Promise<IndexResult>
  delete(objsOrPks): Promise<void>
  update(opts?: { batchSize?; force?; namespace? }): Promise<IndexResult>     // update_index for this index
  search(query, opts): Promise<ModelSearchHit<M>[]>                // hits with `object` (loaded with filter({ pk__in })); deleted rows dropped
}
export function getVectorIndex(name: string): VectorIndex | undefined
export function vectorIndexes(): VectorIndex[]
```

- **Chunking.** `chunkText(text, { size, overlap, separators })` is a recursive character splitter (separators
  `\n\n`, `\n`, `. `, ` `, then characters). Sizes are characters, not tokens (no tokenizer on Workers).
- **Ids.** A chunk's vector id is `<first 40 hex of sha-256("namespace\0key")>-<chunk>`: at most 64 bytes
  (Vectorize's limit) and unique across tenants and indexes sharing a store, because the namespace already contains
  the index name (and the tenant, see 21.4).
- **Reserved metadata.** `_key`, `_chunk` and `_text` (when `storeText`). User keys must not start with `_`; values
  are strings, numbers or booleans (Vectorize's types).
- **Manifest.** With the `vectors` app installed, every indexed document has a `VectorDocument` row (`index`,
  `namespace`, `key`, `chunks`, `digest`). `index()` skips a document whose digest (text, metadata, embedding model,
  chunking) is unchanged, unless `force`. It deletes the chunks a shorter new version no longer has. Vectorize needs
  the manifest to delete documents; the other stores use it only to skip unchanged documents.
- **Order of writes.** Embed every chunk, upsert, delete stale chunks, then save the manifest row, so a failed
  embedding call changes nothing.
- **Filters** use Django lookups on metadata: `{ status: 'published' }`, `year__gte`, `__gt`, `__lt`, `__lte`, `__in`,
  `__exact`, and `exclude` (one key each: `$ne` / `$nin`). They translate to Vectorize filters, `jsonb` SQL and a JS
  matcher. An unknown lookup raises `FilterError`.

### 21.4 Tenants (fail closed)

- `tenant: 'auto'` scopes an index when a context carrier named `tenant` is registered, which `@ghuri/tenants`
  does. `true` always scopes it; `false` never does (platform-wide content).
- A scoped index takes the tenant from `captureContext().tenant` (§14), never from arguments. Without one it raises
  `TenantRequired` for `index`, `delete`, `clear`, `keys` and `search`, and for `ModelIndex.update()`. That includes
  code inside `withoutTenant()`, which carries no tenant.
- The tenant goes into the store **namespace**: `<index>|t=<tenant pk>[|<namespace>]`, hashed when longer than 64
  bytes. On Vectorize this is native namespace isolation, so a missing metadata index cannot leak across tenants. On
  pgvector and `databaseStore()` it is a `WHERE namespace = $1` that every query carries.
- Background work keeps the tenant: tasks capture carriers at enqueue, and `update_index --tenant <pk>` runs inside
  `restoreContext({ tenant })`. `ModelIndex.search()` loads objects through the model's manager, so tenant managers
  apply as well.
- Deliberate limit: there is no search across tenants.

### 21.5 Background indexing

- `@ghuri/vectors` does not import `@ghuri/tasks`. When `globalThis[Symbol.for('ghuri.tasks.interop')]` exists, an
  `onPopulate` hook defines the task `vectors.index` (`maxAttempts: 3`), as agents define `agents.run`.
- `background: true` enqueues it; `'auto'` enqueues when the interop exists and runs inline otherwise.
- Jobs are JSON: `{ index, op: 'index' | 'delete', keys?, documents?, namespace?, force? }`. Model indexes send primary
  keys and reload the rows in the worker, so stale data is never embedded. Mind the 128 KB Queues message limit for
  plain documents.
- `autoIndex` connects `postSave` / `postDelete` for the model, skips `raw` saves (`loaddata`), and defers the work
  with `onCommit`.

### 21.6 Settings, commands and checks

```ts
VECTORS: { <alias>: vectorize(...) | pgvector(...) | databaseStore(...) | memoryStore(...) }
```

Missing `VECTORS` raises `ImproperlyConfigured` on first use. There is no silent in-memory default.

Commands (`VectorsConfig`):

| Command | Does |
|---|---|
| `ghuri update_index [names…] [--tenant pk] [--namespace name] [--batch-size 100] [--force]` | index every row of each `ModelIndex` (unchanged rows skipped); plain `VectorIndex`es are skipped |
| `ghuri clear_index [names…] [--tenant pk] [--namespace name]` | delete a namespace's vectors and manifest rows (any index) |
| `ghuri rebuild_index [names…] [--tenant pk] [--namespace name] [--batch-size 100]` | clear, then update (with `force`) |
| `ghuri createvectortable [--store alias]` | `CREATE EXTENSION IF NOT EXISTS vector`, the table and the ANN index of each `pgvector()` store (Django's `createcachetable`) |

Checks:
- `vectors.E001` a `VECTORS` entry is not a store.
- `vectors.E002` an index names a store alias that is not configured.
- `vectors.E003` `vectorize()` or `databaseStore()` without the `vectors` app.
- `vectors.E004` a store has no embedding.
- `vectors.E005` a `vectorize()` binding is not in wrangler.jsonc `vectorize`.
- `vectors.E006` a `pgvector()` store without known dimensions.
- `vectors.W001` `memoryStore()` with `DEBUG = false`.
- `vectors.W002` `databaseStore()` with `DEBUG = false`.
- `vectors.W003` a `workers-ai:` embedding while wrangler.jsonc has no `ai` binding.

Errors (extend `GhuriError`): `VectorsError`, `InvalidVectorStore`, `EmbeddingError`, `DimensionMismatch`,
`FilterError`, `TenantRequired`.

### 21.7 Testing

- `@ghuri/vectors/testing`:
  - `fakeEmbedding({ dimensions: 64 })`: a deterministic hashed bag-of-words embedder, so texts that share words
    are close and tests need no network;
  - `useVectorStore(config, alias = 'default')`, e.g. `useVectorStore(memoryStore({ embedding }))`: overrides the alias
    and returns `{ store, restore }`;
  - `fakeVectorize()`: an in-memory `VectorizeIndex` binding with namespaces, filters and the 64-byte limits.
- Package tests:
  - the index API, chunking and filters on every store;
  - `databaseStore()` and the manifest on SQLite, PGlite and D1 (Miniflare);
  - `pgvector()` on PGlite with `@electric-sql/pglite-pgvector`;
  - `vectorize()` against `fakeVectorize()` (Miniflare does not simulate Vectorize; `wrangler dev` uses the remote
    index);
  - tenant isolation, fail-closed errors, background indexing through a stub of the tasks interop, the agents tool.

### 21.8 Changes in other packages

| Package | Change |
|---|---|
| core, orm, tasks, agents | none required. Vectors uses `captureContext()`, `apps.onPopulate`, the tasks interop, `AGENTS.*` settings and the `AgentTool` shape |
| tenants | optional, later: publish `tenantMode()` on a `globalThis` interop so platform code inside `withoutTenant()` can be told apart from code with no tenant |
| cli | `startproject --cloudflare` could add a `vectorize` binding and `VECTORS` (phase 2) |
| docs | topic "Vectors and RAG" (`topics/vectors`) |

### 21.9 Phases

1. **0.1**:
   - the four stores, embeddings (Workers AI, OpenAI-compatible, ghuri-ai, AI SDK models);
   - `VectorIndex`, `ModelIndex`, chunking, filters, tenant namespaces, the manifest;
   - background indexing, the commands, checks, testing helpers and `searchTool()`.
2. **0.2**:
   - an ORM `VectorField({ dimensions })` (pgvector `vector(n)`, a blob elsewhere) with pgvector-python's
     `CosineDistance` / `L2Distance` / `MaxInnerProduct` expressions and `HnswIndex` / `IvfflatIndex` (needs
     field-type hooks in `@ghuri/orm`);
   - hybrid search (Postgres full text, D1 FTS5);
   - `distinct` (best chunk per document), rerankers (`@cf/baai/bge-reranker-base`).
3. **Later**: token-based chunking, Vectorize's HTTP API from Node, Turbopuffer / Qdrant stores.

### 21.10 Open questions (proposed answers)

- **`autoIndex` by default.** Haystack's default signal processor does nothing. *Proposed:* on. The manifest digest
  makes re-saves without text changes free, and background tasks keep embedding out of the request.
- **Text in metadata.** Vectorize caps metadata at 10 KiB per vector, which suits chunks of up to ~8,000 characters.
  *Proposed:* store text by default; `storeText: false` for apps that load text from their own rows.
- **Cross-tenant search.** *Proposed:* none in 0.1. Platform code loops over tenants.

### 21.11 As built (supersedes 21.1–21.10 where they conflict)

- **Peers:** `@ghuri/core` ^0.1.0-alpha.5 and `@ghuri/orm` (required; the models are in the main entry),
  `@ghuri/agents` (optional; `@ghuri/vectors/agents` imports its types only). `ai` is **not** a peer: AI SDK
  embedding models are called through their `doEmbed()` (spec v2 to v4), so nothing imports `ai`. The main entry
  imports nothing Node-only (the wrangler checks use computed `import()` specifiers, as tasks does). A test bundles it
  with esbuild for workerd and runs indexing and search in Miniflare.
- **Stores:** `VectorStore` also has `hasEmbedding` and `nativeDeletes` (false for Vectorize). `embedding` throws
  `InvalidVectorStore` when the store has none.
  - `pgvector()` has no `chunk` column (the chunk number is in `metadata._chunk`). The default table is
    `vectors_pgembedding`, or `vectors_pgembedding_<alias>` for other aliases. String range filters compare with
    `COLLATE "C"`.
  - `vectors_vectorembedding` has a `BigAutoField` id, `vectorId`, and `uniqueTogether (store, vectorId)`, so two
    `databaseStore()` aliases can share a database.
  - Vectorize queries ask for `returnMetadata: 'all'`, so Vectorize's lower `topK` limit for queries that return
    metadata applies.
- **Embeddings:**
  - The store's `providerOptions` replace `AGENTS.PROVIDERS[name]` rather than merging with it; environment variables
    (`OPENAI_API_KEY`, `OPENAI_BASE_URL`, `GHURI_AI_URL`, `GHURI_AI_API_KEY`) fill each key the object lacks.
  - `ghuri-ai:` also sends `x-ghuri-feature: vectors`.
  - Known dimensions cover the Workers AI bge / embeddinggemma / qwen3 models and OpenAI's three embedding models.
  - `openai:` sends `dimensions` only when it differs from the model's known default.
- **Indexes:**
  - Names are 1-48 characters of `[A-Za-z0-9_.:-]`. Creating an index with an existing name replaces the old one
    (and its signal receivers).
  - `ModelIndex`'s default name is the model's `labelLower` (`'blog.post'`), so the model needs its app label when
    the index is created.
  - Added: `keys()`, `ModelIndex.indexPks()`, `document()`, `disconnectSignals()`.
  - `index()` returns `{ indexed, skipped, deleted, chunks, taskResultId? }`.
  - Metadata keys match `[A-Za-z0-9_-]{1,64}`, and booleans compare for equality only.
  - The digest also covers the document prefix and `storeText`.
  - Without the manifest, native stores delete a changed document's vectors before the upsert (the old chunk count
    is unknown).
- **Background:** `VectorIndex.index()` / `delete()` default to `background: false`; `ModelIndex` automatic indexing
  defaults to `'auto'`.
- **Agents:**
  - `searchTool(index, { name, description, k = 5, maxK = 10, filter, exclude, minScore, maxChars = 2000 })`
    returns a plain `AgentTool` named `search_<index>`. `filter` may be a function of the `ToolContext`.
  - The subpath also has `formatHits()` and `retrieve()`.
- **Commands** all take `--namespace`; `update_index` skips plain `VectorIndex`es; `rebuild_index` updates with
  `force`. The **checks** add `vectors.E006` (a pgvector store without known dimensions).
- **Tests:** 120 tests:
  - the store contract and the index API on memory, `databaseStore()` (SQLite, PGlite, D1 via Miniflare),
    `pgvector()` (PGlite + `@electric-sql/pglite-pgvector` 0.0.17, pinned to PGlite 0.5.16) and `vectorize()`
    (`fakeVectorize()`);
  - tenant isolation with the real `@ghuri/tenants`, including background runs through `@ghuri/tasks`' dummy
    backend and `update_index --tenant`;
  - providers with stubbed `fetch` and AI bindings, the migration check, `ghuri check` messages and the agents
    tool inside a real `Agent`.
- **Not yet:**
  - Vectorize is not tested end to end; Miniflare has no Vectorize and the remote index needs an account.
  - pgvector is not tested on a Postgres server (postgres.js / Hyperdrive), only on PGlite.
  - `examples/blog` and the CLI templates do not use vectors yet.

---

## 22. Agent usage limits (`@ghuri/agents`)

Status: **built in `@ghuri/agents` (unreleased, branch `feat/usage-limits`)**; see 22.10 for where it differs from this text. No new package:
limits live in `@ghuri/agents`, next to the runs they limit.

An AI SaaS pays for every token its users spend. Without a budget, one heavy user (or one tenant's script) can run
up the model bill for everyone. Usage limits stop a user, a tenant or an anonymous client **before a run starts**
when they have used their token budget for the day or the month, and answer like DRF's throttles: `429` with
`Retry-After` until the window resets. Nothing changes for projects that do not set `AGENTS.USAGE_LIMITS`.

No Django equivalent: the closest is DRF throttling (`UserRateThrottle`, `AnonRateThrottle`), which counts
requests in a cache. Agents count tokens, which are known only after a run, so the counter is a table.

```ts
// settings.ts
AGENTS: {
  USAGE_LIMITS: {
    user: { day: 200_000, month: 2_000_000 },          // tokens (input + output) per UTC day / month
    anon: { day: 20_000 },                              // per client address
    tenant: (subject) => planLimits(subject.key),       // a function: the hook a billing plan plugs into
  },
}

// a view of the app: "you have used X of Y tokens"
import { getUsage } from '@ghuri/agents'
const usage = await getUsage({ user: request.user })
// [{ scope: 'user', key: '42', period: 'day', used: 1234, limit: 200000, remaining: 198766, resetsAt }, …]
```

### 22.1 Where usage is counted

**A counter table, `agents.Usage`** (`agents_usage`), one row per subject per window:
`scope` (`user` / `tenant` / `anon`), `key`, `period` (`day` / `month`), `start` (the window's first UTC day),
`inputTokens`, `outputTokens`, `cachedInputTokens`, `totalTokens`, `runs`, `updatedAt`; unique on
`(scope, key, period, start)`.

- **Why not `agents_run`:** traces are opt-in (`AGENTS.TRACE_RUNS`), may store prompts (privacy, retention), and
  summing a month of runs before every run is a scan that grows with usage. The counter is one indexed read of at
  most four rows (two subjects × two windows) before a run, whatever the volume, and works with traces off.
- **Writes** after every finished run: an `INSERT … ON CONFLICT DO NOTHING` of the missing rows (`bulkCreate` with
  `ignoreConflicts`) and one `UPDATE … SET total_tokens = total_tokens + n, …` of all of them. Increments are done
  by the database (`F()`), so concurrent runs never lose counts. Two statements per run, on Postgres, SQLite and D1.
- **What counts:** `usage.totalTokens` of the run (all steps), else `inputTokens + outputTokens`. Cached input
  reads are part of the input (the AI SDK's definition) and also kept apart in `cachedInputTokens`. Failed runs
  report no usage to agents and count nothing.
- **Windows:** the current UTC day and UTC month. Rows of old windows stay (a history for reports);
  `Usage.objects.filter({ start__lt: … }).delete()` prunes them.

### 22.2 Subjects

Each run counts against up to two subjects:

| Scope | When | Key |
|---|---|---|
| `user` | the run's user is authenticated | the user's pk |
| `anon` | the user is anonymous | DRF's `getIdent(request)` (the client address) when the run has a `request`, else `'*'` (one shared bucket: programmatic and queued anonymous runs) |
| `tenant` | a `tenant` value is carried (`captureContext().tenant`, set by `@ghuri/tenants`) | the tenant pk |

Agents read the tenant through core's context carriers, so `@ghuri/agents` does not import `@ghuri/tenants`, and a
queued run (whose carriers are restored) counts against the same tenant as the request that enqueued it. A scope
is counted only when `USAGE_LIMITS` covers it (22.3), so a project that limits only users writes only user rows.

### 22.3 Limits

`AGENTS.USAGE_LIMITS` is either an object per scope or one function for every scope:

```ts
type UsageLimits = { day?: number | null; month?: number | null }            // tokens; null/absent: no limit
type UsageLimitsValue = UsageLimits | ((subject: UsageSubject) => UsageLimits | null | undefined | Promise<…>)
USAGE_LIMITS?: { user?: UsageLimitsValue; tenant?: UsageLimitsValue; anon?: UsageLimitsValue }
             | ((subject: UsageSubject) => UsageLimits | null | undefined | Promise<…>)
interface UsageSubject { scope: 'user' | 'tenant' | 'anon'; key: string; user: RequestUser }
```

- A function is called before every run (and by `getUsage()`), so it may read a plan from the database; it should
  be cheap or cache. Returning `null` means "no limit" (staff, an unlimited plan) but the subject is still counted.
- **Billing hook:** a future `@ghuri/billing` exposes the subscriber's plan; the project wires it in settings
  (`tenant: (s) => planFor(s.key).then((p) => p.limits.agentTokens)`). Agents never depend on billing.
- Limits are across all agents of the project. Per-agent budgets are not in 0.1 (22.9).

### 22.4 Enforcement

One check, `checkUsage()`, runs in the two places every run passes through:

| Way a run starts | Where the check runs | Over the limit |
|---|---|---|
| chat view, JSON | `agent.run()` → `prepare()`, after permissions, before the model and the conversation | `Throttled` (429, `Retry-After`) |
| chat view, SSE | `agent.stream()` → `prepare()`, before the stream response exists | `Throttled` (429, `Retry-After`), JSON body |
| MCP `ask_<agent>` | `agent.run()` | tool result `isError: true` with the message and `retryAfter` |
| `agent.run()` / `agent.stream()` | `prepare()` | `UsageLimitExceeded` |
| `agent.enqueue()` (tasks and queue paths) | before the conversation is created and the job is sent | `UsageLimitExceeded`, nothing enqueued |
| the queued run itself (`agents.run` task, `consumeAgentQueue`) | `agent.run()` again, when it runs | task: attempt fails (retried, then `FAILED`); queue: message acked and logged, not retried |

A refused run creates no conversation, calls no model and writes no trace. `runFinished` is not sent (no run
happened); `usageLimitReached` is (22.6).

**Soft limit.** The check reads the counters before a run, and the run is counted after it ends. Two things let a
subject go over its budget: runs that start at the same time all pass the same check, and the run that crosses the
limit is finished, not cut off. Overshoot is bounded by (concurrent runs) × (one run's tokens), which
`Agent.maxSteps` and `maxOutputTokens` bound. A hard limit would need a reservation (an estimate written before
the run and corrected after), which costs a write per run and an estimate nobody has; it can come later as an
option without changing the table.

### 22.5 Errors

- `UsageLimitExceeded extends AgentError`: `subject`, `period`, `limit`, `used`, `resetsAt` (a `Date`) and `wait`
  (seconds until `resetsAt`). When several windows are exceeded it names the one that resets last.
  Message: `Token usage limit reached for user 42: 200500 of 200000 tokens this day. Resets at 2026-11-24T00:00:00.000Z.`
- HTTP: `Throttled(wait, 'Token usage limit reached for this <period>.', 'usage_limit_exceeded')`, so the body is
  DRF's (`{ detail: '… Expected available in N seconds.' }`), the header is `Retry-After: N`, and the code tells a
  UI the budget is spent (rather than the provider being busy, which is also a 429, §14).

### 22.6 Reading usage, signals, admin

- `getUsage({ user, tenant?, request? })` → one `UsageWindow` per counted scope and period:
  `{ scope, key, period, start, resetsAt, used, limit, remaining, inputTokens, outputTokens, cachedInputTokens,
  runs }` (`limit` / `remaining` `null` when unlimited). `tenant` defaults to the carried one.
- `GET <agents prefix>/usage/` (on every `AgentRouter`, name `agents-usage`): the requesting user's
  `{ results: UsageWindow[] }`, permissions `AGENTS.PERMISSION_CLASSES`.
- Signals, robust like `runFinished` (receiver errors are logged): `usageLimitReached`
  (`{ agent, user, error, subjects }`, sent when a run or enqueue is refused: notify, upsell) and `usageRecorded`
  (`{ agent, user, subjects, tokens }`, after the counters were updated: an 80 % warning reads `getUsage()`).
- `@ghuri/agents/admin` (optional peer `@ghuri/admin`): read-only `Usage` and `Run` admins.

### 22.7 Testing

- The counter, the check and every entry point (chat JSON and SSE, MCP, `run()`, both `enqueue()` paths and both
  queued executions) on SQLite and PGlite; concurrent `recordUsage()` calls on one row lose no tokens; window
  boundaries with a fixed clock; no `agents_usage` writes without `USAGE_LIMITS`.
- `makemigrations --check` stays clean (`0003_usage`).

### 22.8 Changes in other packages

| Package | Change |
|---|---|
| agents | everything above |
| tasks | none needed. Nice to have: a way for a task to fail without retries (a refused run is retried until `maxAttempts`) |
| billing (future) | exposes plan limits as a function the project passes to `AGENTS.USAGE_LIMITS` |
| docs | "Usage limits" in the agents topic, settings rows |

### 22.9 Open questions (proposed answers)

- **Hourly windows / run counts.** *Proposed:* not in 0.1; `day` and `month` cover budgets, DRF throttles cover
  request rates.
- **Cost instead of tokens.** Models differ in price, and cache reads are cheaper. *Proposed:* later, an
  `AGENTS.USAGE_COST(usage, model)` that turns a run's usage into the counted number; tokens until then.
- **Per-agent limits.** *Proposed:* later, `Agent.usageLimits` that overrides the settings for one agent with its
  own counters (`key` prefixed by the agent name).
- **Time zone.** *Proposed:* UTC windows only; a tenant's local midnight is billing's concern.

### 22.10 As built (supersedes 22.1–22.9 where they conflict)

- **Where:** `src/usage.ts` (settings, subjects, windows, `checkUsage` / `recordUsage` / `getUsage`, signals),
  `Usage` in `src/models.ts`, migration `agents.0003_usage` (depends only on `0002_run`; generated by
  makemigrations). Nothing is read or written while `USAGE_LIMITS` is unset; with it set and the agents app missing,
  a run raises `ImproperlyConfigured` rather than silently not enforcing.
- **Hook points:** `Agent.checkUsage(user, request?)` (overridable) runs in `prepare()` right after the permission
  check, so it precedes `resolveModel()`, conversation creation and `beforeRun`; `enqueue()` calls it after
  `enqueueMode()` (configuration errors first). Counting happens at the start of `finish()`, before
  `saveMessages()` and `afterRun`, so a failing hook or save cannot lose spent tokens; the subjects are the ones
  computed by the check (same tenant, same anonymous key).
- **Anonymous key:** `clientIdent(request)` is a `BaseThrottle` subclass's `getIdent()` (honours `NUM_PROXIES`),
  truncated to 100 characters, `'*'` without a request or address. The MCP `ask_<agent>` passes its request, so MCP
  clients are keyed like HTTP ones.
- **Errors:** `UsageLimitExceeded extends AgentError` (not `Throttled`: its message names the subject, which HTTP
  answers leave out). The chat view maps it through `modelCallError()` → `usageThrottled()`; `toToolError()` maps
  it to `ToolError(message, { status: 429, detail: { scope, period, limit, used, resetsAt, retryAfter } })`, which
  covers MCP and agents used as tools of other agents. `consumeAgentQueue` acks refused jobs with a warning; the
  `agents.run` task fails its attempt, is retried (up to 3, with the task's backoff) and ends `FAILED` with
  `exceptionClassPath` naming `UsageLimitExceeded`.
- **HTTP:** `UsageView` at `usage/` on every `AgentRouter` (`AGENTS.AUTHENTICATION_CLASSES`,
  `AGENTS.PERMISSION_CLASSES`), `resetsAt` as an ISO string. It returns `{ results: [] }` when limits are off.
- **Admin:** `@ghuri/agents/admin` registers `UsageAdmin` (no add, all fields read-only, delete resets a window)
  and `RunAdmin` (no add, read-only). `Conversation` stays unregistered (it is swappable).
- **Tested** on SQLite and PGlite (`test/usage.test.ts`, plus the tasks path in `test/tasks.test.ts`): no writes
  without the setting; day / month counting and `getUsage()`; refusal before the model and the conversation; UTC
  day and month rollover with a fake clock; the window that resets last is reported; carried tenant with an async
  limits function; scopes counted only when named; anonymous `'*'` bucket; streamed runs; 20 concurrent
  `recordUsage()` calls on one row; robustness against a failing counter write and receivers; chat view JSON and
  SSE (`429`, `Retry-After`, no conversation); `GET usage/`; MCP `isError`; both `enqueue()` paths and both queued
  executions; the admin registration. `@ghuri/tenants` tests pass against the new build. **Not tested:** D1
  (Miniflare); the package has no D1 harness. `ON CONFLICT DO NOTHING` is supported by D1's SQLite.
- **Not yet:** partial usage of a failed run (a model error at step 3 loses steps 1–2; the AI SDK throws without
  usage), hard limits / reservations, cost weighting (`USAGE_COST`), per-agent budgets, hourly windows, a way for
  `@ghuri/tasks` to fail a task without retries. `ghuri eval` runs count against the eval user like any run.

---

## 23. `@ghuri/billing` (dj-stripe style subscriptions)

Status: **0.1 built** (see 23.11 for where it differs from this text). Repo `ghurijs/billing`, npm
`@ghuri/billing`, peers `@ghuri/core` and `@ghuri/orm` (required), `@ghuri/rest` and `@ghuri/admin` (optional,
behind `@ghuri/billing/rest` and `@ghuri/billing/admin`).

A SaaS needs four things from billing: a checkout that starts a subscription, a portal where customers change or
cancel it, webhooks that keep the app's copy of the subscription true, and a cheap "what may this subscriber do"
question in app code. dj-stripe answers the first three for Django by mirroring Stripe objects into models; Ghuri
does the same, with Django names, on Workers, behind a provider adapter so Paddle or Lemon Squeezy can follow.

```ts
// src/settings.ts
import { stripe } from '@ghuri/billing'
BILLING: {
  PROVIDER: stripe({ secretKey: env.STRIPE_SECRET_KEY, webhookSecret: env.STRIPE_WEBHOOK_SECRET }),
  SUBSCRIBER_MODEL: 'auth.User',                   // or 'tenants.Tenant' (dj-stripe's DJSTRIPE_SUBSCRIBER_MODEL)
  // SUBSCRIBER: (c) => currentTenant(),           // who pays for this request (default: the request user)
  SUCCESS_URL: '/billing/thanks/', CANCEL_URL: '/pricing/', RETURN_URL: '/account/',
  PLANS: {
    free: { limits: { agentTokens: { day: 20_000 } } },
    pro:  { prices: ['pro_monthly', 'pro_yearly'],                     // price ids or lookup keys
            features: ['export', 'api'], limits: { agentTokens: { day: 500_000, month: 5_000_000 } } },
  },
  DEFAULT_PLAN: 'free',
},
INSTALLED_APPS: [..., BillingConfig],
ROOT_URLCONF: [..., path('billing/', include(billingUrls))],            // checkout/, portal/, webhook/

// app code
const sub = await getSubscription(request.user)          // Subscription | null (the current one)
if (await hasFeature(request.user, 'export')) { … }
class ExportView extends APIView { permissionClasses = [IsAuthenticated, HasActiveSubscription] }
AGENTS: { USAGE_LIMITS: { tenant: usageLimits('agentTokens') } }       // §22, without agents importing billing
```

### 23.1 Providers

```ts
interface BillingProvider {
  readonly name: string                                   // 'stripe'
  createCustomer(data: { email?, name?, metadata }): Promise<CustomerData>
  createCheckoutSession(opts: CheckoutOptions): Promise<{ id: string; url: string }>
  createPortalSession(opts: { customer: string; returnUrl: string }): Promise<{ url: string }>
  constructEvent(body: string, headers: Headers): Promise<ProviderEvent>   // verifies the signature
  retrieve(kind: 'customer' | 'product' | 'price' | 'subscription' | 'invoice', id: string): Promise<ObjectData>
  list(kind: 'product' | 'price'): AsyncIterable<ObjectData>
  cancelSubscription(id: string, opts: { atPeriodEnd: boolean }): Promise<SubscriptionData>
  check(): CheckMessage[]
}
```

- The provider turns its objects into **normalized data** (`CustomerData`, `ProductData`, `PriceData`,
  `SubscriptionData`, `InvoiceData`) and its events into `ProviderEvent { id, type, created: Date, livemode,
  object: ObjectData | null, deleted, raw }` (`object` carries its own `kind` and `id`; null for objects billing does
  not sync; `raw` is stored in `Event.data`). Syncing, models and views see only normalized data, so a second provider
  is one adapter.
- **`stripe({ secretKey, webhookSecret, apiVersion?, tolerance?: 300, fetch?, apiBase? })`** talks to the Stripe
  REST API with `fetch` (form-encoded bodies, `Idempotency-Key` on every POST) and verifies webhooks with WebCrypto.
  - *Why not the `stripe` SDK:* it runs on Workers (`createFetchHttpClient`, `createSubtleCryptoProvider`), but it
    is a large bundle for eight endpoints, pins the API version to the SDK release, and needs a fake HTTP client in
    tests anyway. A `fetch` adapter is small, has no dependency, and `stripe({ fetch })` is the test seam.
  - `webhookSecret` may be an array (rotation). Signatures: `Stripe-Signature: t=…,v1=…`, HMAC-SHA256 over
    `"<t>.<raw body>"`, constant-time compare against every `v1`, `|now - t| <= tolerance`.
  - Stripe moved fields between API versions (`current_period_*` to subscription items, `invoice.subscription` to
    `invoice.parent`); the adapter reads both shapes.
- Secrets come from settings only (read from `env`); nothing in the package or its tests holds a real key.

### 23.2 Models (app label `billing`)

dj-stripe's names, a local auto pk and the provider's id in `providerId` (unique). Amounts are integers in the
currency's minor unit (cents), always next to a `currency` (ISO 4217, lowercase as Stripe sends it).

| Model | Table | Fields (besides `provider`, `providerId`, `livemode`, `metadata`, `created`) |
|---|---|---|
| `Customer` | `billing_customer` | `subscriberType`, `subscriberId`, `email`, `name`, `currency`, `deleted` |
| `Product` | `billing_product` | `name`, `description`, `active` |
| `Price` | `billing_price` | `product` → Product, `active`, `currency`, `unitAmount`, `type` (`one_time`/`recurring`), `recurringInterval`, `recurringIntervalCount`, `lookupKey`, `nickname`, `trialPeriodDays` |
| `Subscription` | `billing_subscription` | `customer` → Customer, `status`, `currentPeriodStart/End`, `cancelAtPeriodEnd`, `cancelAt`, `canceledAt`, `endedAt`, `trialStart/End`, `lastEventAt` |
| `SubscriptionItem` | `billing_subscriptionitem` | `subscription` → Subscription, `price` → Price, `quantity` |
| `Invoice` | `billing_invoice` | `customer`, `subscription`, `status`, `currency`, `amountDue`, `amountPaid`, `amountRemaining`, `subtotal`, `total`, `number`, `hostedInvoiceUrl`, `invoicePdf`, `periodStart/End`, `paidAt` |
| `Event` | `billing_event` | `type`, `data`, `status` (`pending`/`processed`/`failed`/`ignored`), `attempts`, `error`, `receivedAt`, `processedAt` |

- **The subscriber is a generic owner**, not a swappable foreign key: `subscriberType` is the model label
  (`'auth.user'`, `'tenants.tenant'`), `subscriberId` its pk as a string, unique together. `BILLING.SUBSCRIBER_MODEL`
  names the model (default `AUTH_USER_MODEL`). *Why:* a foreign key to a setting-chosen model needs every bundled
  migration rewritten per project (§14 `migrationsForUserModel`), a tenant table may live in another app or not
  exist yet, and switching from per-user to per-tenant billing later is a data move, not a schema change. Billing
  never imports `@ghuri/tenants`. `customer.getSubscriber()` loads the instance through `apps.getModel()`.
- `Subscription.status` uses Stripe's values (`incomplete`, `incomplete_expired`, `trialing`, `active`,
  `past_due`, `canceled`, `unpaid`, `paused`). `isActive` is `BILLING.ACTIVE_STATUSES` (default
  `['active', 'trialing']`); `past_due` keeps access only if the project adds it (grace periods).
- Payments (PaymentIntent, Charge) are not mirrored in 0.1: invoices carry what a SaaS shows.

### 23.3 Views (`billingUrls`, namespace `billing`)

| Route | Name | What |
|---|---|---|
| `POST checkout/` | `billing:checkout` | `{ price \| plan, quantity?, successUrl?, cancelUrl? }` → Checkout Session for the request's subscriber (customer created on first use). JSON: `{ id, url }`; form post: `303` to the session |
| `POST portal/` | `billing:portal` | `{ returnUrl? }` → Customer Portal session, same responses |
| `POST webhook/` | `billing:webhook` | CSRF-exempt and `tenantNotRequired()`; verify, store, process |

- Checkout and portal need a subscriber (`BILLING.SUBSCRIBER(c)`, default the authenticated user): 401 otherwise
  (never 403 or a `LOGIN_URL` redirect). They authenticate like an `APIView` (23.11). Only prices named in `BILLING.PLANS` or active local `Price` rows of active products can be bought, so a
  client cannot buy an internal price. Redirect URLs must be relative or on `ALLOWED_HOSTS` (open-redirect guard).
- **Webhook:** bad or missing signature → 400. The event is stored in `Event` by provider id; a duplicate of an
  event already `processed` / `ignored` answers 200 without processing (idempotency). Otherwise it is processed:
  - inline in the request (default), answering 200 on success and 500 on failure so the provider retries;
  - or, with `BILLING.WEBHOOK_TASKS: true` and `@ghuri/tasks` loaded, as the task `billing.processEvent` (through
    `globalThis[Symbol.for('ghuri.tasks.interop')]`, as agents do, with no import), answering 200 at once.
- **Processing** is per kind: customer, product and price events upsert; subscription events upsert the
  subscription and its items (creating missing prices and products); `checkout.session.completed` and
  `checkout.session.async_payment_succeeded` link the customer and fetch the subscription (other checkout events are
  `ignored`); invoice events upsert the invoice. Out-of-order delivery: a subscription event older
  than the stored `lastEventAt` is skipped. Unknown types are stored as `ignored`.

### 23.4 Access in app code

```ts
getCustomer(subject, { create? }): Promise<Customer | null>
getSubscription(subject): Promise<Subscription | null>   // the current one: active first, then the latest
hasActiveSubscription(subject, { plans? }): Promise<boolean>
getPlan(subject): Promise<PlanInfo>                       // { key, plan, subscription } — DEFAULT_PLAN without one
getEntitlements(subject): Promise<{ plan, features, limits }>
hasFeature(subject, feature): Promise<boolean>
usageLimits(limitKey | (entitlements) => limits, opts?): (subject) => Promise<limits | null>
```

- `subject` is a model instance (user, tenant), a `Customer`, a reference `{ type?, id }`, or a Hono `Context`
  (resolved with `BILLING.SUBSCRIBER`). Plans match a subscription item by price id, price lookup key or product id.
- **`usageLimits()`** fits §22's `AGENTS.USAGE_LIMITS` (`(subject: { scope, key, user }) => { day?, month? } |
  null`): for the scope that matches `SUBSCRIBER_MODEL` (`tenant` when it is not the user model, else `user`) it
  reads the plan of the subscriber whose pk is `key`; other scopes get `opts.otherwise` (default null, no limit).
  Billing does not import agents; the shapes are structural.
- **`@ghuri/billing/rest`:** `HasActiveSubscription` (DRF permission; `view.requiredPlans` narrows it) and
  `HasFeature(feature)`. A plain-view decorator `subscriptionRequired({ plans? })` is in the main entry.

### 23.5 Signals, admin, commands

- Signals (sender: the provider): `subscriptionCreated`, `subscriptionUpdated`, `subscriptionCancelled`
  (`{ subscription, previousStatus }`, cancelled when the status becomes `canceled` or the subscription is deleted),
  `invoicePaid`, `invoicePaymentFailed` (`{ invoice }`), `webhookProcessed` (`{ event, type }`: the stored `Event`
  row and its type, every processed or ignored event, dj-stripe's `WEBHOOK_SIGNALS`).
- `@ghuri/billing/admin`: read-mostly admins for every model; `Event` gets the action "Process again".
- `ghuri billing_sync [--kinds products,prices]` (dj-stripe's `djstripe_sync_models`) pulls products and prices.
  `ghuri billing_process_events [--status failed]` re-runs stored events.

### 23.6 Settings and checks

`BILLING: { PROVIDER, SUBSCRIBER_MODEL?, SUBSCRIBER?, AUTHENTICATION_CLASSES?, PLANS?, DEFAULT_PLAN?,
ACTIVE_STATUSES?, SUCCESS_URL?, CANCEL_URL?, RETURN_URL?, WEBHOOK_TASKS?, CHECKOUT_OPTIONS? }`.

Checks: `billing.E001` no `PROVIDER`; `billing.E002` missing or malformed secret key (a publishable `pk_` key is an
error); `billing.E003` missing webhook secret; `billing.E004` `SUBSCRIBER_MODEL` not installed; `billing.E005` a
plan's `prices` is not a list of strings or `DEFAULT_PLAN` is not a plan; `billing.W001` (deploy) a test key with
`DEBUG = false`; `billing.W002` `WEBHOOK_TASKS` without `@ghuri/tasks`.

Errors (extend `GhuriError`): `BillingError`, `ProviderError` (status, code, provider message);
`SignatureVerificationError` (core `HttpError`, 400) and `NoSubscriber` (core `HttpError`, 401, thrown by
`requireSubscriber(c)`).

### 23.7 Testing

- `@ghuri/billing/testing`: `fakeStripe()` — an in-memory Stripe REST API behind `stripe({ fetch })`: customers,
  products, prices, checkout and portal sessions, subscriptions; `signPayload(body, secret)` builds a valid
  `Stripe-Signature`; `fake.event(type, object)` builds an event. No network, no keys.
- Package tests: signature verification (good, bad, expired, rotated secrets), checkout/portal/webhook views, sync of
  every kind, idempotency and out-of-order events, access helpers, permission classes, checks, migrations with no
  missing changes, on SQLite, PGlite and D1.

### 23.8 Changes in other packages

| Package | Change |
|---|---|
| agents | none: `usageLimits()` plugs into `AGENTS.USAGE_LIMITS` (§22) |
| tasks | none: webhooks use the interop object |
| tenants | `tenantNotRequired(view)` (as built): the webhook runs under `TENANTS.REQUIRED`; see 23.11 |
| cli | later: `startproject --billing` adds settings, URLs and `STRIPE_*` vars to `.dev.vars.example` |
| docs | topic "Billing", dj-stripe cheat-sheet rows |

### 23.9 Phases

1. **0.1**: the Stripe adapter, models, views, access helpers, REST permissions, signals, admin, sync command,
   checks, testing helpers.
2. **0.2**: Paddle and Lemon Squeezy adapters, usage-based billing (meter events from §22 counters), one-time
   payments, proration previews.
3. **Later**: payment methods and charges, tax ids, coupons in admin, a pricing-table component.

### 23.10 Open questions (proposed answers)

- **Refetch on every event** (dj-stripe re-retrieves objects). *Proposed:* no; trust the signed payload, skip stale
  subscription events by `lastEventAt`, refetch only what an event does not carry (the subscription of a completed
  checkout, a missing product).
- **Grace periods.** *Proposed:* through `ACTIVE_STATUSES` (`['active', 'trialing', 'past_due']`) rather than a
  separate setting.

### 23.11 As built (supersedes 23.1–23.10 where they conflict)

- **Package:** peers `@ghuri/core`, `@ghuri/orm`, `hono` (required), `@ghuri/rest`, `@ghuri/admin` (optional, only
  behind `/rest` and `/admin`). Subpaths `.`, `/testing`, `/admin`, `/rest`. Nothing in `src` imports a Node module
  or an SDK (a test enforces it); a workerd test bundles the app with esbuild and runs checkout, a signed webhook and
  `getPlan()` on Miniflare + D1. `@ghuri/tasks` and `@ghuri/tenants` are devDependencies only (tests of the
  interop path and of `TENANTS.REQUIRED`).
- **Provider interface** also has `parseEvent(raw)` (re-processing a stored `Event.data` without its signature);
  `check({ debug, deploy })` returns the provider's own messages (`E002`, `E003`, `W001`). `stripe()` options:
  `secretKey`, `webhookSecret` (string or list), `apiVersion` (not pinned by default: the account's version; the
  normalizers read both pre- and post-2025-03-31 shapes), `tolerance` (300), `maxNetworkRetries` (2, on 429 / 5xx /
  network errors, same `Idempotency-Key`), `fetch`, `apiBase`. Keys live in private class fields: `JSON.stringify`,
  `inspect` and the debug page never show them.
- **Customer uniqueness** is a partial unique constraint `(subscriberType, subscriberId) WHERE NOT deleted`
  (`billing_customer_subscriber_uniq`), so a subscriber whose Stripe customer was deleted gets a new one. Works on
  Postgres, SQLite and D1. Two concurrent first checkouts can create two Stripe customers; the loser's is unused.
- **Plans:** `PlanConfig` also has `trialPeriodDays` (server-side trial for checkouts of the plan). When any plan
  lists `prices`, checkout accepts only plan prices (by id, lookup key or product); without, any active local price of
  an active product. `{ plan, interval }` picks the plan's local price with that interval. `getPlan()` returns
  `{ key, plan, subscription, active }`; `getEntitlements()` adds `active` and `subscription`.
- **Views:** a missing subscriber is 401 JSON `{ detail }` only (with `WWW-Authenticate` from the first
  authentication class when it has a scheme; there is no `LOGIN_URL` redirect, since both views accept only POST); a
  provider failure is 502 `{ detail, code }`; redirect URLs are relative (resolved on the request origin) or on the
  request host / a non-`*` `ALLOWED_HOSTS` entry, and Stripe's `{CHECKOUT_SESSION_ID}` placeholder survives.
  `subscriptionRequired({ plans?, redirectTo? })` answers 403 or 302. `requireSubscriber(c)` throws `NoSubscriber`
  (401).
- **Authentication of checkout and portal** follows DRF's `APIView`, so single-page apps call them with their API
  token or JWT: both views are `csrfExempt`, then run `BILLING.AUTHENTICATION_CLASSES` (structurally `@ghuri/rest`'s
  `BaseAuthentication`; default `REST_FRAMEWORK.DEFAULT_AUTHENTICATION_CLASSES`, read from settings without importing
  rest). The first class that returns a user wins and is `setUser()` on the request, so `BILLING.SUBSCRIBER` sees it;
  session classes enforce CSRF, token / JWT classes do not. With classes and no match, the request user becomes
  anonymous (an ambient session cookie the classes do not accept cannot skip CSRF). Without either setting, the
  session user of `AuthenticationMiddleware`, with `enforceCsrf()` for an authenticated user (as before, when
  `CsrfMiddleware` checked them). *Why not only document `BILLING.SUBSCRIBER`:* a JWT request without a CSRF cookie
  is refused by `CsrfMiddleware` before any subscriber callback runs.
- **Tenants:** the webhook view carries `@ghuri/tenants`' `tenantNotRequired()` marker,
  `Symbol.for('ghuri.tenantNotRequired')`, set without importing tenants. Under `TENANTS.REQUIRED` it runs with no
  tenant (an unknown tenant is still 404, and every other tenant-less request still answers 404). Processing needs no
  tenant (billing's tables are not tenant-scoped); receivers that touch tenant-scoped models call `runAsTenant()`
  with the customer's subscriber. *Why not resolve the tenant from the event's customer:* `TenantMiddleware` answers
  404 before the view can read and verify the body, so an exemption is needed either way, and a resolver that parsed
  unverified webhook bodies would be a new trust boundary. `tenantNotRequired()` mirrors Django 5.1's
  `login_not_required` and keeps `REQUIRED` fail-closed for unmarked views.
- **Webhook processing:** `handleWebhook()` returns `{ eventId, type, result }` with `processed`, `ignored`,
  `duplicate`, `queued` or `busy`. A delivery claims the stored event with a compare-and-set on `attempts`, so two
  concurrent deliveries never both process it. Processing is not wrapped in a transaction (D1 has none across
  statements); every step is an idempotent upsert, so a retry finishes the job. `invoice.deleted` (drafts) deletes the
  row. Prices and products are deactivated, never deleted, on `*.deleted`. A price whose product is unknown fetches
  the product; a subscription whose customer is unknown fetches the customer.
- **Usage limits** match §22.3 as built (`UsageSubject { scope, key, user }` → `{ day?, month? } | null`, called for
  every run): `usageLimits(limit, { scope?, otherwise?, cacheSeconds? })` caches a subscriber's entitlements in
  memory for `cacheSeconds` (default 60), cleared in-process by the subscription signals and by
  `clearEntitlementsCache()`; other isolates see a plan change within the TTL.
- **Tasks:** `billing.processEvent(eventId)` (`maxAttempts: 3`) is defined in an `onPopulate` hook when the interop
  object exists, like `agents.run`.
- **Admin:** every model is registered read-only (no add or delete); events have the action `process_again`.
- **Tests (73):** the flow suite on SQLite, PGlite and D1 (migrations with no missing changes, sync command,
  checkout guards, completed checkout, access helpers, duplicate and stale events, cancellation, invoices, product
  / price / customer events, forged and stale signatures, rotation, failure and replay), Stripe adapter unit tests,
  REST permissions, the decorator, checks, per-tenant billing, the webhook under `TENANTS.REQUIRED`, JWT and session
  authentication of checkout / portal (CSRF), `requireSubscriber()` as 401, the tasks path, the admin action,
  workerd.
- **Workspace:** `billing` sits after `tasks` in `scripts/bootstrap.sh` `REPOS` and `scripts/publish-all.sh` `ORDER`.
- **Not yet:** `startproject --billing`, an `examples/blog` integration, separate test-mode and live-mode customers
  for one subscriber (switching keys needs a fresh customer table or `deleted` rows), Paddle / Lemon Squeezy.
