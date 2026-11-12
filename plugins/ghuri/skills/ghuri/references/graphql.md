# GraphQL (@ghuri/graphql)

Covers graphene-django style GraphQL: `ModelType`, scalars and wrappers, `Query` / `Mutation` classes, `Schema`, Relay `Node` and `ConnectionField` (filter / orderBy), mutations (`SerializerMutation`, `ModelMutation`, plain), permissions, DataLoaders, `GraphQLView`, the `GRAPHQL` setting, `ghuri graphql_schema` and `@ghuri/graphql/testing`.

Install: `npm install @ghuri/graphql@next graphql` (graphql-js 17 is a peer). Subpath exports: `@ghuri/graphql` and `@ghuri/graphql/testing` only. Subscriptions are not supported. `@ghuri/rest` is an optional peer: serializer and permission classes are passed in, never imported by the package.

## graphene-django habit -> Ghuri

| graphene-django | Ghuri |
|---|---|
| `class PostType(DjangoObjectType): class Meta: model = Post` | `class PostType extends ModelType { static Meta = { model: Post, fields: [...] } }` |
| `title = graphene.String()` on the type | `static fields = { title: GString }` (extra fields; `Meta.fields` picks model fields) |
| `def resolve_title(self, info)` | `static resolveTitle(post, args, info)` (parent is the first arg, not `this`) |
| `get_queryset(cls, queryset, info)` | `static getQueryset(qs, info)`, synchronous, returns a QuerySet |
| `graphene.Field(T, id=graphene.ID(required=True))` | `Field(T, { args: { id: NonNull(ID) }, resolve })` |
| `required=True` | `NonNull(T)` or `Field(T, { required: true })` |
| `class Query(blog.Query, shop.Query, graphene.ObjectType)` | `new Schema({ query: [BlogQuery, ShopQuery] })` |
| `graphene.Schema(query=Query, mutation=Mutation)` | `new Schema({ query: [...], mutation: [...], types: [...] })` |
| `DjangoFilterConnectionField(T)` + `filter_fields` | `ConnectionField(T)` + `Meta.filterFields` |
| `allPosts(title_Icontains: "x")` | `allPosts(filter: { title: { icontains: "x" } })` |
| `class Arguments` + `def mutate(root, info, **kw)` | `static Arguments = {...}` + `static mutate(root, args, info)` |
| `relay.ClientIDMutation.mutate_and_get_payload` | `ClientIDMutation`: `static Input`, `static mutateAndGetPayload(root, input, info)` |
| `SerializerMutation` (`serializer_class`, `model_operations`, `lookup_field`) | `SerializerMutation` (`serializerClass`, `modelOperations`, `lookupField`) |
| `@login_required` (django-graphql-jwt) | `loginRequired(fn)` wrapper |
| `GRAPHENE = {'SCHEMA': 'mysite.schema.schema'}` | `GRAPHQL: { SCHEMA: schema }` (the object, not a dotted path) |

## Setup

```ts
// src/settings.ts
import { defineSettings } from '@ghuri/core'
import { SessionAuthentication, TokenAuthentication } from '@ghuri/auth/rest'
import { GraphQLConfig } from '@ghuri/graphql'
import { schema } from './schema'

export default defineSettings((env) => ({
  INSTALLED_APPS: [/* ... */ GraphQLConfig /* gives the graphql_schema command */],
  GRAPHQL: {
    SCHEMA: schema,
    AUTHENTICATION_CLASSES: [TokenAuthentication, SessionAuthentication],
    MAX_DEPTH: 10,
    RELAY_CONNECTION_MAX_LIMIT: 50,
  },
}))
```

```ts
// src/urls.ts
import { path } from '@ghuri/core'
import { GraphQLView } from '@ghuri/graphql'

export const urlpatterns = [path('graphql/', GraphQLView.asView(), { name: 'graphql' })]
```

```ts
// src/schema.ts -- the project schema, merging every app's Query / Mutation
import { Schema } from '@ghuri/graphql'
import { BlogMutation, BlogQuery, CommentType } from './blog/schema'

export const schema = new Schema({
  query: [BlogQuery],       // name clashes between apps are errors
  mutation: [BlogMutation],
  types: [CommentType],     // ModelTypes reachable only through relations MUST be listed
})
```

The schema is built lazily on first use, so importing it from `settings.ts` is fine. `schema.validate()` builds it eagerly (use in a test). `SchemaOptions` also take `optimize` (boolean or `{ only, maxDepth }`) and `description`. New projects: `npx ghuri startproject mysite --graphql`.

