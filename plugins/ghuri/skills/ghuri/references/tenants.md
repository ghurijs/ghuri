# Multi-tenancy (@ghuri/tenants)

Covers shared-schema multi-tenancy: the tenant model, `tenantModel()` / `TenantModel` factories, `objects` vs `unscoped`, the current tenant (`runAsTenant`, `withoutTenant`, `activateTenant`, ...), `TenantMiddleware` and resolvers, the `TENANTS` setting, what is checked on reads and writes, `tenantCache()`, `uuid7()`, GraphQL/REST behaviour, `assertTenantIsolation()` and limits.

Install: `npm install @ghuri/tenants@next` (needs `@ghuri/core` / `@ghuri/orm` 0.1.0-alpha.1+). It is a library, not an app: nothing goes in `INSTALLED_APPS`. Works on D1, SQLite and Postgres (one database, one migration run).

Entry points (from `packages/tenants/package.json`):

| Import | Exports you use |
|---|---|
| `@ghuri/tenants` | `tenantModel`, `TenantModel`, `TenantManager`, `TenantQuerySet`, `isTenantModel`, `tenantFieldOf`, `runAsTenant`, `withoutTenant`, `activateTenant`, `currentTenant`, `requireTenant`, `tenantMode`, `TenantMiddleware`, `HeaderResolver`, `SubdomainResolver`, `HostResolver`, `getTenantModel`, `tenantCache`, `uuid7`, `uuid7Time`, `TenantNotSet`, `CrossTenantError`, `TenantNotFound` |
| `@ghuri/tenants/testing` | `assertTenantIsolation`, `TenantLeakError` |

## Model: rows carry a tenant FK; queries fail closed

Every tenant-scoped row has a foreign key to the tenant. `objects` adds `WHERE <tenant> = <current>` when the QuerySet runs. With **no** tenant active (and not inside `withoutTenant()`), any query or write on a tenant-scoped model throws `TenantNotSet` instead of returning every tenant's rows.

## Django add-on habit -> Ghuri

| Django add-ons | Ghuri |
|---|---|
| django-tenants schema per tenant | does not exist (no schemas on D1/SQLite): shared schema + tenant FK |
| a `tenant` FK + custom manager on every model (django-multitenant) | build models with a `tenantModel()` factory |
| `TenantMainMiddleware` (by domain) | `TenantMiddleware` + `TENANTS.RESOLVERS` |
| `with scope(store=s):` (django-scopes) | `await runAsTenant(s, async () => { ... })` |
| `with scopes_disabled():` | `withoutTenant(() => ...)` or `Model.unscoped` |
| `connection.set_tenant(t)` | `const restore = activateTenant(t)` |
| `ScopeError` | `TenantNotSet` |

## Setup

```ts
// src/stores/models.ts
import { CharField, Model, SlugField } from '@ghuri/orm'
import { tenantModel } from '@ghuri/tenants'

export class Store extends Model({                     // the tenant: an ordinary, unscoped model
  name: new CharField({ maxLength: 100 }),
  slug: new SlugField({ unique: true }),
  domain: new CharField({ maxLength: 200, null: true, blank: true }),
  storefrontToken: new CharField({ maxLength: 64, unique: true }),
}) {}

// One factory per project: a `store` FK and UUIDv7 primary keys on every model built with it.
export const StoreModel = tenantModel({ field: 'store', to: () => Store, uuidPk: true })
```

```ts
// src/catalog/models.ts
import { CharField, SlugField } from '@ghuri/orm'
import { StoreModel } from '../stores/models'

export class Product extends StoreModel({
  title: new CharField({ maxLength: 255 }),
  handle: new SlugField(),
}) {
  static Meta = { uniqueTogether: [['store', 'handle']] }   // start every index/unique with the tenant field
}
```

```ts
// src/settings.ts
import { HeaderResolver, HostResolver, SubdomainResolver, TenantMiddleware } from '@ghuri/tenants'

MIDDLEWARE: [SecurityMiddleware, CommonMiddleware, TenantMiddleware /* , ... */],
TENANTS: {
  MODEL: 'stores.Store',
  RESOLVERS: [
    new HeaderResolver({ header: 'X-Storefront-Token', field: 'storefrontToken' }),
    new SubdomainResolver({ domain: 'myshop.example', exclude: ['www', 'api', 'admin'] }),
    new HostResolver({ field: 'domain' }),
  ],
},
```

Then `npx ghuri makemigrations` + `npx ghuri migrate` as usual (the tenant FK is an ordinary `store_id` column).

```ts
await Product.objects.all()                                       // this request's store only
await Product.objects.create({ title: 'Shirt', handle: 'shirt' }) // `store` filled in
await Product.unscoped.count()                                    // every store: platform code only
```

## `tenantModel(options)`

Gives each model: the tenant FK (`<field>`, NOT NULL, indexed, `onDelete: CASCADE`, column `<field>_id`), `objects` (`TenantManager`, scoped), `unscoped` (plain `Manager`, no checks) and a checking `save()`.

| Option | Default | |
|---|---|---|
| `field` | `'tenant'` | Name of the tenant FK. |
| `to` | `TENANTS.MODEL` | Tenant model or thunk (`() => Store`). |
| `relatedName` | Django default (`productSet`) | Reverse accessor on the tenant; `'+'` hides it. |
| `uuidPk` | `false` | `id: UUIDField({ primaryKey: true, default: uuid7 })`. |

`TenantModel` = ready-made factory with `field: 'tenant'` and `to` from `TENANTS.MODEL`.

## `TENANTS` setting and resolvers

