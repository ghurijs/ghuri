# Admin (@ghuri/admin)

How to install the Django-style admin, register models, configure `ModelAdmin` / inlines / actions / list filters, override hooks and build custom admin sites.

## Setup (three steps, no autodiscover)

1. `AdminConfig` in `INSTALLED_APPS` **after** `ContentTypesConfig`, `AuthConfig`, `SessionsConfig` (it throws `ImproperlyConfigured` at startup if `contenttypes` or `auth` is missing). `SessionMiddleware` and `AuthenticationMiddleware` must be in `MIDDLEWARE` (login uses sessions, flash messages live in the session).
2. `path('admin/', admin.site.urls)` in the root URLconf.
3. Each app's `AppConfig` imports its `admin.ts` module (`admin = admin`). Importing the module is what runs the registrations. There is no `autodiscover()`.

```ts
// src/settings.ts
import { AdminConfig } from '@ghuri/admin'
import {
  AuthConfig, AuthenticationMiddleware, ContentTypesConfig, SessionMiddleware, SessionsConfig,
} from '@ghuri/auth'
import { CommonMiddleware, CsrfMiddleware, defineSettings, SecurityMiddleware } from '@ghuri/core'
import { BlogConfig } from './blog/app'

export default defineSettings((env) => ({
  SECRET_KEY: env.SECRET_KEY,
  INSTALLED_APPS: [ContentTypesConfig, AuthConfig, SessionsConfig, AdminConfig, BlogConfig],
  MIDDLEWARE: [SecurityMiddleware, CommonMiddleware, SessionMiddleware, CsrfMiddleware, AuthenticationMiddleware],
}))
```

```ts
// src/urls.ts
import { admin } from '@ghuri/admin'
import { path } from '@ghuri/core'

export const urlpatterns = [path('admin/', admin.site.urls)]
```

```ts
// src/blog/app.ts
import { AppConfig } from '@ghuri/core'
import * as admin from './admin'
import * as migrations from './migrations'
import * as models from './models'

export class BlogConfig extends AppConfig {
  name = 'blog'
  verboseName = 'Blog'
  path = import.meta.dirname
  models = models
  migrations = migrations
  admin = admin // importing ./admin runs admin.site.register / @admin.register
}
```

Then `npx ghuri migrate` (AdminConfig ships the `LogEntry` migration, table `django_admin_log`) and `npx ghuri createsuperuser` (interactive; non-interactive: `GHURI_SUPERUSER_PASSWORD=... npx ghuri createsuperuser --no-input --username admin --email admin@example.com`). Only users with `isStaff` and `isActive` can log in.

## Django -> Ghuri

| Django | Ghuri |
|---|---|
| `from django.contrib import admin` | `import { admin } from '@ghuri/admin'` (namespace object) or named imports (`ModelAdmin`, `TabularInline`, `display`, `action`, ...) |
| `admin.py` found by autodiscover | `admin.ts` imported by `AppConfig` (`admin = admin`) |
| `class PostAdmin(admin.ModelAdmin)` | `class PostAdmin extends ModelAdmin<Post>` |
| `list_display = ('title',)` | `listDisplay = ['title']` (all options camelCase arrays/objects) |
| `@admin.register(Post)` | `@admin.register(Post)` or `register(Post)(PostAdmin)` |
| `@admin.display(description=..., boolean=True)` | `@display({ description: '...', boolean: true })` |
| `admin_order_field` / `short_description` | `display({ ordering: 'field', description: '...' })` |
| `@admin.action(description=...)` | `action({ description, permissions }, fn)` or `@action({...})` on a method |
| `def make_published(modeladmin, request, queryset)` | `async (modelAdmin, c, queryset) => {}` |
| `self.message_user(request, msg, messages.SUCCESS)` | `await this.messageUser(c, msg, 'success')` |
| `request.user` in hooks | `getUser(c)` from `@ghuri/core` |
| `def get_queryset(self, request)` | `getQueryset(c: Context)` (synchronous, returns a QuerySet) |
| `has_change_permission(self, request, obj=None)` | `async hasChangePermission(c, obj?)` |
| `form = MyModelForm` | No ModelForm classes: override `cleanForm`, `getFormFields`, `formfieldForDbField` |
| Template overrides (`change_form.html`) | Not supported (JSX pages). Use options, hooks, `ADMIN_ASSETS.css`, custom views |