## ModelType

```ts
import { User } from '@ghuri/auth'
import { Field, ModelType, Node, type ResolveInfo, String as GString } from '@ghuri/graphql'
import { Q, type QuerySet } from '@ghuri/orm'
import { Post } from './models'

export class AuthorType extends ModelType {
  // ALWAYS list fields for models with sensitive columns (never expose password / email by default)
  static Meta = { model: User, fields: ['id', 'username', 'firstName', 'lastName'] }
}

export class PostType extends ModelType {
  static Meta = {
    model: Post,
    fields: ['id', 'title', 'slug', 'body', 'author', 'tags', 'published', 'comments', 'createdAt'],
    interfaces: [Node],
    filterFields: {
      title: ['exact', 'icontains', 'istartswith'],
      published: ['exact'],
      author__username: ['exact'],      // spans relations with __ -> GraphQL name authorUsername
      createdAt: ['gte', 'lte', 'year'],
    },
    orderBy: ['createdAt', 'title'],
  }

  static fields = {
    excerpt: Field(GString, {
      description: 'First 140 characters.',
      resolve: (post: Post) => post.body.slice(0, 140),
    }),
  }

  static resolveTitle(post: Post) {   // resolver for an existing field: resolve<FieldName>(parent, args, info)
    return post.title.trim()
  }

  // Row-level scoping: root lists, connections, node(), relation loaders and mutation lookups
  static getQueryset(qs: QuerySet<Post>, info: ResolveInfo) {
    const user = info.context.user
    if (user.isStaff) return qs
    if (user.isAuthenticated) return qs.filter(Q({ published: true }).or(Q({ author: user.pk })))
    return qs.filter({ published: true })
  }
}
```

`ModelTypeMeta` keys (source: `types/modeltype.ts`): `model`, `fields` (default `'__all__'`), `exclude`, `filterFields` (`['title']` = exact only, or `{ field: [lookups] }`), `orderBy` (list or `'__all__'`), `connectionClass`, `permissionClasses`, `convertChoicesToEnum` (default true; or a list of names), plus `name`, `description`, `interfaces`. Override `static getNode(id, info)` to customise `node(id:)` lookups.

Field mapping: pk -> `ID!` (global ID with `Node`), char/text/slug/email/url -> `String`, integer -> `Int`, big integer -> `BigInt`, float/duration -> `Float`, decimal -> `Decimal` (string), date/datetime/time -> `Date`/`DateTime`/`Time`, UUID/JSON/binary -> `UUID`/`JSON`/`Base64`, file/image -> `String` (URL), `choices` -> enum `<Model><Field>`, FK/O2O -> related type, reverse FK / M2M -> `[T!]!` or a connection when the related type implements `Node`. Non-null unless the model field has `null: true`. Relations to models with no ModelType are skipped. Custom ORM field: `registerFieldConverter('MoneyField', () => Decimal)`.

## Scalars, wrappers, plain types

Exports: scalars `String`, `Int`, `Float`, `Boolean`, `ID`, `DateTime`, `DateScalar`, `Time`, `Decimal`, `JSONScalar`, `GenericScalar`, `UUID`, `BigIntScalar`, `Base64`; wrappers `Field`, `List`, `NonNull`, `Argument`, `InputField`; types `ObjectType`, `Query`, `InputObjectType`, `Interface`, `Union`, `Enum`, `Connection`.

```ts
import { Argument, Boolean as GBoolean, Enum, Field, InputObjectType, Int, List, NonNull, ObjectType, String as GString } from '@ghuri/graphql'

export const Status = Enum.from('Status', { DRAFT: 'd', PUBLISHED: 'p' })  // or: class X extends Enum { static values = {...} }

export class StatsType extends ObjectType {
  static fields = {
    total: NonNull(Int),
    tags: List(GString, { nullableItems: true }),
    status: Field(Status),
    top: List(GString, { args: { limit: Argument(Int, { defaultValue: 5 }) }, resolve: (_p, { limit }) => [] }),
    ok: GBoolean,
  }
}
export class PostFilterInput extends InputObjectType { static fields = { title: NonNull(GString) } }
```

`FieldOptions`: `args`, `resolve`, `description`, `deprecationReason`, `defaultValue`, `required`, `source` (parent property to read), `permissionClasses`, `extensions`. Field references can be thunks for cycles.

## Queries

