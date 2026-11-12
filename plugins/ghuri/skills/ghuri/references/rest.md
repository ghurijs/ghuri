# REST framework (@ghuri/rest)

Cheat-sheet for `@ghuri/rest` (a DRF port): serializers, views, viewsets, routers, request/response, exceptions, permissions, authentication, filtering, pagination, throttling, OpenAPI and `REST_FRAMEWORK` settings.

## DRF habit -> Ghuri

| DRF (Python) | Ghuri (TypeScript) |
|---|---|
| `from rest_framework import serializers` / `serializers.CharField` | `import { CharField, ModelSerializer } from '@ghuri/rest'` (flat exports, no namespaces) |
| `class Meta: model = Post; fields = [...]` | `static Meta = { model: Post, fields: [...] }` |
| `read_only_fields`, `extra_kwargs` | `readOnlyFields`, `extraKwargs: { email: { writeOnly: true } }` |
| `Serializer(instance, data=d, partial=True)` | `new S({ instance, data: d, partial: true })` (one options object; `new S(post)` also works) |
| `serializer.is_valid(raise_exception=True)` | `await serializer.isValid({ raiseException: true })` |
| `serializer.data` | `await serializer.getData()` (`.data` only after that; it throws otherwise) |
| `serializer.validated_data` | `serializer.validatedData` (sync, after `isValid()`) |
| `validate_title(self, value)` | `validateTitle(value)` (may be async) |
| `get_comment_count(self, obj)` | `getCommentCount(obj)` (may be async) |
| `serializer_class`, `permission_classes`, `perform_create` | `serializerClass`, `permissionClasses`, `performCreate` |
| `get_queryset()`, `get_object()`, `get_serializer_class()` | `getQueryset()`, `await getObject()`, `getSerializerClass()` |
| `@action(detail=True, methods=['post'])` | `@action({ detail: true, methods: ['post'] })` |
| `request.query_params`, `request.data` | `request.query` (Record) / `request.queryParams` (URLSearchParams), `request.data` (sync) |
| `Response(data, status=201)` | `new APIResponse(data, { status: status.HTTP_201_CREATED })` or just `return data` |
| `IsAuthenticated \| IsAdminUser`, `&`, `~` | `IsAuthenticated.or(IsAdminUser)`, `.and(...)`, `.not()` |
| `DjangoModelPermissions` / `DjangoObjectPermissions` | `ModelPermissions` / `ObjectPermissions` |
| `django_filters.rest_framework.DjangoFilterBackend` | `FieldFilter` (alias `DjangoFilterBackend`), `filtersetFields` |
| `router.register(r'posts', V, basename='p')` | `router.register('posts', V, { basename: 'p' })` |
| `'rest_framework.authentication.TokenAuthentication'` (dotted string) | the class itself, imported from `@ghuri/auth/rest` |
| `drf-spectacular` `@extend_schema` | `@extendSchema({...})`, `SchemaView`, `SwaggerUIView`, `ScalarView` |

## Serializers

```ts
import { CharField, ModelSerializer, SerializerMethodField, SlugRelatedField, ValidationError } from '@ghuri/rest'
import { Comment, Post, Tag } from './models'

export class PostSerializer extends ModelSerializer<Post> {
  static Meta = {
    model: Post,
    fields: ['id', 'title', 'slug', 'body', 'author', 'authorName', 'tags', 'published', 'commentCount', 'createdAt'],
    readOnlyFields: ['author'],
    extraKwargs: { slug: { required: false } },
  }
  authorName = new CharField({ source: 'author.username', readOnly: true })
  tags = new SlugRelatedField({ slugField: 'slug', many: true, required: false, queryset: Tag.objects.all() })
  commentCount = new SerializerMethodField()          // calls getCommentCount(obj)

  async getCommentCount(post: Post) {
    return Comment.objects.filter({ post: post.pk, approved: true }).count()
  }

  validateTitle(value: string) {                       // field-level hook: validate<FieldName>
    if (value.toLowerCase().includes('spam')) throw new ValidationError('No spam, please.')
    return value                                       // must return the value
  }

  validate(attrs: Record<string, unknown>) {            // object-level; must return attrs
    if (attrs.published && !attrs.body) throw new ValidationError({ body: ['A published post needs a body.'] })
    return attrs
  }
}
```

