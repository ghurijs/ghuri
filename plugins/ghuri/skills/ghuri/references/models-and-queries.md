# Models and queries

Defining models (`@ghuri/orm`), fields, relations, managers, the async QuerySet API, lookups, Q/F/aggregates, transactions and raw SQL.

## Defining a model

```ts
// src/blog/models.ts
import { User } from '@ghuri/auth'
import {
  BooleanField, CASCADE, CharField, DateTimeField, ForeignKey, type Manager, ManyToManyField,
  Model, type RelatedManager, SlugField, TextField,
} from '@ghuri/orm'

export class Tag extends Model({
  name: new CharField({ maxLength: 50, unique: true }),
  slug: new SlugField({ maxLength: 50, unique: true }),
}) {
  declare static objects: Manager<Tag>
  static Meta = { ordering: ['name'] }
  toString() { return this.name }
}

export class Post extends Model({
  title: new CharField({ maxLength: 200 }),
  slug: new SlugField({ maxLength: 200, unique: true }),
  body: new TextField({ blank: true }),
  author: new ForeignKey(() => User, { onDelete: CASCADE, relatedName: 'posts' }),
  tags: new ManyToManyField(() => Tag, { blank: true, relatedName: 'posts' }),
  published: new BooleanField({ default: false }),
  createdAt: new DateTimeField({ autoNowAdd: true }),
  updatedAt: new DateTimeField({ autoNow: true }),
}) {
  declare static objects: Manager<Post>      // types Post.objects.get() as Post
  declare comments: RelatedManager<Comment>  // reverse FK from Comment.post (runtime-created)
  static Meta = {
    ordering: ['-createdAt'],
    indexes: [{ fields: ['published', '-createdAt'], name: 'blog_post_pub_created_idx' }],
  }
  toString() { return this.title }            // Django's __str__
  get isDraft() { return !this.published }    // @property -> getter
}

export class Comment extends Model({
  post: new ForeignKey(() => Post, { onDelete: CASCADE, relatedName: 'comments' }),
  body: new TextField(),
}) {
  declare static objects: Manager<Comment>
}
```

- Fields are passed as an object to `Model({...})`; you `extends` the returned class. Never declare fields as class properties.
- `static Meta = {...}` replaces `class Meta:`. Use `declare` (never an initializer) for typing-only members (`objects`, reverse managers).
- Implicit `id: new BigAutoField({ primaryKey: true })` unless a field sets `primaryKey: true`. `instance.pk` aliases the primary key.
- Property names are camelCase; columns are snake_case automatically (`createdAt` -> `created_at`, FK `author` -> `author_id`, attribute `authorId`). Table: `<appLabel>_<modelname>` (`blog_post`).
- The model gets its app label from the `AppConfig` that lists it (`models = models` in `app.ts`). Outside INSTALLED_APPS (scripts) use `Meta.appLabel` or `registerModels('blog', models)`.
- After any model change: `npx ghuri makemigrations` then `npx ghuri migrate`.

## Fields (all from `@ghuri/orm`; `FileField`/`ImageField` from `@ghuri/storage`)

| Field | TS value | Notes |
|---|---|---|
| `AutoField`, `BigAutoField`, `SmallAutoField` | `number` | auto PKs |
| `CharField` | `string` | `maxLength` (default 255). SQLite/D1 do not enforce length; validation does |
| `TextField`, `SlugField` (default maxLength 50, indexed, `allowUnicode`), `EmailField`, `URLField` | `string` | |
| `UUIDField` | `string` | `default: () => crypto.randomUUID()` |
| `GenericIPAddressField` | `string` | `protocol`, `unpackIpv4` |
| `IntegerField`, `BigIntegerField`, `SmallIntegerField`, `PositiveIntegerField`, `PositiveBigIntegerField`, `PositiveSmallIntegerField`, `FloatField` | `number` | |
| `DecimalField` | `string` (`'19.99'`) | `maxDigits`, `decimalPlaces`; never a float |
| `BooleanField`, `NullBooleanField` | `boolean` | |
| `DateField` | `string` `'YYYY-MM-DD'` | `autoNow`, `autoNowAdd` |
| `DateTimeField` | `Date` | `autoNow`, `autoNowAdd` (stored UTC) |
| `TimeField` | `string` `'HH:MM:SS'` | |
| `DurationField` | `number` (milliseconds) | not a timedelta |
| `JSONField` | `any` or generic | `new JSONField<{ theme: string }>({ default: () => ({ theme: 'light' }) })` |
| `BinaryField` | `Uint8Array` | |
| `ForeignKey(to, { onDelete, ... })`, `OneToOneField`, `ManyToManyField(to, {...})` | see Relations | |