## Registering

```ts
// src/blog/admin.ts
import { admin, ModelAdmin } from '@ghuri/admin'
import { Comment, Post, Tag } from './models'

admin.site.register(Tag)                       // default ModelAdmin
admin.site.register([Comment], ModelAdmin)     // several models, one class

@admin.register(Post)
export class PostAdmin extends ModelAdmin<Post> {
  listDisplay = ['title', 'author', 'published', 'createdAt']
}
// Without decorators: class PostAdmin extends ModelAdmin<Post> {...}; admin.register(Post)(PostAdmin)
// or admin.site.register(Post, PostAdmin)
```

`admin.site.unregister(Model)`, `admin.site.isRegistered(Model)`, `admin.site.getModelAdmin(Model)`. Registering twice throws `AlreadyRegistered`; unregistering an unknown model throws `NotRegistered`. Abstract models cannot be registered. `@admin.register(Post, { site: otherSite })` targets another `AdminSite`.

## ModelAdmin options (class fields; defaults from source)

Change list:

| Option | Default | Notes |
|---|---|---|
| `listDisplay` | `['__str__']` | Field names, `'author__username'`, ModelAdmin or model method names, or functions |
| `listDisplayLinks` | first column | `null` = no links |
| `listFilter` | `[]` | Field names, `SimpleListFilter` subclasses, or `['field', FieldListFilterClass]` |
| `listSelectRelated` | `false` | `true` or field names |
| `listPerPage` / `listMaxShowAll` | `100` / `200` | |
| `listEditable` | `[]` | Fields edited inline in the list |
| `searchFields` | `[]` | `'title'` icontains, `'^slug'` istartswith, `'=email'` iexact, `'@body'` (treated as icontains), `'author__username'` |
| `searchHelpText` | `null` | |
| `dateHierarchy` | `null` | A date/datetime field name |
| `ordering` | `null` (model `Meta.ordering`) | `['-createdAt']` |
| `sortableBy` | `null` (all) | |
| `showFullResultCount` | `true` | |
| `emptyValueDisplay` | site's `'-'` | |
| `preserveFilters` | `true` | |
| `actions` | `[]` | Functions, method names, or site action names; `null` disables actions |
| `actionsOnTop` / `actionsOnBottom` / `actionsSelectionCounter` | `true` / `false` / `true` | |

Change form:

| Option | Default | Notes |
|---|---|---|
| `fields` | `null` (all editable) | Nested array = one line: `['title', ['slug', 'status']]` |
| `exclude` | `null` | |
| `fieldsets` | `null` | `[[null, { fields: [...] }], ['Publishing', { fields, classes: ['collapse'], description }]]` |
| `readonlyFields` | `[]` | Field names, method names or functions; `autoNow*` / non-editable fields are always read-only |
| `prepopulatedFields` | `{}` | `{ slug: ['title'] }` |
| `rawIdFields` / `autocompleteFields` | `[]` | FK/M2M widgets; autocomplete needs `searchFields` on the related admin |
| `filterHorizontal` / `filterVertical` | `[]` | M2M filter widget |
| `radioFields` | `{}` | `{ status: HORIZONTAL }` (or `VERTICAL`) |
| `formfieldOverrides` | `{}` | Keyed by `internalType`: `{ TextField: { widget: 'text' } }` |
| `saveAs` / `saveAsContinue` / `saveOnTop` | `false` / `true` / `false` | |
| `viewOnSite` | `true` | Uses `obj.getAbsoluteUrl()`; or `(obj) => url`, or `false` |
| `inlines` | `[]` | Inline **classes** (not instances) |

## Full example (examples/blog/src/blog/admin.ts)

