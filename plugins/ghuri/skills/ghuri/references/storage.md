# File storage (@ghuri/storage)

Covers `STORAGES` / `MEDIA_URL`, the backends (R2, S3, filesystem, memory), the `Storage` API, `FileField` / `ImageField` / `FieldFile`, uploads (views and REST multipart), `serveMedia()`, presigned URLs and validators.

`@ghuri/storage` is a library, not an app: nothing goes in `INSTALLED_APPS`. Importing it adds `STORAGES`, `MEDIA_URL` and `DELETE_FILES_ON_MODEL_DELETE` to the typed settings. App code never touches `env.MEDIA` (the R2 binding) directly; it uses `storages.get()` or a `FileField`.

## Django habit -> Ghuri

| Django | Ghuri |
|---|---|
| `STORAGES = {"default": {"BACKEND": "storages.backends.s3.S3Storage", ...}}` | `STORAGES: { default: s3({...}) }` (factory, not dotted path) |
| `django-storages` S3 / R2 | `r2('MEDIA')` (Workers binding) or `s3({...})` from `@ghuri/storage` |
| `FileSystemStorage` + `MEDIA_ROOT` | `fileSystemStorage({ location, baseUrl })` from `@ghuri/storage/fs` (Node only). No `MEDIA_ROOT` setting |
| `InMemoryStorage` | `memoryStorage()` |
| `default_storage` | `defaultStorage()` (a function) or `storages.get('default')` |
| `storages["private"]` | `storages.get('private')` |
| `upload_to='covers/%Y/'` | `uploadTo: 'covers/%Y/'` (strftime tokens, UTC) |
| `width_field=` / `height_field=` | `widthField:` / `heightField:` |
| `instance.file.url` | `instance.file.url` (getter, sync) |
| `instance.file.size` | `await instance.file.size()` (async method) |
| `if instance.file:` | `if (!instance.file.isEmpty)` (the value is always a `FieldFile`) |
| `request.FILES['f']` | `(await c.req.formData()).get('f')` (a web `File`) |
| `ContentFile(b'...', name='a.txt')` | `new ContentFile(bytes, 'a.txt')` |
| `static(settings.MEDIA_URL, document_root=...)` | `path('media/<path:name>', serveMedia())` or `...mediaPatterns('media/')` |
| `storage.url(name)` with signing (boto3) | `await storage.presignedUrl(name, { expiresIn })` (S3 backend only) |

## Settings

```ts
import { defineSettings } from '@ghuri/core'
import { r2, s3 } from '@ghuri/storage'
import { fileSystemStorage } from '@ghuri/storage/fs'

export default defineSettings((env) => ({
  // ...
  STORAGES: {
    // R2 binding "MEDIA" on Cloudflare; local disk on Node (pattern from examples/blog)
    default: env.MEDIA
      ? r2('MEDIA')
      : fileSystemStorage({ location: env.MEDIA_ROOT ?? '.data/media', baseUrl: '/media/' }),
    private: s3({
      endpoint: env.S3_ENDPOINT,
      bucket: 'private',
      accessKeyId: env.S3_KEY,
      secretAccessKey: env.S3_SECRET,
    }),
  },
  MEDIA_URL: '/media/',               // default '/media/'
  DELETE_FILES_ON_MODEL_DELETE: false, // default false, like Django
}))
```

Each entry is a config `{ backend, create(env) }` (same shape as `CACHES` / `DATABASES` entries) or a `Storage` instance. Configs are instantiated once per `env` and cached. Note: `@ghuri/storage/fs` imports `node:fs`; examples/blog imports it in settings anyway, but only instantiates it when `env.MEDIA` is absent.

## Backends