Common options (every field): `null`, `blank`, `default` (value or function), `dbDefault`, `choices` (`[value, label][]` or enum-like object), `primaryKey`, `unique`, `dbIndex`, `dbColumn`, `dbComment`, `editable`, `helpText`, `verboseName`, `validators`, `errorMessages`, `serialize`. A field with `null: true` is typed `T | null`. For text prefer `blank: true, default: ''` over `null: true`.

Validators (from `@ghuri/orm`): `MinValueValidator`, `MaxValueValidator`, `MinLengthValidator`, `MaxLengthValidator`, `RegexValidator`, `EmailValidator`, `URLValidator`, `DecimalValidator`, `validateSlug`, `validateEmail`, `validateURL`, `validateIPv4Address`. Custom validator: a function that throws `ValidationError` (from `@ghuri/core`).

```ts
import { IntegerField, MaxValueValidator, MinValueValidator } from '@ghuri/orm'
const rating = new IntegerField({ validators: [new MinValueValidator(1), new MaxValueValidator(5)] })
```

## Meta options

`dbTable`, `ordering`, `verboseName`, `verboseNamePlural`, `uniqueTogether` (`[['author', 'slug']]`), `indexes` (`{ fields, name?, unique?, condition? }`, `-field` = descending), `constraints` (`{ type: 'unique', fields, name, condition? }` or `{ type: 'check', check: 'views >= 0', name }`), `abstract`, `permissions` (`[['publish_post', 'Can publish posts']]`), `defaultPermissions`, `getLatestBy`, `appLabel`, `managed`, `defaultManagerName`.

Abstract base model (no multi-table inheritance, no proxy models):

```ts
import { CharField, DateTimeField, Model } from '@ghuri/orm'

export class Timestamped extends Model({
  createdAt: new DateTimeField({ autoNowAdd: true }),
  updatedAt: new DateTimeField({ autoNow: true }),
}) {
  static Meta = { abstract: true }
}

export class Page extends Model({ title: new CharField({ maxLength: 200 }) }, { extends: Timestamped }) {}
```

## Relations

```ts
import { CASCADE, ForeignKey, ManyToManyField, OneToOneField, SET_NULL } from '@ghuri/orm'

const fields = {
  author: new ForeignKey(() => User, { onDelete: CASCADE, relatedName: 'posts' }),
  editor: new ForeignKey('auth.User', { onDelete: SET_NULL, null: true, blank: true, relatedName: '+' }),
  parent: new ForeignKey('self', { onDelete: CASCADE, null: true }),
  profile: new OneToOneField(() => User, { onDelete: CASCADE, relatedName: 'profile' }),
  tags: new ManyToManyField(() => Tag, { blank: true, relatedName: 'posts' }),
}
```

- Target: a class, `() => Class` (preferred: no import-order problems), `'app.Model'`, `'Model'` (same app) or `'self'`.
- Options: `onDelete` (required on FK/O2O), `relatedName` (`'+'` hides it), `relatedQueryName`, `toField`, `limitChoicesTo`, `dbConstraint`; M2M: `through`, `throughFields`, `dbTable`.
- `onDelete` constants: `CASCADE`, `PROTECT` (throws `ProtectedError`), `RESTRICT` (`RestrictedError`), `SET_NULL`, `SET_DEFAULT`, `SET(value | () => value)`, `DO_NOTHING`. Enforced by the ORM (same on D1/SQLite/Postgres), not by the DB.
- Default reverse accessor is camelCase `<model>Set` (`user.postSet`), lookup name `<model>` (`post`).

Using them:

```ts
post.authorId                         // raw FK value, no query
const author = await post.author      // FK access is awaitable (cached after first load)
post.author = user                    // sets authorId; never assign an un-awaited relation
await user.posts.filter({ published: true }).count()   // reverse related manager
await user.posts.create({ title: 'New', slug: 'new' })   // sets author automatically
await post.tags.add(tag1, tag2)       // instances or pks; also remove(), set([...]), clear(), all()
await club.members.add(alice, { throughDefaults: { role: 'chair' } })   // through model extras
const profile = await user.profile    // reverse one-to-one: single object or throws Profile.DoesNotExist
```

`post.tags = [...]` is not allowed; use `post.tags.set([...])`. The instance must be saved before changing M2M.

## Managers

```ts
import { Manager } from '@ghuri/orm'

class PublishedManager extends Manager<Post> {
  getQueryset() { return super.getQueryset().filter({ published: true }) }
  byTag(slug: string) { return this.getQueryset().filter({ tags__slug: slug }) }
}

export class Post extends Model({ /* fields */ }) {
  declare static objects: Manager<Post>
  static published = new PublishedManager()   // `objects = PublishedManager()` in Django
}
await Post.published.byTag('news').count()
```

`objects` always exists; replace it with `static objects = new PostManager()`. The default manager for related lookups is `objects` unless `Meta.defaultManagerName` is set.

## Instances: save, delete, validate

```ts
import { ValidationError } from '@ghuri/core'

const post = new Post({ title: 'Hi', slug: 'hi', authorId: user.pk })
await post.save()                                  // INSERT
post.title = 'Hello'
await post.save({ updateFields: ['title'] })       // also forceInsert, forceUpdate, using
await post.refreshFromDb({ fields: ['title'] })
const [total, perModel] = await post.delete()      // [14, { 'blog.Post': 1, 'blog.Comment': 13 }]

try {
  await post.fullClean()      // save() does NOT validate; fullClean({ exclude, validateUnique })
} catch (e) {
  if (e instanceof ValidationError) console.log(e.messageDict)
}
```

Override `clean()` (throw `new ValidationError({ body: ['...'] })`) for cross-field rules. Override `async save(opts)` and call `await super.save(opts)`. `toJSON()` gives concrete field values (FKs as `...Id`). DB errors: `IntegrityError`, `NotSupportedError`, `DatabaseError`, `FieldError`, `ProtectedError`, `RestrictedError` (all `@ghuri/orm`). `Post.DoesNotExist` / `Post.MultipleObjectsReturned` extend `ObjectDoesNotExist` / `MultipleObjectsReturned` from `@ghuri/core`.

## QuerySet API (everything that hits the DB is `await`ed)

QuerySets are lazy, immutable and thenable: `await qs` runs it and returns `T[]`.

```ts
import { getObjectOr404 } from '@ghuri/orm'

const posts = await Post.objects.filter({ published: true }).exclude({ title__startswith: 'Draft' }).orderBy('-createdAt')
const page = await Post.objects.all().slice(20, 30)          // OFFSET 20 LIMIT 10 (no negative indexes); .limit(n)
const one = await Post.objects.get({ slug: 'hello' })        // throws Post.DoesNotExist / MultipleObjectsReturned
const first = await Post.objects.filter({ published: true }).first()   // Post | null; also last()
const latest = await Post.objects.latest('createdAt')        // also earliest()
const n = await Post.objects.count()
const exists = await Post.objects.filter({ slug: 'x' }).exists()
const post = await getObjectOr404(Post, { slug: 'hello' })   // throws Http404; accepts model, manager or QuerySet
for await (const p of Post.objects.filter({ published: true })) { /* ... */ }
for await (const p of Post.objects.filter({ published: true }).iterator(500)) { /* chunked */ }
```