```ts
import { action, admin, display, ModelAdmin, TabularInline } from '@ghuri/admin'
import type { QuerySet } from '@ghuri/orm'
import type { Context } from 'hono'
import { Comment, Post, Tag } from './models'

class CommentInline extends TabularInline<Comment> {
  model = Comment
  extra = 1
  fields = ['name', 'email', 'body', 'approved']
  readonlyFields = ['createdAt']
}

/** Standalone action: give arrow functions an explicit `name` (they have no function name). */
export const makePublished = action(
  { name: 'make_published', description: 'Mark selected %(verbose_name_plural)s as published', permissions: ['change'] },
  async (modelAdmin: ModelAdmin, c: Context, queryset: QuerySet<Post>) => {
    const n = await queryset.update({ published: true })
    await modelAdmin.messageUser(c, `${n} post(s) were published.`, 'success')
  },
)

@admin.register(Post)
export class PostAdmin extends ModelAdmin<Post> {
  listDisplay = ['title', 'author', 'published', 'commentCount', 'createdAt']
  listFilter = ['published', 'tags', 'createdAt']
  searchFields = ['title', 'body', 'author__username']
  prepopulatedFields = { slug: ['title'] }
  readonlyFields = ['createdAt', 'updatedAt']
  filterHorizontal = ['tags']
  dateHierarchy = 'createdAt'
  ordering = ['-createdAt']
  listPerPage = 25
  inlines = [CommentInline]
  actions = [makePublished, 'unpublish']
  fieldsets = [
    [null, { fields: ['title', 'slug', 'body', 'cover'] }],
    ['Publishing', { fields: ['author', 'tags', 'published', 'createdAt', 'updatedAt'] }],
  ]

  @display({ description: 'Comments' })
  async commentCount(post: Post) {
    return Comment.objects.filter({ post: post.pk }).count()
  }

  // Method actions receive (c, queryset) - no modelAdmin argument; `this` is the ModelAdmin.
  @action({ description: 'Unpublish selected posts', permissions: ['change'] })
  async unpublish(c: Context, queryset: QuerySet<Post>) {
    const n = await queryset.update({ published: false })
    await this.messageUser(c, `${n} post(s) were unpublished.`, 'success')
  }
}

@admin.register(Tag)
export class TagAdmin extends ModelAdmin<Tag> {
  listDisplay = ['name', 'slug']
  searchFields = ['name']
  prepopulatedFields = { slug: ['name'] }
}
```

## display() and action()

`display({ description?, ordering?, boolean?, emptyValue? })` for `listDisplay` / `readonlyFields` callables (may be async; may return JSX; values are escaped). `action({ name?, description?, permissions? })`: `description` supports `%(verbose_name_plural)s` / `%(verbose_name)s`; `permissions` entries `'add' | 'change' | 'delete' | 'view'` or a custom `'x'` that requires a `hasXPermission(c)` method on the ModelAdmin (any one passing is enough). Both work as TC39 decorators, legacy decorators, or wrappers:

```ts
import { action, display, ModelAdmin } from '@ghuri/admin'
import { getUser } from '@ghuri/core'
import type { QuerySet } from '@ghuri/orm'
import type { Context } from 'hono'
import { Post } from './models'

export class PostAdmin extends ModelAdmin<Post> {
  listDisplay = ['title', 'isPublished', 'authorName']
  actions = ['archive']

  @display({ description: 'Published?', boolean: true, ordering: 'published' })
  isPublished(obj: Post) { return obj.published }

  // Wrapper form as a class field (no decorators needed)
  authorName = display({ description: 'Author', emptyValue: '(nobody)' }, async (obj: Post) => (await obj.author)?.username)

  @action({ description: 'Archive', permissions: ['publish'] })
  async archive(c: Context, queryset: QuerySet<Post>) {
    await queryset.update({ archived: true })
  }

  async hasPublishPermission(c: Context) {
    return getUser(c).hasPerm('blog.publish_post')
  }
}
```

An action returns nothing (redirect back to the list with flash messages) or a `Response` (CSV download, confirmation page). `deleteSelected` (`'delete_selected'`) is site-wide by default: `admin.site.disableAction('delete_selected')`, `admin.site.addAction(fn, name?)`, `admin.site.getAction(name)`. `messageUser(c, message, level = 'info')`: level `'debug' | 'info' | 'success' | 'warning' | 'error'` or the `DEBUG`/`INFO`/`SUCCESS`/`WARNING`/`ERROR` constants.

## Inlines