```ts
import { ConnectionField, Field, List, Node, NonNull, Query, type ResolveInfo, String as GString } from '@ghuri/graphql'
import { Post } from './models'
import { AuthorType, PostType, TagType } from './types'

export class BlogQuery extends Query {
  static fields = {
    posts: List(PostType),                                  // root list: Model.objects default + getQueryset
    postBySlug: Field(PostType, {
      args: { slug: NonNull(GString) },
      resolve: (_root: unknown, { slug }: { slug: string }) => Post.objects.filter({ slug }).first(),
    }),
    allPosts: ConnectionField(PostType, { maxLimit: 50 }),  // Relay connection with filter / orderBy
    allTags: ConnectionField(TagType),
    post: Node.Field(PostType),                             // post(id: <global id>)
    node: Node.Field(),                                     // node(id: ID!): Node
    me: Field(AuthorType, {
      resolve: (_r: unknown, _a: unknown, info: ResolveInfo) =>
        info.context.user.isAuthenticated ? info.context.user : null,
    }),
  }
}
```

`info.context` (`GraphQLContext`): `user`, `auth`, `c` (Hono context; undefined outside HTTP), `request` (`PermissionRequest`), `loaders`, `state` (Map). Return QuerySets from **plain (non-async) functions**: a QuerySet is thenable, so `async` resolvers or an `async getQueryset` execute it before Ghuri can scope, paginate or optimize it.

`schema.execute(source, { user, variables, operationName, auth, c, context, rootValue })` runs without HTTP (errors not masked); `schema.printSchema()` returns SDL.

## Relay: global IDs, connections, filter, orderBy

```ts
import { fromGlobalId, toGlobalId } from '@ghuri/graphql'

const gid = toGlobalId('PostType', 42)   // base64("PostType:42") -- type NAME, not model name
const parsed = fromGlobalId(gid)         // { type: 'PostType', id: '42' } or null
```

```graphql
{
  allPosts(
    first: 10, after: "YXJyYXljb25uZWN0aW9uOjk="
    filter: { title: { icontains: "workers" },
              or: [{ published: { exact: true } }, { authorUsername: { exact: "ann" } }] }
    orderBy: ["-createdAt", "title"]
  ) { totalCount pageInfo { hasNextPage endCursor } edges { cursor node { id title } } }
}
```

- `ConnectionFieldOptions`: `filterFields` (or `false`), `orderBy` (or `false`), `resolve` (return a QuerySet or array), `args`, `description`, `deprecationReason`, `maxLimit`, `connectionClass`, `permissionClasses`.
- Pagination: `first`/`after`, `last`/`before`, offset cursors. No `first`/`last` -> page size `RELAY_CONNECTION_MAX_LIMIT`; asking for more is an error. `totalCount` runs `COUNT` only when selected.
- Filter: one nested `filter` input per type; any ORM lookup listed in `filterFields`; combine with `and: [...]`, `or: [...]`, `not: {...}`. ID filters accept raw pks and global IDs.
- orderBy: list of strings, `-` prefix for descending, limited to `Meta.orderBy`; pk is appended for stable pages.
- Reverse FK / M2M to `Node` types are connections too, with that type's filters and ordering.

## Mutations

Root container: a `Mutation` subclass whose `static fields` use `X.field()`.

```ts
import { Boolean as GBoolean, Field, ID, loginRequired, ModelMutation, Mutation, NonNull, type ResolveInfo, SerializerMutation } from '@ghuri/graphql'
import { IsAuthenticated } from '@ghuri/rest'
import { Post } from './models'
import { IsAuthorOrReadOnly } from './permissions'
import { PostSerializer } from './serializers'
import { PostType } from './types'

// Recommended: reuse the REST serializer (validation, create()/update()) and permission classes
export class CreatePost extends SerializerMutation {
  static Meta = {
    serializerClass: PostSerializer,
    modelOperations: ['create'] as const,
    permissionClasses: [IsAuthenticated],
    exclude: ['cover'],
  }
  static async performMutate(serializer: PostSerializer, info: ResolveInfo) {  // like performCreate()
    await serializer.save({ author: info.context.user })
    return { ...(await serializer.getData()), errors: [] }
  }
}

export class UpdatePost extends SerializerMutation {
  static Meta = { serializerClass: PostSerializer, modelOperations: ['update'] as const,
                  permissionClasses: [IsAuthenticated, IsAuthorOrReadOnly] }
}

export class DeletePost extends ModelMutation {   // payload { ok, deletedId, errors, clientMutationId }
  static Meta = { model: Post, operation: 'delete' as const, permissionClasses: [IsAuthenticated, IsAuthorOrReadOnly] }
}

export class PublishPost extends Mutation {        // plain mutation
  static Arguments = { id: NonNull(ID) }
  static fields = { post: Field(PostType), ok: GBoolean }   // payload fields (PublishPostPayload)
  static mutate = loginRequired(async (_root: unknown, { id }: { id: string }, _info: ResolveInfo) => {
    const post = await Post.objects.get({ id })
    post.published = true
    await post.save()
    return { post, ok: true }
  })
}

export class BlogMutation extends Mutation {
  static fields = {
    createPost: CreatePost.field(),
    updatePost: UpdatePost.field(),
    deletePost: DeletePost.field(),
    publishPost: PublishPost.field(),
  }
}
```