| Django | Ghuri |
|---|---|
| `filter(a=1, b__gt=2)` | `filter({ a: 1, b__gt: 2 })` |
| `order_by('-x')`, `qs[:10]`, `qs[10:20]` | `orderBy('-x')`, `slice(0, 10)`, `slice(10, 20)` |
| `select_related`, `prefetch_related` | `selectRelated('author')`, `prefetchRelated('tags', 'comments')` |
| `values('id')`, `values_list('id', flat=True)` | `values('id')`, `valuesList('id', { flat: true })` |
| `get_or_create(slug=s, defaults={...})` | `getOrCreate({ slug: s }, { defaults: {...} })` -> `[obj, created]` |
| `update_or_create(...)` | `updateOrCreate(lookup, { defaults, createDefaults })` -> `[obj, created]` |
| `bulk_create(objs, batch_size=500)` | `bulkCreate(objs, { batchSize: 500, ignoreConflicts: true })` |
| `bulk_update(objs, ['f'])` | `bulkUpdate(objs, ['f'], { batchSize })` -> number |
| `in_bulk([1, 2])` (dict) | `inBulk([1, 2])` / `inBulk(slugs, { fieldName: 'slug' })` -> `Map` |
| `qs.update(x=1)` | `await qs.update({ x: 1 })` -> number of rows (no signals, no save()) |
| `qs.delete()` | `const [total, perModel] = await qs.delete()` |
| `Post.objects.all().delete()` | same: the Manager has no `delete()` |
| `distinct('field')` | not supported (`distinct()` only) |
| `only`, `defer`, `none`, `using('alias')`, `reverse()` | same names |
| `str(qs.query)` | `qs.toSQL()` -> `{ sql, params }` |

Pitfall: QuerySets are thenable, so `return qs` from an `async` function resolves it to an array. Return it from a plain function (e.g. `getQueryset()`) to keep it a QuerySet.

## Lookups

`field__lookup` keys; no lookup means `exact`. Lookups: `exact`, `iexact`, `contains`, `icontains`, `in`, `gt`, `gte`, `lt`, `lte`, `startswith`, `istartswith`, `endswith`, `iendswith`, `range` (inclusive), `isnull`, `regex`, `iregex` (regex not available on D1: `NotSupportedError`). Transforms: `date`, `time`, `year`, `month`, `day`, `hour`, `minute`, `second`, `week_day`, `quarter` (chainable: `createdAt__year__gte: 2025`). `contains`/`startswith`/`endswith` are case-sensitive on every backend.

```ts
await Post.objects.filter({ author__username: 'rifat' })          // forward FK (join)
await User.objects.filter({ posts__published: true })             // reverse FK via relatedName (EXISTS subquery)
await Post.objects.filter({ tags__slug__in: ['news', 'edge'] })    // M2M
await Post.objects.filter({ author: user })                       // instance, pk, or authorId: 1
await Post.objects.filter({ author__in: User.objects.filter({ isStaff: true }) })   // subquery
```

Multi-valued spans compile to `EXISTS (...)`, so rows are not duplicated and `distinct()` is rarely needed. Conditions in one `filter()` apply to the same related object; chained `filter()` calls may match different ones (as in Django).

## Q, F, expressions, aggregates

```ts
import { Avg, Coalesce, Concat, Count, F, Lower, Max, Prefetch, Q, Sum, Value } from '@ghuri/orm'

await Post.objects.filter(Q({ title__icontains: 'd1' }).or(Q({ body__icontains: 'd1' })))   // Q(a) | Q(b)
await Post.objects.filter(Q({ published: true }).and(Q.not({ author__username: 'bot' })))   // & ~Q()
await Post.objects.filter(Q.or(Q({ a: 1 }), Q({ b: 2 })), { published: true })              // Q plus plain object
await Post.objects.filter({ slug }).update({ views: F('views').add(1) })   // add/sub/mul/div/mod
await Post.objects.filter({ updatedAt__gt: F('createdAt') })
await Post.objects.orderBy(F('rating').desc({ nullsLast: true }))
await Tag.objects.orderBy(Lower('name'))
await User.objects.annotate({ fullName: Concat('firstName', Value(' '), 'lastName') })

const stats = await Post.objects.aggregate({ total: Count('id'), avgViews: Avg('views'), top: Max('views') })
// aggregates are always named: { total, avgViews, top }
const busy = await Post.objects
  .annotate({ numComments: Count('comments'), approved: Count('comments', { filter: Q({ comments__approved: true }) }) })
  .filter({ numComments__gt: 2 })
  .orderBy('-numComments')
await Post.objects.values('author__username').annotate({ posts: Count('id') })   // GROUP BY
await Post.objects.prefetchRelated(
  new Prefetch('comments', { queryset: Comment.objects.filter({ approved: true }), toAttr: 'approvedComments' }),
)
```

