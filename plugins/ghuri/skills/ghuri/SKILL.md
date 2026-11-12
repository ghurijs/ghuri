---
name: ghuri
description: Write correct code for Ghuri, the Django-style TypeScript framework (Hono + Drizzle, Cloudflare Workers with D1/R2 by default, Node + Postgres too). Use whenever package.json depends on @ghuri/* packages (@ghuri/core, @ghuri/orm, @ghuri/auth, @ghuri/rest, @ghuri/admin, @ghuri/graphql, @ghuri/realtime, @ghuri/storage, @ghuri/agents, @ghuri/oauth, @ghuri/socialauth, @ghuri/cli), files import from them, package.json has a "ghuri" key or `ghuri` scripts, or the user mentions Ghuri. Covers models, queries, migrations, settings, URLs, views, middleware, REST serializers/viewsets/routers, admin, auth, permissions, social login (GitHub/Google/OIDC, allauth-style), OAuth/OIDC/magic-link login strategies (Passport-style), GraphQL, WebSockets, file storage, AI agents/MCP, signals, cache, cron/queues, management commands, tests and deployment. Ghuri is NOT Python Django, DRF, Prisma or plain Hono, even though names look like Django's; do not write Python or snake_case APIs.
---

# Ghuri

Ghuri is "Django for TypeScript": `settings.ts` with `INSTALLED_APPS`, apps with models, migrations, `urls.ts`, class-based views, an admin, a DRF-style REST framework, graphene-style GraphQL, Channels-style WebSockets, file storage, auth and AI agents. It is built on Hono and Drizzle and runs on Cloudflare Workers (D1, R2, KV, Queues, Durable Objects) by default, and on Node with Postgres with the same code.

It is brand new, so your instincts are wrong in predictable ways: the names are Django's, but the syntax is TypeScript, options are camelCase, everything that touches the database is `async`, and nothing is discovered by file name. Read the reference file for the area you touch before writing code (index at the bottom).

## Check the real project first

- If the `ghuri` MCP server is connected (tools `project_info`, `list_apps`, `list_models`, `describe_model`, `list_routes`, `list_commands`, `show_migrations`, `run_command`, `search_docs`, `get_doc`), use it before editing: inspect the real models, routes, apps and migration state instead of guessing, run `makemigrations` / `migrate` / `check` / `test` through `run_command`, and use `search_docs` when unsure an API exists.
- Without it, read `src/settings.ts`, `src/urls.ts` and the relevant `src/<app>/` files, and run `npx ghuri <command>` in the shell.
- Full docs (one file, for search): https://ghurijs.github.io/docs/llms-full.txt. Only use APIs that the docs, these references or the project's own code show exist. If a Django/DRF feature is not listed, assume it does not exist and say so rather than inventing it.

## Mental model: Django -> Ghuri

| Django / DRF | Ghuri |
|---|---|
| `django-admin startproject mysite` / `startapp blog` | `npm create ghuri@latest mysite` / `npx ghuri startapp blog` |
| `python manage.py <cmd>` | `npx ghuri <cmd>` (`makemigrations`, `migrate`, `createsuperuser`, `shell`, `test`, `check`, `routes`) |
| `settings.py` constants | `export default defineSettings((env) => ({ ... }))` (`@ghuri/core`) |
| `INSTALLED_APPS = ['blog']` | `INSTALLED_APPS: [ContentTypesConfig, AuthConfig, ..., BlogConfig]` (imported classes) |
| `apps.py` `AppConfig` | `class BlogConfig extends AppConfig { name = 'blog'; models = models; migrations = migrations; admin = admin }` |
| `ROOT_URLCONF = 'mysite.urls'` | `ROOT_URLCONF: urlpatterns` (the imported array) |
| `class Post(models.Model): title = models.CharField(max_length=200)` | `class Post extends Model({ title: new CharField({ maxLength: 200 }) }) {}` |
| `class Meta: ordering = [...]` | `static Meta = { ordering: [...] }` |
| `on_delete=models.CASCADE, related_name='posts'` | `{ onDelete: CASCADE, relatedName: 'posts' }` (`CASCADE` from `@ghuri/orm`) |
| `auto_now_add=True`, `null=True, blank=True` | `autoNowAdd: true`, `null: true, blank: true` |
| `__str__` | `toString()` |
| `Post.objects.filter(title__icontains='x').order_by('-created_at')[:10]` | `await Post.objects.filter({ title__icontains: 'x' }).orderBy('-createdAt').slice(0, 10)` |
| `post.author` / `post.author_id` / `user.post_set` | `await post.author` / `post.authorId` / `user.postSet` (or the `relatedName`) |
| `Q(a=1) \| ~Q(b=2)`, `F('views') + 1` | `Q({ a: 1 }).or(Q.not({ b: 2 }))`, `F('views').add(1)` |
| `get_or_create(..., defaults=)` | `const [obj, created] = await getOrCreate({...}, { defaults: {...} })` |
| `with transaction.atomic():` | `await atomic(async () => {...})` (no rollback on D1) |
| `path('posts/<int:id>/', view, name='detail')` | `path('posts/<int:id>/', view, { name: 'detail' })` |
| `def view(request, id)` | `function view(c: Context)` with `kwargs(c).id`; return `c.json(...)` |
| `request.user`, `request.GET` | `getUser(c)`, `c.req.query('q')` |
| `@login_required` | `loginRequired(view)` (`@ghuri/auth`) |
| `class PostSerializer(serializers.ModelSerializer)` | `class PostSerializer extends ModelSerializer<Post> { static Meta = { model: Post, fields: [...] } }` |
| `serializer.is_valid()` / `.data` | `await serializer.isValid()` / `await serializer.getData()` |
| `ModelViewSet`, `perform_create`, `@action(detail=True)` | `ModelViewSet<Post>`, `async performCreate(serializer)`, `@action({ detail: true })` |
| `IsAuthenticated \| IsAdminUser` | `IsAuthenticated.or(IsAdminUser)` |
| `class PostAdmin(admin.ModelAdmin): list_display = (...)` | `class PostAdmin extends ModelAdmin<Post> { listDisplay = [...] }` |
| `@receiver(post_save, sender=Post)` | `postSave.connect(async ({ instance, created }) => {...}, { sender: Post })` |
| Celery / cron | `onQueue('emails', fn)` / `onSchedule('0 3 * * *', fn)` (`@ghuri/core`) + wrangler config |
| `TestCase`, `self.client` | Vitest via `npx ghuri test`, `setupTestDatabase()`, `APIClient` |

## Golden rules

1. **TypeScript, ES modules, camelCase.** Field options, Meta options, methods and hooks are camelCase (`maxLength`, `onDelete`, `relatedName`, `autoNowAdd`, `dbIndex`, `verboseName`, `orderBy`, `selectRelated`, `getQueryset`, `performCreate`, `validateTitle`, `listDisplay`). Settings keys stay `UPPER_SNAKE`. DB columns are snake_case automatically.
2. **Keyword arguments become one object**: `filter({ author__username: 'ana', createdAt__year: 2026 })`, `save({ updateFields: ['title'] })`. The `__` lookup syntax is unchanged.
3. **Await every database touch**: QuerySets (`await qs`), `get`, `first`, `count`, `exists`, `create`, `save`, `delete`, `update`, FK access (`await post.author`), related managers, serializers (`isValid`, `getData`, `save`), `user.hasPerm`, `user.checkPassword`, cache calls.
4. **Models**: `class X extends Model({ ...fields }) { static Meta = {...} }`, fields from `@ghuri/orm` (files from `@ghuri/storage`). Add `declare static objects: Manager<X>` for typing. Never declare model fields as class properties.
5. **After any model change run `npx ghuri makemigrations` then `npx ghuri migrate`.** Never hand-write CREATE TABLE SQL, Prisma schemas or drizzle-kit migrations for Ghuri models. Commit the generated files.
6. **Nothing is discovered by name.** Register the app's `AppConfig` in `INSTALLED_APPS`; the AppConfig imports its `models`, `migrations` (generated `migrations/index.ts`), `admin` module, `commands`. URLs are included explicitly in `src/urls.ts`.
7. **Settings are a function of `env`** and only `settings.ts` names bindings: `d1('DB')`, `postgres({ url: env.DATABASE_URL })`, `r2('MEDIA')`, `kvCache('CACHE')`. App code never calls `env.DB`, `env.MEDIA` or D1/R2 APIs directly; it uses the ORM, `storages`/`FileField` and `cache`. Never read settings at module top level: call `getSettings()` / `setting()` inside functions.
8. **Views take a Hono `Context`** (`c`) and return a `Response` (`c.json(...)`, `json(c, data)`, `redirect(c, 'name')`, `c.html(<Page />)`). Only REST views/actions may return plain data.
9. **Import from the right package**: auth decorators and `User` from `@ghuri/auth`; `TokenAuthentication`, `JWTAuthentication`, `SessionAuthentication`, `obtainAuthToken` from `@ghuri/auth/rest`; REST serializer field classes from `@ghuri/rest` (same names as ORM fields, different classes); Node-only modules (`@ghuri/core/node`, `@ghuri/orm/sqlite`, `@ghuri/orm/pglite`, `@ghuri/storage/fs`) never in Worker code paths.
10. **Tests run with `npx ghuri test`** (Vitest, `src/**/tests.ts` and `*.test.ts`), using `setupTestDatabase()` from `@ghuri/orm/testing` and `APIClient` from `@ghuri/rest/testing`. Run them, plus `npx ghuri check`, after changes.
11. **D1 has no transactions**: `atomic()` does not roll back there. Use single-statement writes (`qs.update()` with `F()`, `bulkCreate()`), `(await connections.get()).batch?.([...])`, or Postgres.
12. **Non-interactive commands**: pass `--no-input` (`makemigrations`, `migrate`, `createsuperuser`, `deploy`); prompts hang without a TTY. With `--no-input`, renames become remove + add, so give new NOT NULL fields a default.

## Workflows

**Start a project**
1. `npm create ghuri@latest mysite` (`-- --db d1|postgres|sqlite`, `--graphql`), `cd mysite`.
2. `npx ghuri migrate`, `npx ghuri createsuperuser`, `npm run dev` (wrangler dev on :8787; `--db sqlite` serves Node on :8000).
3. Install extra packages with the `next` tag: `npm install @ghuri/graphql@next graphql`.

**Add an app**
1. `npx ghuri startapp blog` (creates `src/blog/` and adds `BlogConfig` to `INSTALLED_APPS`).
2. Add `path('blog/', include(blogUrls))` to `src/urls.ts` (`import * as blogUrls from './blog/urls'`). See urls-views-middleware.md.

**Add a model + migration**
1. Edit `src/<app>/models.ts` (models-and-queries.md). Relations: `new ForeignKey(() => Other, { onDelete: CASCADE, relatedName: '...' })`.
2. `npx ghuri makemigrations <app>` -> check the new file in `src/<app>/migrations/` -> `npx ghuri migrate`.
3. Data changes: `npx ghuri makemigrations <app> --empty --name backfill_x` + `ops.RunCode(async (apps, conn, { using }) => {...})` (migrations.md).

**Expose a REST API** (rest.md)
1. `serializers.ts`: `class PostSerializer extends ModelSerializer<Post> { static Meta = { model: Post, fields: [...], readOnlyFields: [...] } }`.
2. `views.ts`: `class PostViewSet extends ModelViewSet<Post> { queryset = Post.objects.all(); serializerClass = PostSerializer; permissionClasses = [IsAuthenticatedOrReadOnly] }`; set the owner in `async performCreate(serializer) { await serializer.save({ author: this.request.user }) }`.
3. Router: `router.register('posts', PostViewSet)` on a `DefaultRouter`, mounted with `path('api/', include(router.urls))`.
4. OpenAPI is automatic: new projects already route `api/schema/` (`SchemaView`), `api/docs/` (Swagger UI) and `api/reference/` (Scalar) before the router include, so don't add them again (older projects: see rest.md). For a file, `npx ghuri generateschema --file openapi.yaml` (needs `RestFrameworkConfig` in `INSTALLED_APPS`). Tune operations with `@extendSchema(...)` or exclude a view with `schema = null`. Never hand-write the OpenAPI document.

**Register in the admin** (admin.md)
1. `admin.ts`: `@admin.register(Post) export class PostAdmin extends ModelAdmin<Post> { listDisplay = [...]; searchFields = [...] }` (or `admin.site.register(Post)`).
2. In `app.ts`: `import * as admin from './admin'` and `admin = admin` (no autodiscover). `AdminConfig` in `INSTALLED_APPS`, `path('admin/', admin.site.urls)` in urls.
3. Vitest needs `oxc: { decorator: { legacy: true } }` in `vitest.config.ts` for decorators.

**Add auth / permissions** (auth.md, rest.md)
- Function views: `loginRequired(view)`, `permissionRequired('blog.change_post')(view)`, `getUser(c)`.
- API: `REST_FRAMEWORK.DEFAULT_AUTHENTICATION_CLASSES: [TokenAuthentication, JWTAuthentication, SessionAuthentication]` from `@ghuri/auth/rest`; token/JWT endpoints `obtainAuthToken`, `TokenObtainPairView.asView()`. Object rules: subclass `BasePermission` with `async hasObjectPermission(request, view, obj)`.
- Custom user: `Model({...}, { extends: AbstractUser })` + `AUTH_USER_MODEL: 'accounts.User'` before the first migrate; reusable code uses `getUserModel()`.

**Add social login / custom login flows** (social-login-and-oauth.md)
- "Log in with GitHub/Google/…": `npm install @ghuri/socialauth@next @ghuri/oauth@next`, `SocialAuthConfig` in `INSTALLED_APPS`, `SOCIALACCOUNT: { PROVIDERS: { github: { APP: { clientId: env.GITHUB_CLIENT_ID, secret: env.GITHUB_SECRET } } } }`, `path('accounts/', include(socialUrls))`, then `migrate`. Login buttons POST to `/accounts/<provider>/login/` with the CSRF token; callback URL is `/accounts/<provider>/login/callback/`.
- Your own flow (any OIDC/OAuth2 provider in code, magic links, API keys): `strategies.use('name', new OIDCStrategy({...}, verify))` and `path('login/name/', authenticate('name', {...}))` from `@ghuri/oauth`. Not Passport, not allauth: no `passport.authenticate()`, no `allauth.*` apps.

**Add GraphQL** (graphql.md)
`GraphQLConfig` in `INSTALLED_APPS`; `ModelType` classes with `static Meta = { model, fields, interfaces: [Node], filterFields }`; a `Query` subclass with `static fields = { allPosts: ConnectionField(PostType) }`; `new Schema({ query: [BlogQuery], mutation: [...], types: [...] })`; `GRAPHQL: { SCHEMA: schema }`; `path('graphql/', GraphQLView.asView())`.

**Add a WebSocket consumer** (realtime.md)
`class ChatConsumer extends JsonWebSocketConsumer` with `static room = (scope) => ...`, `receiveJson`, event handlers named after the event type (`'chat.message'` -> `chatMessage`), per-connection data in `this.state`; route `path('ws/chat/<slug:room>/', ChatConsumer.asView())`. On Workers: `REALTIME: { LAYER: durableObjectLayer('REALTIME') }`, `export const GhuriRoom = createRoomClass(app)` in `src/index.ts`, and the Durable Object binding + migration in `wrangler.jsonc`.

**File uploads** (storage.md)
`STORAGES: { default: r2('MEDIA') }`; `cover: new ImageField({ uploadTo: 'covers/%Y/%m/', blank: true })`; REST multipart uploads work through `ModelSerializer`; serve with `path('media/<path:name>', serveMedia())`. Elsewhere use `defaultStorage().save(name, content)`.

**Add an AI agent / MCP endpoint** (agents.md)
`AgentsConfig` in `INSTALLED_APPS`, `AGENTS: { DEFAULT_MODEL: 'workers-ai:...' }`; `class SupportAgent extends Agent { instructions = '...'; tools = [new ModelTools(Post, {...})] }` plus `@tool({ description, input: z.object({...}) })` methods; `const agents = new AgentRouter(); agents.register('support', SupportAgent)`; `path('agents/', include(agents.urls))` and `path('mcp/', agents.mcp({ name, version, tools }))`. MCP auth = REST authentication classes (token header, no OAuth).

**Deploy to Cloudflare** (deployment.md)
`npx wrangler d1 create <name>` and paste `database_id`; `npx wrangler r2 bucket create <bucket>`; `npx wrangler secret put SECRET_KEY`; `npx ghuri check --deploy`; `npx ghuri deploy --migrate` (or `npx ghuri migrate --remote` then `wrangler deploy`). Keep `nodejs_compat`.

**Move D1 -> Postgres** (deployment.md)
Add `pg: postgres({ url: env.DATABASE_URL })` (or `{ hyperdrive: 'HYPERDRIVE' }`) to `DATABASES`; `npx ghuri migrate --database pg`; `npx ghuri copydata --from default --to pg`; then make `pg` the `default`. No model or migration changes.

## Common mistakes (Django/DRF/Prisma habits that break Ghuri)

- Writing Python, `models.Model`, `class Meta:`, `serializers.ModelSerializer`, `def get_queryset(self)`.
- snake_case: `max_length`, `on_delete`, `related_name`, `auto_now_add`, `order_by`, `select_related`, `values_list`, `get_or_create`, `perform_create`, `list_display`, `read_only_fields`, `post_set`, `author_id`, `is_staff`, `query_params`.
- Missing `await` (QuerySet used as an array, `post.author.username` on a promise, `if (user.hasPerm(...))` always truthy).
- `filter(title='x')`-style args or `Q(a=1) | Q(b=2)` / `~Q(...)` / `F('x') + 1` operators: use objects and `.or()`, `.and()`, `Q.not()`, `F('x').add(1)`.
- `aggregate(Avg('views'))` unnamed: write `aggregate({ avg: Avg('views') })`. `inBulk()` returns a `Map`; `delete()` returns `[total, perModel]`; the Manager has no `delete()` (use `.all().delete()`).
- Returning a QuerySet from an `async` function (it resolves to an array) - keep `getQueryset()` synchronous.
- Dotted strings for apps, middleware, URLconfs, permission/auth classes or `GRAPHQL.SCHEMA`: import the values.
- `include('blog.urls')`, `name='x'` positional args, `request` parameters on function views, `reverse('x', kwargs={...})`: use `include(blogUrls)`, `{ name: 'x' }`, `c: Context`, `reverse('x', { id: 1 })`.
- Forgetting to add the app to `INSTALLED_APPS`, `admin = admin` / `migrations = migrations` on the AppConfig, or the `include()` in `src/urls.ts`.
- Skipping `makemigrations` after editing models, or editing `migrations/index.ts` by hand; importing current models inside a data migration instead of `apps.getModel()`.
- `env.DB.prepare(...)`, `env.MEDIA.put(...)`, `process.env.X` in app code; `fs`, `better-sqlite3` or `@ghuri/storage/fs` on Workers.
- Expecting templates, forms, `{% csrf_token %}`, `render(request, 'x.html')`, Celery, `squashmigrations`, `inspectdb`, multi-table inheritance, proxy models, DB routers, i18n or GraphQL subscriptions: they don't exist. Use Hono JSX, serializers, queues.
- `DecimalField` values are strings, `DurationField` is milliseconds, `DateField`/`TimeField` are strings; only `DateTimeField` is a `Date`.
- Storing per-connection data on `this` in a consumer (rebuilt per event: use `this.state`); `memoryLayer()` on Workers.
- Importing `CharField` from `@ghuri/orm` into a serializer (use `@ghuri/rest`), or token/JWT auth from `@ghuri/rest` (use `@ghuri/auth/rest`).

## Reference files (read before working in that area)

| File | Read when |
|---|---|
| references/models-and-queries.md | defining models, fields, relations, managers; any query, lookup, Q/F, aggregate, transaction, raw SQL |
| references/migrations.md | after model changes, data migrations, rollbacks, applying to D1/Postgres |
| references/settings.md | editing `settings.ts`, INSTALLED_APPS, DATABASES/STORAGES/CACHES, reading settings/env, system checks |
| references/urls-views-middleware.md | `urls.ts`, `path`/`include`/`reverse`, function and class-based views, JSX, middleware, AppConfig |
| references/rest.md | serializers, viewsets, routers, API permissions/authentication, filtering, pagination, throttling, OpenAPI |
| references/admin.md | `ModelAdmin`, inlines, actions, list filters, admin hooks, custom admin sites |
| references/social-login-and-oauth.md | `@ghuri/socialauth` (providers, settings, URLs, adapter, SPA/native tokens) and `@ghuri/oauth` (strategies, `authenticate()`, REST bearer auth, testing) |
| references/auth.md | users, login/logout, sessions, permissions/groups, custom user model, tokens/JWT, password hashing |
| references/graphql.md | `ModelType`, `Query`/`Mutation`, Relay connections and filters, `SerializerMutation`, `GraphQLView` |
| references/realtime.md | WebSocket consumers, rooms, `channelLayer`, Durable Objects setup, socket auth |
| references/storage.md | `FileField`/`ImageField`, storage backends (R2/S3/fs/memory), uploads, serving media |
| references/agents.md | `Agent`, `@tool`, `ModelTools`/`ViewSetTools`/`RouterTools`, `AgentRouter`, MCP endpoints, providers |
| references/signals-cache-tasks-commands.md | signals, cache API, cron (`onSchedule`) and queues (`onQueue`), custom management commands |
| references/testing.md | writing or running tests, test databases, `APIClient`, test client, query counting |
| references/cli.md | any `ghuri` command and its flags, how the CLI loads the project, the `ghuri mcp` server |
| references/deployment.md | `wrangler.jsonc`, deploying to Workers, secrets, Node + Postgres, Docker, D1 -> Postgres |

A complete, tested example project is `examples/blog` in https://github.com/ghurijs/ghuri (models, admin, REST, GraphQL, agents, tests).
