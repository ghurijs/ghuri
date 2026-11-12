# URLs, views and middleware

Covers `@ghuri/core` routing (`path`/`rePath`/`include`/`reverse`), function and class-based views over Hono's `Context`, errors, auth decorators, JSX rendering, middleware, settings access and `AppConfig`.

## Django habit -> Ghuri

| Django | Ghuri |
|---|---|
| `ROOT_URLCONF = 'mysite.urls'` (dotted string) | `ROOT_URLCONF: urlpatterns` (the imported array itself) |
| `path('p/<int:id>/', view, name='detail')` | `path('p/<int:id>/', view, { name: 'detail' })` |
| `re_path(r'^x/(?P<y>\d+)/$', v)` | `rePath('^x/(?P<y>[0-9]+)/$', v)` (`(?<y>...)` also works) |
| `include('blog.urls')` | `include(blogUrls)` (an imported module or array) |
| `app_name = 'blog'` | `urlpatterns('blog', [...])` or `export const appName = 'blog'` |
| `register_converter(C, 'yyyy')` | `registerConverter('yyyy', { regex, toJs, toUrl })` |
| `reverse('blog:detail', kwargs={'id': 1})` | `reverse('blog:detail', { id: 1 })` |
| `def view(request, id)` | `function view(c: Context)` + `kwargs(c).id` |
| `request.GET.get('q')` | `c.req.query('q')` |
| `request.POST` / `request.FILES` | `await c.req.parseBody()` |
| `json.loads(request.body)` | `await c.req.json()` |
| `request.user` | `getUser(c)` |
| `request.session` | `c.get('session')` (needs `SessionMiddleware` from `@ghuri/auth`) |
| `request.resolver_match` | `resolverMatch(c)` |
| `JsonResponse(d, status=201)` | `json(c, d, 201)` or `c.json(d, 201)` |
| `redirect('home')` | `redirect(c, 'home')` |
| `render(request, 'x.html', ctx)` | `render(c, <Page {...ctx} />)` or `c.html(<Page />)` (Hono JSX, no templates) |
| `MyView.as_view(x=1)` | `MyView.asView({ x: 1 })` |
| `@login_required` | `loginRequired(view)` from `@ghuri/auth` |
| `@require_POST` / `require_http_methods` | `path('x/', view, { methods: ['POST'] })` (no decorator exists) |

## URL patterns

```ts
import { include, path, rePath } from '@ghuri/core'
import { admin } from '@ghuri/admin'
import type { Context } from 'hono'
import { router } from './router'
import * as blogUrls from './blog/urls'
import { AboutView } from './views'

function home(c: Context) {
  return c.json({ ok: true })
}

export const urlpatterns = [
  path('', home, { name: 'home' }),
  path('about/', AboutView, { name: 'about' }),            // View class: asView() called for you
  path('blog/', include(blogUrls)),                         // namespace from appName
  path('news/', include(blogUrls.urlpatterns, { namespace: 'news' })),
  path('admin/', admin.site.urls),                          // a pattern array
  path('api/', include(router.urls)),                       // @ghuri/rest router
  rePath('^feeds/(?P<format>rss|atom)/$', home, { name: 'feed' }),
  path('upload/', home, { methods: ['POST'] }),             // other methods -> 405 + Allow
  path('terms/', home, { kwargs: { page: 'terms' } }),      // extra kwargs merged into kwargs(c)
]
```

App-level `src/blog/urls.ts`:

```ts
import { path, urlpatterns as patterns } from '@ghuri/core'
import * as views from './views'

export const urlpatterns = patterns('blog', [
  path('', views.index, { name: 'index' }),
  path('<slug:slug>/', views.detail, { name: 'detail' }),
])
```

- `path(route, target, { name?, methods?, kwargs? })`. `target` may be a view function, a `View` class, `X.asView(...)`, `include(...)`, a pattern array, or a `Hono` instance (mounted as-is; sees paths relative to the prefix).
- Routes have no leading slash and end in `/`, like Django. First match wins.
- `APPEND_SLASH` (default `true`): GET/HEAD `/x` -> 301 `/x/` if only the slashed path matches. The app does this even without `CommonMiddleware`. POSTs are never redirected.

### Converters

| Converter | Regex | `kwargs(c)` value |
|---|---|---|
| `<x>` / `<str:x>` | `[^/]+` | string |
| `<int:x>` | `[0-9]+` | number |
| `<slug:x>` | `[-a-zA-Z0-9_]+` | string |
| `<uuid:x>` | lowercase UUID | string |
| `<path:x>` | `.+` (includes `/`) | string |

`c.req.param('id')` is always the raw string (and is missing for routes that fall back to regex matching: `rePath` with complex regexes, two params in one segment). Use `kwargs(c)` for converted values.