`TabularInline<M>` (table rows) and `StackedInline<M>` (full forms) extend `InlineModelAdmin<M>`. Options: `model` (required), `fkName` (only when several FKs to the parent), `extra` (default `3`), `minNum` / `maxNum` (`null`), `canDelete` (`true`), `showChangeLink` (`false`), `verboseName` / `verboseNamePlural`, `classes`, `description`, plus the form options (`fields`, `exclude`, `fieldsets`, `readonlyFields`, `rawIdFields`, `autocompleteFields`, `formfieldOverrides`, ...). Hooks: `getExtra(c, obj)`, `getMinNum(c, obj)`, `getMaxNum(c, obj)`. Formset prefix is the reverse accessor (`commentSet` or the FK's `relatedName`).

## List filters

```ts
import { EmptyFieldListFilter, type ModelAdmin, RelatedOnlyFieldListFilter, SimpleListFilter } from '@ghuri/admin'
import type { QuerySet } from '@ghuri/orm'
import type { Context } from 'hono'

class DecadeFilter extends SimpleListFilter {
  title = 'decade born'
  parameterName = 'decade'
  lookups(c: Context, modelAdmin: ModelAdmin) {
    return [['80s', 'in the eighties'], ['90s', 'in the nineties']] as Array<[string, string]>
  }
  queryset(c: Context, qs: QuerySet<any>) { // synchronous!
    if (this.value() === '80s') return qs.filter({ birthday__gte: '1980-01-01', birthday__lt: '1990-01-01' })
    return qs
  }
}
// listFilter = ['status', DecadeFilter, ['category', RelatedOnlyFieldListFilter], ['summary', EmptyFieldListFilter]]
```

Field filters chosen automatically: `BooleanFieldListFilter`, `ChoicesFieldListFilter`, `RelatedFieldListFilter`, `DateFieldListFilter`, `AllValuesFieldListFilter`. `FieldListFilter.register(test, Cls, takePriority?)` adds one.

## Hooks (override like Django; `c` replaces `request`)

- Permissions (async): `hasViewPermission(c, obj?)`, `hasAddPermission(c, obj?)`, `hasChangePermission(c, obj?)`, `hasDeletePermission(c, obj?)`, `hasModulePermission(c)`. Defaults check `app.view_model` etc. via `getUser(c).hasPerm(...)`; active superusers pass. View-only users get read-only forms.
- Queryset/list: `getQueryset(c)` (sync), `getSearchResults(c, qs, term)` -> `[qs, mayHaveDuplicates]`, `getListDisplay(c)`, `getListDisplayLinks(c, list)`, `getListFilter(c)`, `getSearchFields(c)`, `getSortableBy(c)`, `getListSelectRelated(c)`, `getOrdering(c)`, `lookupAllowed(lookup, value, c)`.
- Forms: `getFields(c, obj)`, `getFieldsets(c, obj)`, `getReadonlyFields(c, obj)`, `getPrepopulatedFields(c, obj)`, `getExclude(c, obj)`, `getAutocompleteFields(c)`, `getInlines(c, obj)`, `getInlineInstances(c, obj)`, `getFormFields(c, obj, names?)`, `formfieldForDbField(c, field)`, `getFieldQueryset(c, field)`, `cleanForm(c, form)`, `getChangeformInitialData(c)`, `getObject(c, id)`.
- Saving: `saveModel(c, obj, form, change)`, `saveRelated(c, form, formsets, change)`, `saveFormset(c, form, formset, change)`, `deleteModel(c, obj)`, `deleteQueryset(c, qs)`.
- Responses/logging: `responseAdd(c, obj, data)`, `responseChange(c, obj, data)`, `responseDelete(c, repr)`, `logAddition`, `logChange`, `logDeletion`, `messageUser(c, msg, level)`.
- Actions/URLs: `getActions(c)`, `getAction(spec)`, `responseAction(c, data, qs)`, `getUrls()`.

```ts
import { ModelAdmin, type ModelForm } from '@ghuri/admin'
import { getUser, path } from '@ghuri/core'
import type { Context } from 'hono'
import { Post } from './models'

export class PostAdmin extends ModelAdmin<Post> {
  getQueryset(c: Context) { // NOT async: QuerySets are thenable, async would resolve it to an array
    const user = getUser(c)
    const qs = super.getQueryset(c)
    return user.isSuperuser ? qs : qs.filter({ author: user.pk })
  }

  async hasDeletePermission(c: Context, obj?: Post | null) {
    return getUser(c).isSuperuser ?? false
  }

  async saveModel(c: Context, obj: Post, form: ModelForm, change: boolean) {
    if (!change) obj.authorId = getUser(c).pk as number
    await super.saveModel(c, obj, form, change)
  }

  cleanForm(c: Context, form: ModelForm) {
    const { title } = form.cleanedData as { title?: string }
    if (title?.startsWith('Draft')) form.addError('title', 'Remove the Draft prefix.')
  }

  getUrls() {
    return [
      path('stats/', this.adminSite.adminView((c) => this.stats(c)), { name: 'blog_post_stats' }),
      ...super.getUrls(),
    ]
  }

  async stats(c: Context) {
    return this.adminSite.renderPage(c, 'Post statistics', `${await Post.objects.count()} posts`)
  }
}
```

`adminSite.adminView(view)` = staff-only + CSRF check + no-cache. URL names live in the site namespace: `reverse('admin:blog_post_change', { object_id: quote(post.pk) })` (`quote` from `@ghuri/admin`); others: `index`, `login`, `logout`, `app_list`, `<app>_<model>_changelist|add|change|delete|history`, `autocomplete`.

## Custom AdminSite and branding

```ts
import { admin, AdminSite, ModelAdmin } from '@ghuri/admin'
import { Post } from '../blog/models'

admin.site.siteHeader = 'Acme administration' // default site, e.g. in AppConfig.ready()

class StaffSite extends AdminSite {
  siteHeader = 'Editorial desk'
  indexTitle = 'Dashboard'
}
export const editorSite = new StaffSite({ name: 'editors' }) // URL namespace 'editors'
editorSite.register(Post, class extends ModelAdmin<Post> { listDisplay = ['title', 'published'] })
// urls.ts: path('editors/', editorSite.urls)
```

`AdminSiteOptions`: `name`, `siteHeader`, `siteTitle`, `indexTitle`, `siteUrl` (`null` hides "View site"), `emptyValueDisplay`, `enableNavSidebar`. Override `hasPermission(c)` (default: active staff), `getUrls()`, `index(c)`, `getAppList(c)`. Setting `ADMIN_ASSETS: { htmx: '/static/htmx.min.js' | false, css: [...], js: [...] }`.

`UserAdmin` / `GroupAdmin` are auto-registered when `auth` is installed (not when `AUTH_USER_MODEL` is swapped). To customise: `admin.site.unregister(User)` then `@admin.register(User) class MyUserAdmin extends UserAdmin {...}`. With a custom user model, register it yourself (subclass `UserAdmin`).

## Gotchas

- **No autodiscover.** If models do not appear, the app's `AppConfig` is missing `admin = admin` (with `import * as admin from './admin'`).
- `AdminConfig` must come after `ContentTypesConfig` and `AuthConfig`; `SessionMiddleware` + `AuthenticationMiddleware` are required.
- Options are camelCase class fields with arrays, not tuples: `listDisplay = ['title']`, never `list_display = ('title',)`. `fieldsets` entries are plain arrays `[null, { fields: [...] }]`.
- `inlines = [CommentInline]` takes classes; inline classes must set `model = Comment`.
- Function actions take `(modelAdmin, c, queryset)`; **method** actions take `(c, queryset)` and are listed by name string (`actions = ['unpublish']`). Arrow-function actions have no name: pass `name` to `action()` or the name becomes a slug of the description.
- No `short_description` / `boolean` attributes on functions: use `display({...})` / `action({...})`.
- `getQueryset(c)` and `SimpleListFilter.queryset(c, qs)` must return the QuerySet synchronously (no `async`).
- Permission hooks are async and take the Hono context; the current user is `getUser(c)`, not `request.user`. `user.hasPerm()` returns a Promise: always `await` it.
- `messageUser` is async: `await this.messageUser(c, msg, 'success')`.
- No ModelForm classes, no `form =`, no template overrides, no "+" related popups.
- **Decorators**: `@admin.register`, `@display`, `@action` work as standard TC39 decorators (what wrangler/esbuild emit) and as legacy `experimentalDecorators`; no tsconfig flag is needed for the Worker build. But **vitest transpiles with oxc, which only lowers legacy decorators**, so `vitest.config.ts` needs `oxc: { decorator: { legacy: true } } as Record<string, unknown>` (see examples/blog/vitest.config.ts). If decorators are unavailable, use the call forms: `admin.register(Post)(PostAdmin)`, `display(opts, fn)`, `action(opts, fn)`.
- In tests, log in as admin with `client.forceLogin(await User.objects.createSuperuser('admin', 'a@example.com', 'pw'))` (test client from `@ghuri/core/testing`; hooks registered by importing `@ghuri/auth`).