- `SerializerMutationMeta`: `serializerClass`, `modelOperations` (`'create' | 'update'`, default both: input with the lookup field -> partial update, without -> create), `lookupField` (default pk), `convertChoicesToEnum` (default false), `fields`, `exclude`, `permissionClasses`, `output`. Hooks: `getSerializerKwargs()`, `performMutate(serializer, info)`, `getQueryset`, `getObject`.
- `ModelMutationMeta`: `model`, `operation` (`'create' | 'update' | 'delete'`), `lookupField`, `fields`, `exclude`, `serializerClass` (optional; otherwise `fullClean()` + `save()`), `returnField` (default model name, e.g. `post`), `type`, `permissionClasses`. Create/update payload `{ post, errors, clientMutationId }`.
- Both are `ClientIDMutation`s: single `input: <Name>Input!` arg with `clientMutationId`; payload type `<Name>Payload`. Validation errors are returned in the payload `errors: [{ field, messages }]`, NOT as GraphQL errors.
- Update/delete lookups go through the type's `getQueryset()`, so users cannot touch rows they cannot see. Permission classes see `request.method` `POST` / `PATCH` / `DELETE` (so `ModelPermissions` checks add/change/delete) and `hasObjectPermission` on the looked-up object.

## Permissions

- Decorators/wrappers: `loginRequired`, `staffMemberRequired`, `superuserRequired`, `permissionRequired('blog.change_post')` (string or array), `userPassesTest((user, info) => bool, { message })`. Anonymous failures -> `extensions.code: "UNAUTHENTICATED"`, others `"PERMISSION_DENIED"`.
- REST permission classes on `Field(T, { permissionClasses })` / `ConnectionField`, on `Mutation.Meta.permissionClasses`, and on `ModelType.Meta.permissionClasses` (lists silently drop objects failing `hasObjectPermission`; single fields raise).
- Errors: `NotAuthenticated`, `GraphQLConfigurationError`, `formatError`, `errorCode`. Unexpected exceptions are masked as `"Internal server error"`; with `DEBUG` the stack is in `extensions.exception`.

## DataLoaders and N+1

FK, reverse FK, O2O and M2M fields resolve through per-request DataLoaders automatically (one batched `__in` query per relation level). Custom batching:

```ts
import { Field, ModelType, type ResolveInfo, String as GString } from '@ghuri/graphql'
import { Profile, Post } from './models'

export class PostType extends ModelType {
  static Meta = { model: Post, fields: ['id', 'title'] }
  static fields = {
    bio: Field(GString, {
      resolve: (post: Post, _a: unknown, info: ResolveInfo) =>
        info.context.loaders
          .get<number, string | null>('bioByAuthor', async (ids) => {
            const rows = await Profile.objects.filter({ user__in: [...ids] })
            const by = new Map(rows.map((p) => [p.userId, p.bio]))
            return ids.map((id) => by.get(id) ?? null)  // same order as keys
          })
          .load(post.authorId),
    }),
  }
}
```

Optimizer: `optimize(qs, info, { only, maxDepth })` in a resolver, or `GRAPHQL.OPTIMIZE` / `new Schema({ optimize: true })`, adds `selectRelated` / `prefetchRelated` from the selection.

## GraphQLView