| Factory | Import | Options | Presigned | Runs on |
|---|---|---|---|---|
| `r2(binding, opts?)` | `@ghuri/storage` | `publicUrl?`, `cacheControl?` | no (`NotSupportedError`) | Workers |
| `s3(opts)` | `@ghuri/storage` | `bucket`, `accessKeyId`, `secretAccessKey` (required); `endpoint?`, `sessionToken?`, `region?`, `publicUrl?`, `forcePathStyle?`, `cacheControl?`, `fetch?` | yes | Workers, Node |
| `fileSystemStorage(opts)` | `@ghuri/storage/fs` | `location` (required), `baseUrl?`, `filePermissions?` (0o644), `directoryPermissions?` (0o755) | no | Node only |
| `memoryStorage(opts?)` | `@ghuri/storage` | `baseUrl?` | no | anywhere (tests) |

- `r2('MEDIA')`: `MEDIA` is the binding name from `wrangler.jsonc` `r2_buckets`. Missing binding raises `ImproperlyConfigured`. `url()` = `publicUrl + name`, else `MEDIA_URL + name`.
- `s3()` speaks R2's S3 API too (`endpoint: https://<account>.r2.cloudflarestorage.com`, region defaults to `auto`); use a second `s3()` storage on the same bucket when you need presigned URLs on Cloudflare.
- `memoryStorage()` returns `{ backend, storage, create }`; `.storage` is the `MemoryStorage` (has `clear()`).
- Classes: `R2Storage`, `S3Storage`, `MemoryStorage` (`@ghuri/storage`), `FileSystemStorage` (`@ghuri/storage/fs`).

## Storage API

```ts
import { defaultStorage, storages } from '@ghuri/storage'

const storage = storages.get('default')          // or defaultStorage(); storages.has('private')
const name = await storage.save('reports/q1.csv', csvString, { contentType: 'text/csv' })
// returns the FINAL name: 'reports/q1_Ab3dE9x.csv' if 'reports/q1.csv' was taken
const file = await storage.open(name)            // StoredFile | null
await file?.text()                               // .bytes() .arrayBuffer() .blob() .body (stream, read once)
await storage.open(name, { range: { offset: 0, length: 1024 } })   // or { suffix: n }
await storage.exists(name)
await storage.size(name)                         // throws FileNotFoundError when missing
await storage.getModifiedTime(name)              // Date | null
await storage.stat(name)                         // { name, size, contentType, etag?, lastModified? } | null
storage.url(name)                                // sync
await storage.listdir('reports')                 // { dirs: string[], files: string[] }
await storage.delete(name)                       // idempotent
```

| Method | Notes |
|---|---|
| `save(name \| null, content, opts?)` | content: `Blob`/`File`/`ArrayBuffer`/typed array/`ReadableStream`/string. `null` name uses the File's name. Options: `contentType`, `maxLength`, `overwrite` (default false), `cacheControl`, `contentDisposition`, `metadata` |
| `presignedUrl(name, opts?)` | `expiresIn` (3600), `method` (`'GET'`/`'PUT'`/`'HEAD'`/`'DELETE'`), `download`, `responseContentType`. S3 only |
| `generateFilename(name)`, `getValidName(name)`, `getAvailableName(name, maxLength?)`, `getAlternativeName(root, ext)` | Django's naming helpers |

Content type on save: explicit `contentType`, else Blob `type`, else guessed from extension, else `application/octet-stream`. Unsafe names (absolute, `..`, NUL) raise `SuspiciousFileOperation` (a core `SuspiciousOperation`, so 400). Errors: `StorageError`, `FileNotFoundError`, `NotSupportedError`, `SuspiciousFileOperation`.

Custom backend: extend `Storage`, implement `_save`, `stat`, `open`, `delete`, `listdir`, `url` (`createStoredFile(info, stream, range)` builds `open()` results); register as `{ backend: 'mine', create: (env) => new MyStorage(...) }`.

## FileField / ImageField