| Key | Default | |
|---|---|---|
| `MODEL` | none | `'app_label.ModelName'` or the class. |
| `RESOLVERS` | `[]` | Tried in order; first tenant wins. |
| `REQUIRED` | `false` | 404 when no resolver finds a tenant (else the request runs with no tenant). Per instance: `new TenantMiddleware({ required: true, resolvers })`. |

| Resolver | Matches | Unknown value |
|---|---|---|
| `HeaderResolver({ header = 'X-Tenant', field = 'pk' })` | a header (storefront token) | 404 |
| `SubdomainResolver({ domain, field = 'slug', exclude })` | `amarshop.myshop.example` -> `slug = 'amarshop'` | 404; other hosts -> `null` |
| `HostResolver({ field = 'domain' })` | whole host (custom domains) | `null` |
| `async (c) => tenant \| null` | anything | your choice (throw `TenantNotFound` for 404) |

All take `filter` (`{ isActive: true }`) and `model`. In views: `currentTenant()`, `requireTenant()` or `c.get('tenant')`.

**A resolver is not authorization.** Check the user belongs to the tenant yourself (a REST `BasePermission` comparing `request.user` with your membership model); no membership permission class ships yet.

## The current tenant outside requests

| Function | |
|---|---|
| `runAsTenant(tenant, fn)` | Run `fn` as `tenant` (queue/cron handlers, commands, tests). Needs a saved tenant. |
| `withoutTenant(fn)` | Scoping off: `objects` sees every tenant, writes unchecked. Platform code only. |
| `activateTenant(tenant)` | Set a fallback tenant (scripts, REPL, tests); returns `restore()`. `activateTenant(null)` clears. |
| `currentTenant()` / `requireTenant()` | Active tenant or `null` / or throw `TenantNotSet`. |
| `tenantMode()` | `'tenant'`, `'bypass'`, `'none'`. |

Innermost wins. Queue consumer:

```ts
onQueue<{ storeId: string }>('inventory', async (batch) => {
  for (const msg of batch.messages) {
    const store = await Store.objects.get({ pk: msg.body.storeId })
    await runAsTenant(store, async () => {
      for await (const p of Product.objects.iterator()) { /* this store only */ }
    })
    msg.ack()
  }
})
```

## What is checked (tenant active)

- Reads (`fetch`, `get`, `count`, `exists`, `aggregate`, `values`, iteration), subqueries, reverse relations, M2M managers and GraphQL: filtered to the tenant.
- `save()` / `create()` / `bulkCreate()`: fill an empty tenant; refuse another tenant's object or an explicit key naming another tenant's row.
- FKs to tenant-scoped models must point to the same tenant (`save`, `create`, `bulkCreate`, `bulkUpdate`, `update`).
- `update(values)`: scoped; cannot change the tenant field or point FKs at another tenant. `bulkUpdate()`: refuses other tenants' objects and tenant changes. `delete()`: scoped; cascades follow same-tenant FKs. M2M `add()`: both sides in the current tenant.
- Refusals throw `CrossTenantError`. FK checks cost one `COUNT` per field per write, cached for the request / `runAsTenant()` block.
- The filter is added at run time, so `queryset = Product.objects.all()` on a viewset (or at module top level) is fine and is scoped per request.

## Cache, keys, GraphQL, REST

- `tenantCache(alias = 'default')`: the cache API with keys prefixed `t:<tenant pk>:`; `clear()` clears only this tenant on memory/KV.
- `uuid7()` / `uuid7Time(id)`: time-ordered UUIDs; with `uuidPk: true` keys stay unique if a tenant later moves to its own database.
- `@ghuri/graphql` reads through the default manager: root fields, connections, relations and `node(id:)` are scoped; another tenant's `node(id:)` is `null`.
- `@ghuri/rest` generic views re-evaluate `queryset.all()` per request, so they are scoped too (not yet covered by the package's tests: add a leak test).

## Testing

```ts
import { activateTenant, runAsTenant } from '@ghuri/tenants'
import { assertTenantIsolation } from '@ghuri/tenants/testing'

it('never leaks between stores', async () => {
  const [a, b] = await makeTwoStoresWithData()
  await assertTenantIsolation({
    tenants: [a, b],
    run: () => listOrdersForDashboard(),   // optional: your code, run as each tenant
    // models: [Order, Product],            // default: every registered tenant-scoped model
  })
})

let restore: () => void
beforeEach(() => { restore = activateTenant(storeA) })
afterEach(() => restore())
```

`assertTenantIsolation` runs `objects.all()` per model and `run` as each tenant, searches results (arrays, objects, Maps, Sets) and throws `TenantLeakError` when another tenant's row appears or a tenant's own rows are missing. Create fixtures with `runAsTenant(store, ...)` or `unscoped` (no tenant active -> `TenantNotSet`).

## Gotchas and limits

- Building a tenant-owned model with plain `Model()` plus a hand-made `ForeignKey(() => Store)`: it is NOT scoped. Use the factory.
- Expecting `objects` to work in platform code with no tenant (signup, staff dashboards, billing cron): it throws `TenantNotSet`. Use `withoutTenant()` or `unscoped` deliberately.
- Not scoped: `unscoped`, `_baseManager`, raw SQL, `getDrizzle()`. A non-tenant FK from a scoped model to the tenant model itself (e.g. `referrerStore`) is not checked.
- `@ghuri/admin` has no tenant integration: on a request with no tenant, admin pages for tenant-scoped models fail with `TenantNotSet`.
- Uniqueness is usually per tenant: `uniqueTogether: [['store', 'handle']]`, not `unique: true` on `handle`.
- Not yet: per-tenant database routing, `dumpdata --tenant`, Postgres row-level security, a REST tenant-membership permission class, schema-per-tenant.