`GraphQLView.asView({...})` options: `schema`, `graphiql`, `batch`, `authenticationClasses`, `maxDepth`, `maxComplexity`, `introspection`, `validationRules`, `rootValue`, `persistedQueries`, `persistedQueriesOnly`, `getContext(c, context)`, `debug`. They override `GRAPHQL` settings per view. Behaviour: GET (queries only; mutation over GET = 405), POST JSON / `application/graphql` / form. The view is CSRF-exempt but enforces CSRF for session-authenticated POSTs (token/JWT clients just send `Authorization`). GraphiQL served to browsers when `graphiql` / `GRAPHIQL` / `DEBUG` (add `?raw` for JSON). Validation helpers: `depthLimit(n)`, `complexityLimit(n)`.

## Settings: `GRAPHQL`

| Key | Default |
|---|---|
| `SCHEMA` | none (`Schema`, graphql-js schema, or thunk) |
| `GRAPHIQL` | `DEBUG` |
| `MAX_DEPTH` / `MAX_COMPLEXITY` | unlimited |
| `INTROSPECTION` | `true` |
| `RELAY_CONNECTION_MAX_LIMIT` | `100` (also default page size) |
| `BATCH` | `false` |
| `AUTHENTICATION_CLASSES` | none (user from `AuthenticationMiddleware`) |
| `OPTIMIZE` | `false` |

Command: `npx ghuri graphql_schema [-o, --out <file>] [--json] [--sort] [--indent <n>]` prints `GRAPHQL.SCHEMA` as SDL (or introspection JSON). Needs `GraphQLConfig` in `INSTALLED_APPS`.

## Testing

```ts
import { toGlobalId } from '@ghuri/graphql'
import { assertResponseHasErrors, assertResponseNoErrors, graphqlQuery, payloadErrors } from '@ghuri/graphql/testing'
import { APIClient } from '@ghuri/rest/testing'

declare const api: APIClient, token: string

const res = await graphqlQuery(api.client, '{ allPosts(filter: { title: { icontains: "d1" } }) { totalCount } }')
assertResponseNoErrors(res)

const anon = await graphqlQuery(api.client, 'mutation { createPost(input: { title: "x", slug: "x" }) { id } }')
assertResponseHasErrors(anon, { code: 'UNAUTHENTICATED' })

const bad = await graphqlQuery(api.client, 'mutation ($i: CreatePostInput!) { createPost(input: $i) { errors { field messages } } }', {
  variables: { i: { title: '', slug: 'taken' } },
  headers: { Authorization: `Token ${token}` },
})
payloadErrors(bad.data.createPost) // { title: [...], slug: [...] }
toGlobalId('PostType', 1)
```

`graphqlQuery(client, query, { variables, operationName, headers, path, method: 'GET' | 'POST', csrf, accept })` returns `{ response, status, json, data, errors }`; default path `/graphql/` (`graphqlTestDefaults.path`). Works with the core test client and `APIClient.client`; `client.forceLogin(user)` gives session auth with CSRF sent automatically. Or skip HTTP: `await schema.execute(query, { user })`.

## Gotchas

- `String`, `Boolean`, `Int`, `Float`, `ID` imports shadow JS globals: alias them (`String as GString`, `Boolean as GBoolean`) as the blog example does.
- No `graphene.` namespace, no `DjangoObjectType`, no `class Meta:` nesting: `static Meta = {...}` and `static fields = {...}` on the class.
- Resolvers are `(parent, args, info)` static functions; `info.context.user` (not `info.context.request.user`).
- `Meta.fields` names are camelCase model field names (`createdAt`), filter spans use `__` (`author__username`), and the GraphQL filter arg is camelized (`authorUsername`).
- Filters are nested `filter: { field: { lookup: value } }`, never `title_Icontains`. Ordering is `orderBy: ["-createdAt"]`.
- `getQueryset` must be synchronous and return a QuerySet; do not `await` or make it `async`.
- Types are not auto-registered globally: a ModelType reachable only through relations must go in `Schema({ types })`.
- Multiple apps merge via arrays in `new Schema({ query: [A, B] })`, not class inheritance.
- Global IDs encode the GraphQL type name (`PostType`), so `toGlobalId('PostType', pk)` in tests.
- Mutation validation errors are in the payload's `errors` field; check `payloadErrors(...)`, not `res.errors`.
- `GRAPHQL.SCHEMA` takes the schema object, not a dotted path string. Add `GraphQLConfig` to `INSTALLED_APPS` for the command.
- Without `AUTHENTICATION_CLASSES`, only the middleware (session) user is seen; token clients need `TokenAuthentication` / `JWTAuthentication` from `@ghuri/auth/rest`.
- No subscriptions; use `@ghuri/realtime` for push.