```ts
import { CharField, IntegerField, type Manager, Model } from '@ghuri/orm'
import { FileExtensionValidator, FileField, ImageField } from '@ghuri/storage'

function attachmentPath(instance: Post, filename: string) {
  return `attachments/${instance.slug}/${filename}`
}

export class Post extends Model({
  title: new CharField({ maxLength: 200 }),
  slug: new CharField({ maxLength: 200, unique: true }),
  cover: new ImageField({
    uploadTo: 'covers/%Y/%m/',
    blank: true,
    widthField: 'coverWidth',
    heightField: 'coverHeight',
  }),
  coverWidth: new IntegerField({ null: true, blank: true, editable: false }),
  coverHeight: new IntegerField({ null: true, blank: true, editable: false }),
  attachment: new FileField({
    uploadTo: attachmentPath,           // (instance, filename) => full name
    storage: 'private',                 // STORAGES alias (default 'default'), Storage, config, or () => Storage
    maxLength: 255,                     // varchar length of the stored NAME (default 100)
    accept: '.pdf,application/pdf',     // admin <input accept>
    deleteWithModel: true,              // default: DELETE_FILES_ON_MODEL_DELETE
    validators: [new FileExtensionValidator(['pdf'])],
    blank: true,
  }),
}) {
  declare static objects: Manager<Post>
}
```

- Column stores only the **name** (FileField extends `CharField`; `varchar(100)` default). `dumpdata`/`loaddata` move names, not bytes.
- `uploadTo` strftime tokens (UTC): `%Y %y %m %d %H %M %S %j %s %%`. A string is a directory prefix; a function returns the full name. Functions are recorded in migrations by name (`{ callable: 'attachmentPath' }`), so use named functions.
- `ImageField` validates content by **magic bytes** (PNG, JPEG, GIF, WebP, BMP, AVIF, HEIC) at upload time, raising `ValidationError` before anything is written; it sets `widthField`/`heightField` (AVIF/HEIC dimensions are null).
- Validators: `FileExtensionValidator(['pdf', 'docx'])` (case-insensitive, no dot), `validateImageFileExtension` (an instance, not a function to call). They receive the `FieldFile` during `fullClean()`.

## FieldFile

`post.cover` is always a `FieldFile` (`ImageFieldFile` for ImageField), even when empty.

| Member | |
|---|---|
| `name` | stored name or `null` |
| `url` | getter: `storage.url(name)`; throws when empty |
| `isEmpty`, `committed`, `storage`, `instance`, `field` | |
| `await size()`, `await exists()`, `await open(opts?)` | `open` throws `FileNotFoundError` |
| `await presignedUrl(opts?)` | S3 storages only |
| `await save(name, content, { save = true, contentType? })` | applies `uploadTo`, uploads, then saves the model unless `save: false` |
| `await delete({ save = true })` | deletes stored file, clears field (and dimensions), saves model |
| `toJSON()` / `String(file)` | the stored **name**, not the URL |
| `width`, `height`, `await dimensions()` | ImageFieldFile only |

```ts
import { ContentFile, upload } from '@ghuri/storage'
import { Post } from './models'

const post = await Post.objects.get({ slug: 'hello' })
post.cover = upload(file)                  // web File; upload(bytes, 'cover.png') for unnamed content
await post.save()                          // uploads pending files FIRST, then UPDATE
post.cover = 'covers/existing.png'         // point at an already-stored name
post.cover = null                          // clear (stored file is kept)
await post.cover.save('cover.png', new ContentFile(bytes))   // Django style; also saves the model
await post.attachment.save('a.pdf', blob, { save: false })    // upload only (before bulk ops)
```

`upload()` exists because attributes are typed `FieldFile`; assigning a `File` directly also works at runtime. Names are reduced to their base name and cleaned (`My Cat?.JPG` -> `My_Cat.JPG`); collisions get `_<7 random chars>`.

## Uploads

From a plain view (Hono context):

```ts
import { BadRequest, json } from '@ghuri/core'
import { getObjectOr404 } from '@ghuri/orm'
import { upload } from '@ghuri/storage'
import type { Context } from 'hono'
import { Post } from './models'

export async function uploadCover(c: Context) {
  const post = await getObjectOr404(Post.objects.all(), { slug: c.req.param('slug') })
  const file = (await c.req.formData()).get('cover')
  if (!(file instanceof File)) throw new BadRequest('Send the image in a "cover" field.')
  post.cover = upload(file)
  await post.save()
  return json(c, { url: post.cover.url, width: post.coverWidth })
}
```