`Meta` options (`ModelSerializerMeta`): `model`, `fields` (array or `'__all__'`), `exclude`, `readOnlyFields`, `extraKwargs`, `depth` (nested read-only output), `validators` (e.g. `UniqueTogetherValidator`; replaces generated ones), `listSerializerClass`, `fullClean` (also run the model's `fullClean()` before save). A declared field always wins; a declared field missing from `fields` is appended (DRF would raise). `HyperlinkedModelSerializer` adds a `url` field via `<basename>-detail`.

Plain `Serializer`: declare fields as instance properties and implement `create()` / `update()` yourself (`save()` throws if missing).

```ts
import { CharField, DateTimeField, EmailField, Serializer } from '@ghuri/rest'
import { Contact } from './models'

export class ContactSerializer extends Serializer {
  name = new CharField({ maxLength: 100 })
  email = new EmailField()
  sentAt = new DateTimeField({ readOnly: true })
  async create(data: Record<string, unknown>) { return Contact.objects.create(data) }
}
```

### Lifecycle

```ts
import { PostSerializer } from './serializers'
import { Post } from './models'

const s = new PostSerializer({ data: payload })
if (await s.isValid()) s.validatedData else s.errors     // { field: ['msg'], nonFieldErrors: [...] }
await s.isValid({ raiseException: true })                // throws REST ValidationError -> 400
const post = await s.save({ author: user })              // extra kwargs merged into validatedData
const out = await s.getData()                            // after save; never call save() after getData()

const edit = new PostSerializer({ instance: post, data: { title: 'New' }, partial: true })
await edit.isValid({ raiseException: true }); await edit.save()   // save() -> update()

const one = await new PostSerializer(post).getData()
const many = await new PostSerializer({ instance: Post.objects.filter({ published: true }), many: true }).getData()
const list = PostSerializer.many({ instance: posts })    // typed ListSerializer alternative
PostSerializer.jsonSchema()                              // JSON Schema 2020-12 (used by OpenAPI + agents)
```

Constructor options (`SerializerOptions`): `instance`, `data`, `partial`, `context`, `many`, `allowEmpty`, `maxLength`, `minLength`, plus any field option (for nesting). Generic views pass `context = { request, view, format }`.

Validation order: field checks -> field `validators` -> `validate<Field>()`; then `Meta.validators` -> `validate()`. Hooks may be async and may throw either `@ghuri/rest`'s or `@ghuri/core`'s `ValidationError`. Errors from `validate()` without a key go under `nonFieldErrors` (`NON_FIELD_ERRORS_KEY`). `ModelSerializer` auto-adds `UniqueValidator` for `unique: true` fields and `UniqueTogetherValidator` for `uniqueTogether`.

### Fields

Common options (`FieldOptions`): `readOnly`, `writeOnly`, `required`, `default`, `initial`, `source` (dotted `'author.username'` awaits relations; `'*'` = whole object), `label`, `helpText`, `style`, `errorMessages`, `validators`, `allowNull`.

| Field | Notes |
|---|---|
| `CharField`, `EmailField`, `URLField`, `SlugField`, `UUIDField`, `IPAddressField` | `maxLength`, `minLength`, `allowBlank`, `trimWhitespace` |
| `RegexField(regex, opts)` | regex is the first positional argument |
| `IntegerField`, `FloatField` | `minValue`, `maxValue` |
| `DecimalField` | `maxDigits`, `decimalPlaces`, `coerceToString` (strings by default) |
| `BooleanField`, `NullBooleanField` | accepts `true`, `"true"`, `"1"`, `"on"`... |
| `DateTimeField`, `DateField`, `TimeField`, `DurationField` | ISO 8601; `format`, `inputFormats` |
| `ChoiceField(choices, opts)`, `MultipleChoiceField(choices, opts)` | choices is positional: array, `[value, label][]`, Record or Map |
| `ListField`, `DictField` | `{ child: new IntegerField() }` |
| `JSONField`, `FileField`, `ImageField` | file fields take multipart `File`s, output URL (`useUrl`) |
| `SerializerMethodField` | read-only; `get<Name>(obj)` or `{ methodName }`; `{ schema }` for OpenAPI |
| `HiddenField({ default })` | never from input, not in output: `new HiddenField({ default: new CurrentUserDefault() })` |
| `ReadOnlyField` | renders the attribute as-is |

Defaults: a value, a function, `new CurrentUserDefault()` (needs `request` in context), `new CreateOnlyDefault(v)`.

### Relations

```ts
import { PrimaryKeyRelatedField, SlugRelatedField, StringRelatedField, HyperlinkedRelatedField, ModelSerializer } from '@ghuri/rest'
import { Post, Tag, Comment } from './models'

export class CommentSerializer extends ModelSerializer<Comment> {
  static Meta = { model: Comment, fields: ['id', 'post', 'author', 'tags', 'body', 'link'] }
  post = new PrimaryKeyRelatedField({ queryset: Post.objects.filter({ published: true }) })   // FK default
  author = new StringRelatedField()                                     // toString(), read-only
  tags = new SlugRelatedField({ slugField: 'name', many: true, queryset: Tag.objects.all() })
  link = new HyperlinkedRelatedField({ viewName: 'post-detail', source: 'post', readOnly: true })
}
```

FK defaults to `PrimaryKeyRelatedField`, M2M to an array of pks; writable relation fields need `queryset` (or `readOnly: true`). Nested serializers (`comments = new CommentSerializer({ many: true, readOnly: true })`) are read-only; for nested writes override `create()`/`update()`. `ModelSerializer.create()/update()` set M2M fields after save automatically. Use `selectRelated`/`prefetchRelated` in the view queryset to avoid N+1; prefer `annotate({ n: Count('comments') })` + `IntegerField({ readOnly: true })` over a per-row `SerializerMethodField` count on big lists.

## Views

```ts
import { APIResponse, APIView, apiView, IsAuthenticated, status, type APIRequest } from '@ghuri/rest'
import { Post } from './models'

export class StatsView extends APIView {
  permissionClasses = [IsAuthenticated]
  async get(request: APIRequest) {
    const total = await Post.objects.filter({ author: request.user.pk }).count()
    return new APIResponse({ total }, { status: status.HTTP_200_OK })   // or `return { total }`
  }
}

export const whoami = apiView(['GET'], { permissionClasses: [IsAuthenticated] })(
  async (request, kwargs) => ({ id: request.user.pk, username: request.user.username }),
)
// urls.ts: path('api/stats/', StatsView.asView(), { name: 'stats' }), path('api/whoami/', whoami)
```

Handlers get `(request, kwargs)`; also `this.request`, `this.kwargs`, `this.format`, `this.c` (Hono context). Return `APIResponse`, a fetch `Response`, or plain data (wrapped). Undefined methods -> 405. API views are CSRF-exempt; session-style auth enforces CSRF itself. Policy attributes: `authenticationClasses`, `permissionClasses`, `throttleClasses`, `throttleScope`, `parserClasses`, `rendererClasses`, `contentNegotiationClass`, `metadataClass`, `schema`. `asView({...})` initkwargs override instance attributes. `apiView(methods, opts)` options: same policy names plus `name`, `description`.

### Generic views and mixins

`GenericAPIView` attributes: `queryset`, `serializerClass`, `lookupField` (default `'pk'`), `lookupUrlKwarg`, `lookupValueRegex`, `lookupValueConverter` (`'int'`, `'uuid'`, `'slug'`), `filterBackends`, `paginationClass` (`null` disables), `searchFields`, `orderingFields`, `ordering`, `filtersetFields`. Methods: `getQueryset()`, `await getObject()` (404 + object permissions), `getSerializer(opts)`, `getSerializerClass()`, `getSerializerContext()`, `filterQueryset(qs)`, `await paginateQueryset(qs)`, `getPaginatedResponse(data)`.

Concrete: `CreateAPIView`, `ListAPIView`, `RetrieveAPIView`, `DestroyAPIView`, `UpdateAPIView`, `ListCreateAPIView`, `RetrieveUpdateAPIView`, `RetrieveDestroyAPIView`, `RetrieveUpdateDestroyAPIView`.

Mixins are class factories (no multiple inheritance): `ListModelMixin`, `CreateModelMixin` (`performCreate`), `RetrieveModelMixin`, `UpdateModelMixin` (`update`, `partialUpdate`, `performUpdate`), `DestroyModelMixin` (`performDestroy`).

```ts
import { CreateModelMixin, GenericAPIView, GenericViewSet, ListCreateAPIView, ListModelMixin, type APIRequest } from '@ghuri/rest'
import { Comment, Tag } from './models'
import { CommentSerializer, TagSerializer } from './serializers'

export class TagList extends ListModelMixin(CreateModelMixin(GenericAPIView)) {
  queryset = Tag.objects.all()
  serializerClass = TagSerializer
  async get(request: APIRequest) { return this.list(request) }
  async post(request: APIRequest) { return this.create(request) }
}
export class TagListCreateViewSet extends CreateModelMixin(ListModelMixin(GenericViewSet)) { queryset = Tag.objects.all(); serializerClass = TagSerializer }

export class CommentList extends ListCreateAPIView {        // path('api/posts/<int:postId>/comments/', CommentList.asView())
  serializerClass = CommentSerializer
  getQueryset() { return Comment.objects.filter({ post: this.kwargs.postId }) }
  async performCreate(serializer: CommentSerializer) {
    await serializer.save({ postId: this.kwargs.postId })
  }
}
```

## ViewSets

`ViewSet` (no actions), `GenericViewSet` (generic plumbing, no actions), `ReadOnlyModelViewSet` (`list`, `retrieve`), `ModelViewSet` (`list`, `create`, `retrieve`, `update`, `partialUpdate`, `destroy`). On the instance: `this.action` (`'list'`, `'publish'`, `'metadata'` for OPTIONS), `this.detail`, `this.basename`, `this.reverseAction('detail', { pk })`.

```ts
import { Q } from '@ghuri/orm'
import {
  type APIRequest, action, FieldFilter, IsAdminUser, IsAuthenticatedOrReadOnly,
  ModelViewSet, OrderingFilter, PageNumberPagination, SearchFilter,
} from '@ghuri/rest'
import { Post } from './models'
import { IsAuthorOrReadOnly } from './permissions'
import { PostListSerializer, PostSerializer } from './serializers'

export class BlogPagination extends PageNumberPagination {
  pageSize = 10
  pageSizeQueryParam = 'pageSize'
  maxPageSize = 100
}

export class PostViewSet extends ModelViewSet<Post> {
  queryset = Post.objects.all().selectRelated('author').prefetchRelated('tags')
  serializerClass = PostSerializer
  permissionClasses = [IsAuthenticatedOrReadOnly, IsAuthorOrReadOnly]
  paginationClass = BlogPagination
  filterBackends = [SearchFilter, OrderingFilter, FieldFilter]
  searchFields = ['title', 'body', 'author__username', 'tags__name']
  orderingFields = ['createdAt', 'title']
  ordering = ['-createdAt']
  filtersetFields = { published: ['exact'], tags__slug: ['exact'], createdAt: ['gte', 'lte'] }
  lookupField = 'slug'                                       // route posts/<slug>/, this.kwargs.slug

  getQueryset() {
    const qs = super.getQueryset()
    const user = this.request.user
    if (user.isStaff) return qs
    if (user.isAuthenticated) return qs.filter(Q({ published: true }).or(Q({ author: user.pk })))
    return qs.filter({ published: true })
  }

  getSerializerClass() {
    return this.action === 'list' ? PostListSerializer : PostSerializer
  }

  async performCreate(serializer: PostSerializer) {
    await serializer.save({ author: this.request.user })
  }

  @action({ detail: true, methods: ['post'] })               // POST /posts/<slug>/publish/  name post-publish
  async publish(_request: APIRequest) {
    const post = await this.getObject()
    post.published = true
    await post.save({ updateFields: ['published', 'updatedAt'] })
    return { status: 'published', slug: post.slug }
  }

  @action({ detail: false, permissionClasses: [IsAdminUser] }) // GET /posts/drafts/
  async drafts(_request: APIRequest) {
    const qs = this.filterQueryset(this.getQueryset().filter({ published: false }))
    const page = await this.paginateQueryset(qs)
    const data = await this.getSerializer({ instance: page ?? qs, many: true }).getData()
    return page ? this.getPaginatedResponse(data) : data
  }
}
```

`@action` options (`ActionOptions`): `detail` (required), `methods` (default `['get']`), `urlPath` / `urlName` (default kebab-case method name: `setFeatured` -> `set-featured/`), `name`, `suffix`, `description`, plus any view attribute override (`permissionClasses`, `serializerClass`, `throttleScope`...). It is a TC39 decorator (also works with `experimentalDecorators`). Without decorators (e.g. Vitest/oxc cannot lower TC39 decorators): `static actions = { publish: action({ detail: true, methods: ['post'] }) }`. Per-action permissions: `@action({ permissionClasses })` or override `getPermissions()` returning instances (`[new IsAdminUser()]`).

## Routers

```ts
import { include, path } from '@ghuri/core'
import { DefaultRouter, SimpleRouter } from '@ghuri/rest'
import { CommentViewSet, PostViewSet, TagViewSet } from './blog/views'

export const router = new DefaultRouter()           // { trailingSlash, includeRootView, includeFormatSuffixes, rootViewName }
router.register('posts', PostViewSet)               // basename 'post' derived from queryset's model
router.register('tags', TagViewSet)
router.register('comments', CommentViewSet, { basename: 'comment' })   // required if no `queryset` attribute

export const urlpatterns = [path('api/', include(router.urls))]
```

Routes: `posts/` (`post-list`), `posts/<lookup>/` (`post-detail`), extra actions `post-<urlName>`. Only implemented actions are routed. `DefaultRouter` adds the API root (`api-root`) and `.json` suffix routes; `SimpleRouter` does not. Namespaces: `include(router.urls, { namespace: 'v1' })` -> `reverse('v1:post-detail', { pk: 7 })`. Keep the router in its own module (`src/router.ts`) so urls and agents can import it without cycles. Introspection: `router.registry[i]` (`prefix`, `basename`, `model`, `actions`, `endpoints`, `getSerializerClass(action)`, `jsonSchema(action)`, `await invoke(action, { user, data, kwargs })`), `router.describe()`.

## APIRequest, APIResponse, status

`request.data` (parsed body, sync property; `ParseError`/`UnsupportedMediaType` raised on first read), `request.files`, `request.query` (`Record<string,string>`, first value), `request.queryParams` (`URLSearchParams`), `request.user` (`AnonymousUser` if none), `request.auth` (token/payload), `request.method`, `request.path`, `request.headers`, `request.header(name)`, `request.raw` (fetch `Request`), `request.c` (Hono context), `request.buildAbsoluteUri(loc)`.

`new APIResponse(data, { status, headers, contentType })` or `new APIResponse(data, 201)`. `status.HTTP_201_CREATED`, `status.HTTP_204_NO_CONTENT`, `status.isSuccess(code)`, `isClientError`, `isServerError`, `isRedirect`, `isInformational`.

## Exceptions

From `@ghuri/rest`: `APIException`, `ValidationError` (400), `ParseError` (400), `AuthenticationFailed` (401), `NotAuthenticated` (401), `PermissionDenied` (403), `NotFound` (404), `MethodNotAllowed` (405), `NotAcceptable` (406), `UnsupportedMediaType` (415), `Throttled` (429). Bodies: `{ detail: '...' }` or the field-error dict for validation. Core `Http404`, `PermissionDenied`, `ValidationError` and ORM `DoesNotExist` are mapped automatically. Replace the handler with `REST_FRAMEWORK.EXCEPTION_HANDLER: (exc, context) => APIResponse | null` (default `exceptionHandler`).

```ts
import { APIException } from '@ghuri/rest'

export class ServiceUnavailable extends APIException {
  static statusCode = 503
  static defaultDetail = 'Service temporarily unavailable, try again later.'
  static defaultCode = 'service_unavailable'
}
```

## Permissions

Built-ins: `AllowAny` (default), `IsAuthenticated`, `IsAdminUser` (`isStaff`), `IsAuthenticatedOrReadOnly`, `ModelPermissions` (`<app>.add_/change_/delete_<model>`; override `permsMap`), `ModelPermissionsOrAnonReadOnly`, `ObjectPermissions`. `SAFE_METHODS = ['GET', 'HEAD', 'OPTIONS']`. Listing several classes = AND.

```ts
import { type APIRequest, BasePermission, IsAdminUser, IsAuthenticated, SAFE_METHODS } from '@ghuri/rest'
import type { Post } from './models'

export class IsAuthorOrReadOnly extends BasePermission {
  message = 'Only the author can change this post.'        // 403 detail (also `code`)
  async hasObjectPermission(request: APIRequest, _view: unknown, post: Post) {
    if (SAFE_METHODS.includes(request.method)) return true
    return post.authorId === request.user.pk || request.user.isStaff === true
  }
}

export const StaffOrAuthor = IsAdminUser.or(IsAuthenticated.and(IsAuthorOrReadOnly))
export const LoggedInNonStaff = IsAuthenticated.and(IsAdminUser.not())
```

`hasPermission(request, view)` runs every request; `hasObjectPermission(request, view, obj)` only inside `getObject()` (or call `await this.checkObjectPermissions(request, obj)` yourself). List actions never run object checks: filter in `getQueryset()`. Unauthenticated + denied -> 401 if the view's first authentication class has `authenticateHeader()`, else 403.

## Authentication

| Class | Import | Credentials |
|---|---|---|
| `MiddlewareAuthentication` (default) | `@ghuri/rest` | user set by `AuthenticationMiddleware`; CSRF on unsafe methods |
| `SessionAuthentication` | `@ghuri/auth/rest` | session cookie; CSRF on unsafe methods |
| `TokenAuthentication` | `@ghuri/auth/rest` | `Authorization: Token <key>` (`Token` model, `AuthTokenConfig` app; `keyword`, `model` overridable) |
| `JWTAuthentication` | `@ghuri/auth/rest` | `Authorization: Bearer <access>` (settings key `JWT`) |
| `BasicAuthentication`, `RemoteUserAuthentication` | `@ghuri/auth/rest` | HTTP Basic / `Remote-User` proxy header |

```ts
import { include, path } from '@ghuri/core'
import { obtainAuthToken, TokenBlacklistView, TokenObtainPairView, TokenRefreshView, TokenVerifyView } from '@ghuri/auth/rest'
import { SchemaView, SwaggerUIView } from '@ghuri/rest'
import { router } from './router'

export const urlpatterns = [
  path('api/auth/token/', obtainAuthToken, { name: 'api-token' }),                     // {username,password} -> {token}
  path('api/auth/jwt/', TokenObtainPairView.asView(), { name: 'jwt-obtain' }),         // -> {refresh, access}
  path('api/auth/jwt/refresh/', TokenRefreshView.asView(), { name: 'jwt-refresh' }),   // {refresh} -> {access, refresh?}
  path('api/auth/jwt/verify/', TokenVerifyView.asView(), { name: 'jwt-verify' }),      // {token} -> 200 {} / 401
  path('api/auth/jwt/blacklist/', TokenBlacklistView.asView()),                         // {refresh} -> revoke
  path('api/schema/', SchemaView.asView({ title: 'Blog API', version: '1.0.0' }), { name: 'schema' }),
  path('api/docs/', SwaggerUIView.asView({ urlName: 'schema' }), { name: 'swagger-ui' }),
  path('api/', include(router.urls)),
]
```

`obtainAuthToken` is already a view function (no `.asView()`); the JWT views are classes (call `.asView()`). Token endpoints are CSRF-exempt. Custom class: `implements BaseAuthentication` (an interface, not a base class) with `async authenticate(c: Context): Promise<[RequestUser, unknown] | null>` (return `null` when the header is absent; throw `AuthenticationFailed` when invalid), optional `authenticateHeader(c)` and `static securityScheme = { name, scheme }` for OpenAPI.

## Filtering

```ts
import { BaseFilterBackend, type APIRequest } from '@ghuri/rest'

// FieldFilter:   filtersetFields = ['published', 'author']  or  { createdAt: ['gte', 'lte'], tags__name: ['exact', 'in'] }
//                -> ?published=true&createdAt__gte=2026-01-01&tags__name__in=a,b   (undeclared params ignored; bad values -> 400)
// SearchFilter:  searchFields = ['^title', 'body', '=author__username']  -> ?search=foo bar  (^ istartswith, = iexact, @ icontains, $ iregex)
// OrderingFilter: orderingFields = ['createdAt', 'title'] (or '__all__'), ordering = ['-createdAt'] -> ?ordering=-createdAt,title
export class RecentFilter extends BaseFilterBackend {
  filterQueryset(request: APIRequest, qs: any, _view: unknown) {
    const days = Number(request.query.recent)
    return days ? qs.filter({ createdAt__gte: new Date(Date.now() - days * 86_400_000) }) : qs
  }
  getSchemaOperationParameters() {
    return [{ name: 'recent', in: 'query', schema: { type: 'integer' } }]
  }
}
```

Param names: `SEARCH_PARAM` (`'search'`), `ORDERING_PARAM` (`'ordering'`). No `FilterSet` class: complex filtering goes in `getQueryset()` or a custom backend.

## Pagination

| Class | Query | Attributes | Envelope |
|---|---|---|---|
| `PageNumberPagination` | `?page=3` (`?page=last`) | `pageSize` (default `PAGE_SIZE`), `pageQueryParam`, `pageSizeQueryParam`, `maxPageSize`, `lastPageStrings` | `{ count, next, previous, results }` |
| `LimitOffsetPagination` | `?limit=10&offset=40` | `defaultLimit`, `limitQueryParam`, `offsetQueryParam`, `maxLimit` | `{ count, next, previous, results }` |
| `CursorPagination` | `?cursor=...` | `pageSize`, `ordering` (default `'-createdAt'`), `cursorQueryParam`, `pageSizeQueryParam`, `maxPageSize` | `{ next, previous, results }` |

Enable via `DEFAULT_PAGINATION_CLASS` + `PAGE_SIZE` or per view `paginationClass`. Custom envelope: override `getPaginatedResponse(data)` and `getPaginatedResponseSchema(schema)`. On D1, count queries read every matching row; prefer `CursorPagination` for big feeds.

## Throttling

`AnonRateThrottle` (scope `anon`), `UserRateThrottle` (scope `user`), `ScopedRateThrottle` (view's `throttleScope`), base `SimpleRateThrottle` / `BaseThrottle` (`allowRequest(request, view)`, `wait()`). Rates: `'100/hour'`, `'10/s'`, `'10/5m'`. Every scope used needs a `DEFAULT_THROTTLE_RATES` entry (`null` disables). History lives in the core cache (`THROTTLE_CACHE`, default `'default'`); 429 with `Retry-After`.

## OpenAPI

New projects (`ghuri startproject`) already route `path('api/schema/', SchemaView…, { name: 'schema' })`, `api/docs/` (`SwaggerUIView`) and `api/reference/` (`ScalarView`) before `path('api/', include(router.urls))`, and install `RestFrameworkConfig` (from `@ghuri/rest`, DRF's `'rest_framework'`), which adds `npx ghuri generateschema [--file openapi.yaml] [--format openapi|openapi-json]`. That command reuses the first `SchemaView` in `ROOT_URLCONF`, so the file matches the served schema. Don't add the routes twice and don't hand-write OpenAPI: shape it with `extendSchema` / `AutoSchema` below.

`SchemaView.asView({ title, version, description, info, servers, patterns, prefix, cacheSchema })` serves OpenAPI 3.1 JSON (defaults to `ROOT_URLCONF`). `SwaggerUIView.asView({ urlName: 'schema' })` / `ScalarView.asView({ urlName: 'schema' })` (or `schemaUrl`, `cdn`, `title`). Per view: `schema = new AutoSchema({ tags, operationIdBase, componentName })` or `schema = null` to exclude. Per operation:

```ts
import { action, extendSchema, ModelViewSet, type APIRequest } from '@ghuri/rest'
import { Post } from './models'

export class PostViewSet extends ModelViewSet<Post> {
  @extendSchema({ summary: 'Publish a post', request: null, responses: { 200: { type: 'object' } }, tags: ['posts'] })
  @action({ detail: true, methods: ['post'] })
  async publish(_request: APIRequest) { return { status: 'published' } }
}
```

`extendSchema` keys: `operationId`, `summary`, `description`, `tags`, `deprecated`, `exclude`, `request`, `responses`, `parameters`, `extensions`. Offline: `generateSchema(urlpatterns | router, { title, version, prefix, servers })` (sync). Docs views obey `permissionClasses` like any view.

## REST_FRAMEWORK settings

```ts
import { JWTAuthentication, SessionAuthentication, TokenAuthentication } from '@ghuri/auth/rest'
import { defineSettings } from '@ghuri/core'
import { AnonRateThrottle, FieldFilter, IsAuthenticatedOrReadOnly, OrderingFilter, PageNumberPagination, SearchFilter, UserRateThrottle } from '@ghuri/rest'

export default defineSettings((env) => ({
  // ...
  REST_FRAMEWORK: {
    DEFAULT_AUTHENTICATION_CLASSES: [TokenAuthentication, JWTAuthentication, SessionAuthentication],
    DEFAULT_PERMISSION_CLASSES: [IsAuthenticatedOrReadOnly],
    DEFAULT_PAGINATION_CLASS: PageNumberPagination,
    PAGE_SIZE: 20,
    DEFAULT_FILTER_BACKENDS: [FieldFilter, SearchFilter, OrderingFilter],
    DEFAULT_THROTTLE_CLASSES: [AnonRateThrottle, UserRateThrottle],
    DEFAULT_THROTTLE_RATES: { anon: '100/hour', user: '1000/day' },
  },
  JWT: { ACCESS_TOKEN_LIFETIME: 15 * 60, REFRESH_TOKEN_LIFETIME: 7 * 24 * 60 * 60 },   // seconds
}))
```

All keys (`RestFrameworkSettings`): `DEFAULT_RENDERER_CLASSES`, `DEFAULT_PARSER_CLASSES`, `DEFAULT_AUTHENTICATION_CLASSES`, `DEFAULT_PERMISSION_CLASSES`, `DEFAULT_THROTTLE_CLASSES`, `DEFAULT_CONTENT_NEGOTIATION_CLASS`, `DEFAULT_METADATA_CLASS`, `DEFAULT_PAGINATION_CLASS`, `DEFAULT_FILTER_BACKENDS`, `DEFAULT_SCHEMA_CLASS`, `PAGE_SIZE`, `DEFAULT_THROTTLE_RATES`, `NUM_PROXIES`, `THROTTLE_CACHE`, `UNAUTHENTICATED_USER`, `UNAUTHENTICATED_TOKEN`, `SEARCH_PARAM`, `ORDERING_PARAM`, `EXCEPTION_HANDLER`, `NON_FIELD_ERRORS_KEY`, `URL_FORMAT_OVERRIDE`, `FORMAT_SUFFIX_KWARG`, `URL_FIELD_NAME`, `DATE_FORMAT`, `DATE_INPUT_FORMATS`, `DATETIME_FORMAT`, `DATETIME_INPUT_FORMATS`, `TIME_FORMAT`, `TIME_INPUT_FORMATS`, `COERCE_DECIMAL_TO_STRING`, `UPLOADED_FILES_USE_URL`, `COMPACT_JSON`, `STRICT_JSON`, `HTML_SELECT_CUTOFF`, `HTML_SELECT_CUTOFF_TEXT`, `TEST_REQUEST_DEFAULT_FORMAT`. Read at request time with `apiSettings.PAGE_SIZE`.

## Testing (pointer)

`APIClient` from `@ghuri/rest/testing`: `new APIClient(app, { env, defaultFormat: 'json' })`, `forceAuthenticate(user)`, `credentials({ Authorization: 'Token ...' })`, `get(path, query)`, `post(path, data, { format })`, `res.data` is parsed JSON. See the testing reference for setup.

```ts
import { APIClient } from '@ghuri/rest/testing'
```

## Gotchas

- `serializer.data` throws until `await serializer.getData()`; `isValid()`, `save()`, `getData()` are all async. Call `isValid()` before `save()`, and never `save()` after `getData()`.
- Hooks are camelCase: `validateTitle`, `getCommentCount`; snake_case `validate_title` is silently ignored. `validate()` and `validate<Field>()` must return the value.
- Constructor is one options object: `new S({ instance, data, partial })`, not positional `S(instance, data)`.
- `ChoiceField`/`MultipleChoiceField`/`RegexField` take choices/regex as the FIRST positional argument, not `{ choices }`.
- Import field classes from `@ghuri/rest` in serializers; the ORM's `CharField` etc. share names but are model fields.
- Use `ValidationError` from `@ghuri/rest` in serializers/views; core's also works in hooks, but don't mix up the imports.
- Settings take classes, not dotted strings. Token/JWT/Session auth classes come from `@ghuri/auth/rest`, not `@ghuri/rest`. The default auth (`MiddlewareAuthentication`) ignores `Authorization: Token` headers.
- Put `TokenAuthentication`/`JWTAuthentication` before `SessionAuthentication` if you want 401 + `WWW-Authenticate` for anonymous API calls (first class decides 401 vs 403).
- Permission composition is `A.or(B)` / `A.and(B)` / `A.not()`, not `|`, `&`, `~`.
- Mixins are functions: `ListModelMixin(CreateModelMixin(GenericAPIView))`, never `extends A, B`.
- Viewsets go through a router; `MyViewSet.asView()` without an action map throws. `obtainAuthToken` is used directly; JWT views need `.asView()`.
- Load single objects with `await this.getObject()` (runs object permissions); go through `getQueryset()`, not `this.queryset`.
- Pass the owner via `serializer.save({ author: this.request.user })` in `performCreate`, or `HiddenField({ default: new CurrentUserDefault() })`; don't trust client data.
- `request.data` is a sync property (no `await request.json()`); query params are `request.query`, not `query_params`.
- No API versioning classes, no `TemplateHTMLRenderer`, no `FilterSet`, no YAML schema renderer, no Redoc view (use `ScalarView`).
- Decorators: `@action` works as a TC39 or legacy decorator. Vitest (oxc) only lowers legacy ones, so keep `oxc: { decorator: { legacy: true } }` in `vitest.config.ts` (as examples/blog does), or use `static actions = { name: action({...}) }`.
- Mount `api/schema/` and `api/docs/` paths before `path('api/', include(router.urls))`, as the example app does.