```ts
import { kwargs, registerConverter } from '@ghuri/core'
import type { Context } from 'hono'

registerConverter('year', { regex: '[0-9]{4}', toJs: Number, toUrl: (v) => String(v) })  // before patterns use it

export async function archive(c: Context) {
  const { year, month } = kwargs<{ year: number; month: number }>(c)
  return c.json({ year, month })
}
```

### reverse / resolve

```ts
import { NoReverseMatch, resolve, resolveUrl, resolverMatch, reverse } from '@ghuri/core'

reverse('home')                                    // '/'
reverse('blog:detail', { slug: 'hello' })          // '/blog/hello/'
reverse('archive', [2026, 11])                     // positional
reverse('blog:index', {}, { query: { page: 2 } })  // '/blog/?page=2'
resolve('/blog/hello/').viewName                   // 'blog:detail'
resolveUrl('blog:index')                           // URL name, absolute path, or obj.getAbsoluteUrl()
```

`reverse()`/`resolve()` read `ROOT_URLCONF` from the current context; they throw outside a request/`app.setup()` unless you pass `{ urlconf }`. Unknown names throw `NoReverseMatch`.

## Function views

A view is `(c: Context) => Response | Promise<Response>`. It MUST return a `Response` (returning a plain object raises `ImproperlyConfigured`). It may also `throw` a `Response`.

```ts
import { getUser, json, kwargs, PermissionDenied, redirect } from '@ghuri/core'
import { getObjectOr404 } from '@ghuri/orm'
import type { Context } from 'hono'
import { Post } from './models'

export async function detail(c: Context) {
  const post = await getObjectOr404(Post, { slug: kwargs(c).slug })
  if (!post.published && post.authorId !== getUser(c).pk) throw new PermissionDenied()
  return json(c, { title: post.title, q: c.req.query('q') ?? null })
}

export async function create(c: Context) {
  const body = await c.req.parseBody()          // form / multipart; c.req.json() for JSON
  const post = await Post.objects.create({ title: String(body.title), slug: String(body.slug), author: getUser(c) })
  return redirect(c, 'blog:detail', { slug: post.slug })   // or { permanent: true } as 4th arg
}
```

Shortcuts (all `@ghuri/core` unless noted): `json(c, data, status?, headers?)` (handles bigint/Map/Set), `render(c, jsx, { status?, headers?, doctype? })`, `redirect(c, to, params?, { permanent?, status? })`, `resolveUrl(to, params?)`, `getUser(c)`, `kwargs(c)`, `resolverMatch(c)`, `getObjectOr404` / `getListOr404` (`@ghuri/orm`). For JSON APIs prefer `@ghuri/rest` views (parsing, auth, permissions, serializers).

### HTML with Hono JSX

No template language. Name the file `.tsx`, `"jsxImportSource": "hono/jsx"` in tsconfig. JSX output is escaped; use `raw`/`html` from `hono/html` for trusted markup.

```ts
import { getCsrfToken, render, reverse } from '@ghuri/core'
import type { Context } from 'hono'
import { Post } from './models'

export async function index(c: Context) {
  const posts = await Post.objects.filter({ published: true }).slice(0, 20)
  return render(c,
    <html><body>
      <ul>{posts.map((p) => <li><a href={reverse('blog:detail', { slug: p.slug })}>{p.title}</a></li>)}</ul>
      <form method="post"><input type="hidden" name="csrfmiddlewaretoken" value={getCsrfToken(c)} /></form>
    </body></html>,
  )
}
```

## Class-based views

Built in: `View`, `TemplateView`, `RedirectView`. No `ListView`/`DetailView`/`FormView`/`CreateView` (use `@ghuri/rest` generics or write a `View`).

```ts
import { getUser, json, RedirectView, TemplateView, View } from '@ghuri/core'
import { LoginRequiredMixin } from '@ghuri/auth'
import type { Context } from 'hono'
import { Post } from './models'

export class DraftsView extends LoginRequiredMixin(View) {
  pageSize = 20
  async get(c: Context) {
    const drafts = await Post.objects.filter({ published: false, author: getUser(c).pk }).slice(0, this.pageSize)
    return json(c, drafts)
  }
}

export class AboutView extends TemplateView {
  template = (p: { title: string }) => <h1>{p.title}</h1>
  async getContextData() {
    return { ...(await super.getContextData()), title: 'About' }
  }
}

// urls: path('drafts/', DraftsView.asView({ pageSize: 50 })),
//       path('old/', RedirectView.asView({ patternName: 'home', permanent: true })),
//       path('p/<int:id>/', RedirectView.asView({ url: '/posts/{id}/', queryString: true })),
```