Through REST: a `ModelSerializer` maps model `FileField`/`ImageField` to `@ghuri/rest` `FileField`/`ImageField`. `MultiPartParser` is in `DEFAULT_PARSER_CLASSES` by default. Input is a `File`; output is the file URL (absolute when a request is available) while `UPLOADED_FILES_USE_URL` (REST_FRAMEWORK, default true) or the field's `useUrl` is on. Just list the field in `Meta.fields` (examples/blog `PostSerializer` lists `'cover', 'coverWidth', 'coverHeight'`).

Test (examples/blog/src/blog/tests.ts):

```ts
import { memoryStorage } from '@ghuri/storage'
import { APIClient } from '@ghuri/rest/testing'

ctx.settings.STORAGES = { default: memoryStorage() }   // in beforeAll, after app.setup(env)
const file = new File([PNG], 'cover.png', { type: 'image/png' })
const res = await api.patch('/api/posts/pic/', { cover: file }, { format: 'multipart' })
expect(res.data.cover).toMatch(/covers\/\d{4}\/\d{2}\/cover.*\.png$/)
expect(res.data.coverWidth).toBe(1)
```

## Serving media

```ts
import { path } from '@ghuri/core'
import { mediaPatterns, serveMedia } from '@ghuri/storage'

export const urlpatterns = [
  path('media/<path:name>', serveMedia(), { name: 'media' }),
  // or: ...mediaPatterns('media/'),
  path('private-media/<path:name>', serveMedia({ storage: 'private', cacheControl: 'private, max-age=60' })),
]
```

`ServeMediaOptions`: `storage` (alias/Storage/config, default `'default'`), `param` (default `'name'`), `cacheControl` (default `'public, max-age=3600'`), `download` (attachment disposition). Handles ETag/Last-Modified (304), single Range (206/416), HEAD, 405 for other methods, `nosniff`, and a sandbox CSP for HTML/SVG/XML uploads. For public R2 media in production, prefer `r2('MEDIA', { publicUrl: 'https://media.example.com' })` so the Worker never sees file requests. For private files, wrap your own view with a permission check, or hand out `presignedUrl()` links (S3 storage).

Presigned direct uploads: `await storage.presignedUrl(`uploads/${crypto.randomUUID()}.jpg`, { method: 'PUT', expiresIn: 600 })`, then assign the key: `post.attachment = key`. Use this for files above the Workers request-body limit.

## Gotchas

- Do not read `env.MEDIA` / call `env.MEDIA.put()` in app code. Use `storages.get()` / `defaultStorage()` / a `FileField`.
- `defaultStorage` is a function: `defaultStorage().save(...)`, not `defaultStorage.save(...)`.
- `storage.save()` may return a different name than requested; always store the returned name.
- `file.size()`, `file.exists()`, `file.open()`, `storage.exists()` are async. `file.url` and `storage.url()` are sync.
- An empty field is not `null`: check `post.cover.isEmpty`, not `if (post.cover)`.
- `model.toJSON()` / `String(file)` gives the stored name; use `.url` for clients (REST serializers already output the URL).
- `bulkCreate()` and `qs.update()` cannot upload pending files; call `file.save(name, content, { save: false })` first.
- Deleting a row keeps its files unless `DELETE_FILES_ON_MODEL_DELETE: true` or `deleteWithModel: true`. Replacing a file never deletes the old one.
- `r2()` has no presigned URLs; `presignedUrl()` throws `NotSupportedError`. Use `s3()` against R2's S3 endpoint.
- `fileSystemStorage` (`@ghuri/storage/fs`) is Node only: never select it on Workers (guard on `env.MEDIA` as above).
- There is no `MEDIA_ROOT` setting; pass `location` to `fileSystemStorage`.
- Option names are camelCase: `uploadTo`, `widthField`, `heightField`, `maxLength`, `deleteWithModel`.
- The REST `ImageField` checks the client MIME type/extension; the model `ImageField` re-checks real bytes on save.
- `uploadTo` strftime is UTC, and the default stored-name column is only 100 chars; raise `maxLength` for deep paths.
- `ContentFile` is a web `File` subclass: `new ContentFile(content, name)` (name second, default `'content'`).