Other expressions: `Sum`, `Min`, `Upper`, `Length`, `Coalesce`, `Now`, `new Func('ROUND', ['price'])`, `new RawSQL('...?', [params])`. String args are field references; wrap literals in `Value()`.

## Transactions

```ts
import { atomic, connections, onCommit } from '@ghuri/orm'

await atomic(async () => {
  const order = await Order.objects.create({ customer: user, total: '49.00' })
  await onCommit(() => sendReceipt(order))   // runs after the outermost block commits
})
await atomic(fn, { using: 'pg' })           // nested atomic() = savepoint (not on D1)

// D1: atomic() does NOT roll back. For all-or-nothing writes on D1 use a batch of raw statements:
const conn = await connections.get()
await conn.batch?.([
  { sql: 'UPDATE shop_product SET stock = stock - ? WHERE id = ?', params: [1, productId] },
  { sql: 'INSERT INTO shop_orderline (order_id, product_id) VALUES (?, ?)', params: [orderId, productId] },
])
```

On D1 prefer single statements (`qs.update()` with `F()`, `bulkCreate()`), batches, and idempotent multi-step code. Cascading deletes, `getOrCreate()` and `updateOrCreate()` also use `atomic()` internally, so they are not atomic on D1.

## Raw SQL and the Drizzle escape hatch

```ts
import { connections, getDrizzle } from '@ghuri/orm'
import { sql } from '@ghuri/orm/migrations'

const conn = await connections.get()            // 'default'; connections.get('pg') for another alias
const { rows } = await conn.execute('SELECT author_id, COUNT(*) AS n FROM blog_post GROUP BY author_id', [])
const q = sql`SELECT id FROM blog_post WHERE created_at > ${cutoff}`
const rendered = q.render(conn.dialect)         // '?' on sqlite/D1, '$1' on postgresql
await conn.execute(rendered.sql, rendered.params)
const db = await getDrizzle()                   // Drizzle with Post.table() for queries the ORM can't express
```

`conn.execute()` passes SQL unchanged: `?` placeholders on D1/SQLite, `$1` on Postgres. Never use `env.DB.prepare(...)` in app code. Counting queries: `const [result, queries] = await captureQueries(() => fn())` and `onQuery((e) => ...)` from `@ghuri/orm`.

## Gotchas (what a Django/Prisma-trained model gets wrong)

- Writing `class Post(models.Model)`, `models.CharField(max_length=...)`, `class Meta:` - use `Model({...})`, `new CharField({ maxLength })`, `static Meta = {}`.
- Declaring fields as class properties (`title = new CharField()` inside the class body) - fields go in the `Model({...})` argument. (Class-body fields are for serializers, not models.)
- snake_case anything: `auto_now_add`, `related_name`, `on_delete=models.CASCADE`, `order_by`, `select_related`, `post_set`, `author_id`. All camelCase: `autoNowAdd`, `relatedName`, `onDelete: CASCADE` (imported constant), `orderBy`, `selectRelated`, `postSet`, `authorId`.
- Forgetting `await` on QuerySets, `get()`, `save()`, `count()`, `post.author` (FK access is a promise), related managers.
- Using keyword-style arguments: lookups are one object, `filter({ title__icontains: 'x' })`; `Q(a=1) | Q(b=2)` is `Q({ a: 1 }).or(Q({ b: 2 }))`; `~Q(...)` is `Q.not({...})`.
- Expecting `inBulk()` to return an object (it's a `Map`) or `delete()` to return a tuple of different shape (`[total, perModel]`).
- `aggregate(Avg('views'))` without a name - always `aggregate({ avg: Avg('views') })`.
- Using Prisma (`prisma.post.findMany`) or raw Drizzle/D1 (`env.DB.prepare`) instead of the ORM.
- `DecimalField` values are strings; `DurationField` is milliseconds; `DateField` is a `'YYYY-MM-DD'` string; only `DateTimeField` is a `Date`.
- Expecting `atomic()` to roll back on D1. It doesn't.
- Assuming reverse relations are typed: add `declare comments: RelatedManager<Comment>` (and `declare static objects: Manager<Post>`) for TypeScript.
- Changing a model without running `npx ghuri makemigrations`. Multi-table inheritance, proxy models, generic relations, `distinct('field')` and negative slicing do not exist.