- New instance per request; `this.c`, `this.request` (`c.req`), `this.kwargs` are set in `setup(c)`. Override `setup`/`dispatch` for shared logic.
- Missing method -> 405 with `Allow`; HEAD falls back to `get`; OPTIONS answers 200 with `Allow`.
- `asView(initkwargs)` rejects HTTP method names as keys. `static csrfExempt = true` exempts the class.
- `TemplateView`: `template`, `getTemplate()`, `getContextData()`, `extraContext`, `status`, `renderToResponse()`.
- `RedirectView`: `url` (`{param}` placeholders), `patternName`, `permanent`, `queryString`; neither set -> 410.

## Access decorators and mixins (`@ghuri/auth`)

Plain wrapper functions, not `@decorators`:

```ts
import { loginRequired, permissionRequired, staffMemberRequired, userPassesTest } from '@ghuri/auth'
import { csrfExempt, ensureCsrfCookie, path } from '@ghuri/core'
import { create, detail, index, webhook } from './views'

export const urlpatterns = [
  path('new/', loginRequired(create)),
  path('new2/', loginRequired({ loginUrl: 'accounts:login' })(create)),
  path('edit/', permissionRequired('blog.change_post')(detail)),
  path('perms/', permissionRequired(['blog.add_post', 'blog.change_post'], { raiseException: true })(detail)),
  path('staff/', staffMemberRequired(index)),
  path('vip/', userPassesTest((u) => !!u.isSuperuser)(index)),
  path('hook/', csrfExempt(webhook)),       // also works on a mounted Hono app
  path('spa/', ensureCsrfCookie(index)),
]
```

`AccessOptions`: `loginUrl`, `redirectFieldName` (default `next`), `raiseException`. Anonymous browsers are redirected to `LOGIN_URL` (default `/accounts/login/`); JSON clients get 401; authenticated users without permission get 403. Mixins are class factories: `LoginRequiredMixin(View)`, `PermissionRequiredMixin(View)` (set `permissionRequired = 'app.codename'`), `UserPassesTestMixin(View)` (implement `testFunc(c)`), `AccessMixin(View)`.

## Errors -> responses

Throw from views (or anything they call). From `@ghuri/core` unless noted:

| Thrown | Status |
|---|---|
| `Http404`, `ObjectDoesNotExist`, any `Model.DoesNotExist`, `Resolver404` | 404 |
| `PermissionDenied`, `CsrfFailure` | 403 |
| `BadRequest`, `SuspiciousOperation`, `DisallowedHost` | 400 |
| `ValidationError('msg' \| ['a'] \| { field: ['msg'] })` | 400 `{ detail, errors }` |
| `MethodNotAllowed(method, allowed)` | 405 + `Allow` |
| `HttpError` subclass with `status` | that status |
| Hono `HTTPException` | its status/response |
| anything else | 500 (debug page with `DEBUG`) |

Body is JSON `{ "detail": ... }` when `wantsJson(c)` (path under `API_PATH_PREFIXES`, default `['/api']`, or JSON Accept/Content-Type, or XHR), HTML otherwise. Custom mapping: `registerExceptionHandler(ErrClassOrPredicate, (err, c) => Response | undefined)` (later registrations tried first), or `createApp(settings, { onError })`. `handleException(err, c)` applies the full mapping manually.

## Middleware

```ts
import { CommonMiddleware, CorsMiddleware, CsrfMiddleware, defineSettings, getSettings, Middleware,
  SecurityMiddleware, XFrameOptionsMiddleware } from '@ghuri/core'
import { AuthenticationMiddleware, SessionMiddleware } from '@ghuri/auth'
import type { Context, Next } from 'hono'
import { urlpatterns } from './urls'

export class TimingMiddleware extends Middleware {
  async handle(c: Context, next: Next) {
    if (getSettings().MAINTENANCE_MODE) return c.text('Back soon.', 503)  // short-circuit: return a Response
    const t = Date.now()
    await next()                                                          // c.res is the response afterwards
    c.header('Server-Timing', `app;dur=${Date.now() - t}`)
  }
}

export default defineSettings((env) => ({
  SECRET_KEY: env.SECRET_KEY,
  INSTALLED_APPS: [],
  ROOT_URLCONF: urlpatterns,
  MIDDLEWARE: [
    SecurityMiddleware,
    new CorsMiddleware({ allowOrigins: ['https://app.example.com'], allowCredentials: true }),
    CommonMiddleware,
    SessionMiddleware,
    CsrfMiddleware,
    AuthenticationMiddleware,   // must come after SessionMiddleware
    XFrameOptionsMiddleware,
    TimingMiddleware,
  ],
  CORS: false,   // or { allowOrigins: '*' | string[], allowCredentials?, allowMethods?, allowHeaders?, exposeHeaders?, maxAge? }
}))
```

- `MIDDLEWARE` entries: a `Middleware` subclass, a configured instance, or plain Hono middleware (`logger()` from `hono/logger`). First entry is outermost. Classes are instantiated once per isolate: never store per-request state on `this` (use `c.set()`).
- No `process_view`/`process_exception`: wrap `await next()` in try/catch or use `registerExceptionHandler`.
- Before `MIDDLEWARE`, the app always installs the request context, sends `requestStarted`, and validates `ALLOWED_HOSTS`.
- Built-ins in `@ghuri/core`: `SecurityMiddleware` (nosniff, Referrer-Policy, COOP, HSTS when `SECURE_HSTS_SECONDS > 0`, `SECURE_SSL_REDIRECT`), `CommonMiddleware` (`PREPEND_WWW`, hosts, slash), `CorsMiddleware` (`CORS` setting or constructor options), `CsrfMiddleware`, `XFrameOptionsMiddleware` (`X_FRAME_OPTIONS`, default `DENY`), `GZipMiddleware` (no-op on Workers). `SessionMiddleware`, `AuthenticationMiddleware`, `RemoteUserMiddleware` are in `@ghuri/auth`.
- `toHonoMiddleware(entry)` converts a Ghuri middleware for use in a plain Hono app. `createApp(settings, { hono: (app) => {...} })` customizes the root Hono app (runs after MIDDLEWARE, before URLs).
- CSRF: send the `csrftoken` cookie value as `X-CSRFToken` header or `csrfmiddlewaretoken` form field. Helpers: `getCsrfToken(c)`, `rotateCsrfToken(c)`, `enforceCsrf(c)`, `checkCsrf(c)`. Token/JWT-authenticated REST calls are not CSRF-checked; session-authenticated ones are.

## Settings and context access

```ts
import { getContext, getEnv, getSettings, setting, tryGetContext } from '@ghuri/core'

const debug = getSettings().DEBUG
const perPage = setting('BLOG_PER_PAGE', 20)            // with fallback
const ai = getEnv().AI                                  // raw binding with no Ghuri adapter only
getContext().executionCtx?.waitUntil(Promise.resolve()) // work after the response (Workers)
const maybe = tryGetContext()                           // undefined outside request/setup instead of throwing
```

All of these throw `ImproperlyConfigured` at module top level (no `env` exists before the first request). `settingsFor(c)` returns settings from a Hono context without throwing. Type custom keys with `declare module '@ghuri/core' { interface GhuriSettings { BLOG_PER_PAGE?: number } }`.

## AppConfig

```ts
import { AppConfig, tryGetContext } from '@ghuri/core'
import * as admin from './admin'
import * as migrations from './migrations'
import * as models from './models'
import * as signals from './signals'
import { PublishCommand } from './commands'

export class BlogConfig extends AppConfig {
  name = 'blog'                    // required; label defaults to last segment
  verboseName = 'Blog'
  path = import.meta.dirname       // CLI writes migrations here
  models = models                  // every exported Model is registered under this label
  migrations = migrations          // generated migrations/index.ts
  admin = admin                    // importing registers ModelAdmins
  modules = { signals }            // any other side-effect modules
  commands = { publish: PublishCommand }

  ready() {                        // once per isolate, after all models registered; may be async
    if (tryGetContext()?.settings.DEBUG) console.log('blog ready')
  }
}
```

Nothing is auto-discovered: a model, admin, signal or command module that is not assigned on the config does not exist. Registry: `apps.getModel('blog.Post')`, `apps.getAppConfig('blog')`, `apps.isInstalled('blog')`, `apps.getModels()`.

## Gotchas

- `ROOT_URLCONF` is the array, not a string. `include()` takes an imported module/array, never `'blog.urls'`.
- Options are an object: `path('x/', v, { name: 'x' })`, not `name='x'` or a 3rd string.
- Views receive Hono `Context` (`c`), not a `request`; URL params are NOT function arguments. Use `kwargs(c)` (converted) not `c.req.param()` (string) for `<int:...>`.
- A view must return a `Response`; `return { ok: true }` fails (that only works in `@ghuri/rest` `@action`s).
- `redirect`, `json`, `render` take `c` as the first argument.
- No templates, `{% csrf_token %}`, or `render(request, 'x.html')`: use JSX and `getCsrfToken(c)`.
- Decorators are function wrappers: `loginRequired(view)`, `permissionRequired('a.b')(view)`; they live in `@ghuri/auth`, not core. There is no `requireHttpMethods`/`require_POST`, `cache_page` or `never_cache`; use `{ methods: [...] }`.
- `reverse(name, { id })` - no `kwargs=`/`args=` keys; positional params are an array.
- Middleware is `handle(c, next)` with `await next()`, not `__call__`/`get_response`/`process_request`. Middleware strings (`'django.middleware...'`) are not accepted - import the classes.
- Never read settings or `getEnv()` at module top level, and never touch `env.DB`/`env.MEDIA` in app code.
- `ALLOWED_HOSTS` is enforced even without `CommonMiddleware`; tests hit `testserver`.
