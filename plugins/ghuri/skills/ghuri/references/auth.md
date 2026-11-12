# Auth (@ghuri/auth, @ghuri/auth/rest)

Users, groups, permissions, sessions, login/logout, view protection, password hashing/validation, custom user models, API tokens, JWT, signing and the auth settings.

## Apps and middleware

| App config (from `@ghuri/auth`) | Label | Models (Django table names) | Commands |
|---|---|---|---|
| `ContentTypesConfig` | `contenttypes` | `ContentType` (`django_content_type`) | |
| `AuthConfig` | `auth` | `User` (`auth_user`, absent when swapped), `Group`, `Permission` | `createsuperuser`, `changepassword` |
| `SessionsConfig` | `sessions` | `Session` (`django_session`), for `SESSION_ENGINE: 'db'` | `clearsessions` |
| `AuthTokenConfig` | `authtoken` | `Token` (`authtoken_token`) | `drf_create_token <username> [--reset]` |
| `TokenBlacklistConfig` | `token_blacklist` | `OutstandingToken`, `BlacklistedToken` | `flushexpiredtokens` |

`authApps` = `[ContentTypesConfig, AuthConfig, SessionsConfig]` (spreadable). `ContentTypesConfig` must precede `AuthConfig` (else `ImproperlyConfigured`). All apps ship migrations; `migrate` then creates the default `add_/change_/delete_/view_<model>` permissions (postMigrate signal).

Middleware: `SessionMiddleware` (loads `c.get('session')` from the `sessionid` cookie) must come **before** `AuthenticationMiddleware` (sets the request user). Also exported: `RemoteUserMiddleware`, `PersistentRemoteUserMiddleware`.

```ts
// src/settings.ts (as in examples/blog)
import { AdminConfig } from '@ghuri/admin'
import {
  AuthConfig, AuthenticationMiddleware, AuthTokenConfig, ContentTypesConfig, SessionMiddleware, SessionsConfig,
} from '@ghuri/auth'
import { JWTAuthentication, SessionAuthentication, TokenAuthentication } from '@ghuri/auth/rest'
import {
  CommonMiddleware, CsrfMiddleware, defineSettings, SecurityMiddleware, XFrameOptionsMiddleware,
} from '@ghuri/core'
import { BlogConfig } from './blog/app'

export default defineSettings((env) => ({
  SECRET_KEY: env.SECRET_KEY,
  INSTALLED_APPS: [ContentTypesConfig, AuthConfig, SessionsConfig, AuthTokenConfig, AdminConfig, BlogConfig],
  MIDDLEWARE: [
    SecurityMiddleware, CommonMiddleware, SessionMiddleware, CsrfMiddleware, AuthenticationMiddleware,
    XFrameOptionsMiddleware,
  ],
  AUTH_USER_MODEL: 'auth.User',
  REST_FRAMEWORK: {
    DEFAULT_AUTHENTICATION_CLASSES: [TokenAuthentication, JWTAuthentication, SessionAuthentication],
  },
  JWT: { ACCESS_TOKEN_LIFETIME: 15 * 60, REFRESH_TOKEN_LIFETIME: 7 * 24 * 60 * 60 },
}))
```

## Django -> Ghuri

| Django | Ghuri |
|---|---|
| `from django.contrib.auth.models import User` | `import { User } from '@ghuri/auth'` |
| `get_user_model()` | `getUserModel()` |
| `request.user` | `getUser(c)` (from `@ghuri/core`, re-exported by `@ghuri/auth`) or `c.get('user')` |
| `request.session['k'] = v` | `await c.get('session').set('k', v)` / `getSession(c)` |
| `User.objects.create_user(...)` | `await User.objects.createUser('ann', 'ann@x.com', 'pw')` or `createUser({ username, email, password })` |
| `user.set_password(pw)` / `check_password(pw)` | `await user.setPassword(pw)` / `await user.checkPassword(pw)` |
| `user.has_perm('blog.change_post')` | `await user.hasPerm('blog.change_post')` |
| `authenticate(request, username=u, password=p)` | `await authenticate(c, { username: u, password: p })` |
| `login(request, user)` / `logout(request)` | `await login(c, user)` / `await logout(c)` |
| `@login_required` | `loginRequired(view)` (higher-order function) |
| `@permission_required('x.y')` | `permissionRequired('x.y')(view)` |
| `class User(AbstractUser)` | `class User extends Model({...}, { extends: AbstractUser })` + `AUTH_USER_MODEL` |
| `is_staff`, `date_joined`, `user_permissions` | `isStaff`, `dateJoined`, `userPermissions` |
| `rest_framework.authtoken`, simplejwt | `@ghuri/auth/rest` (`TokenAuthentication`, `JWTAuthentication`, ...) |

## User model and manager

`User` fields: `username` (unique, 150, `unicodeUsernameValidator`), `firstName`, `lastName`, `email`, `password` (hash), `isStaff`, `isActive`, `isSuperuser`, `lastLogin`, `dateJoined`, `groups` (M2M `Group`), `userPermissions` (M2M `Permission`). Statics: `USERNAME_FIELD = 'username'`, `EMAIL_FIELD = 'email'`, `REQUIRED_FIELDS = ['email']`.

`UserManager` methods (source signature: `createUser(usernameOrData, email?, password?, extraFields = {})`; same for `createSuperuser`). Both the Django positional form and an object form are accepted:

```ts
import { User } from '@ghuri/auth'

const ann = await User.objects.createUser('ann', 'ann@example.com', 's3cret!', { firstName: 'Ann' })
const bob = await User.objects.createUser({ username: 'bob', email: 'bob@example.com', password: 'pw' })
const root = await User.objects.createSuperuser('admin', 'admin@example.com', 's3cret!') // isStaff+isSuperuser true

await ann.setPassword('new password') // async (WebCrypto); does NOT save
await ann.save()
await ann.checkPassword('new password') // true; re-hashes + saves outdated hashes
ann.setUnusablePassword()
ann.hasUsablePassword() // false
ann.getFullName(); ann.getShortName(); ann.getUsername()

const staff = await User.objects.withPerm('blog.change_post') // QuerySet incl. active superusers
const u = await User.objects.getByNaturalKey('ann')
```

A `null`/missing password gives an unusable password. `createUser` does not run password validators (as in Django). Never assign `user.password` a raw password.

## Current user, login, logout

`getUser(c)` never returns null: anonymous requests get `AnonymousUser` (`isAuthenticated === false`, `hasPerm()` resolves `false`). The `RequestUser` interface (core) has `pk`, `isAuthenticated`, `isAnonymous`, `isActive?`, `isStaff?`, `isSuperuser?`, `username?`, `hasPerm()`, `hasPerms?()`, `hasModulePerms?()`.

```tsx
import { authenticate, isSafeRedirect, login, logout } from '@ghuri/auth'
import { getCsrfToken, getUser, json, redirect } from '@ghuri/core'
import type { Context } from 'hono'

export async function me(c: Context) {
  const user = getUser(c)
  if (!user.isAuthenticated) return json(c, { user: null })
  return json(c, { id: user.pk, username: user.username, staff: user.isStaff })
}

export async function loginView(c: Context) {
  if (c.req.method === 'POST') {
    const form = await c.req.parseBody()
    const user = await authenticate(c, { username: String(form.username), password: String(form.password) })
    if (user) {
      await login(c, user) // rotates session key + CSRF token, sends userLoggedIn (updates lastLogin)
      const next = c.req.query('next')
      return redirect(c, next && isSafeRedirect(next, [new URL(c.req.url).host]) ? next : 'home')
    }
  }
  return c.html(
    <form method="post">
      <input type="hidden" name="csrfmiddlewaretoken" value={getCsrfToken(c)} />
      <input name="username" /> <input name="password" type="password" /> <button>Log in</button>
    </form>,
  )
}

export async function logoutView(c: Context) {
  await logout(c)
  return redirect(c, 'home')
}
```

`authenticate` returns `null` for bad credentials and inactive users (and sends `userLoginFailed`). Changing a password invalidates other sessions; call `updateSessionAuthHash(c, user)` to keep the current one. Signals: `userLoggedIn`, `userLoggedOut`, `userLoginFailed`.

Built-in views: `path('accounts/', include(authUrls))` gives `login/` (`login`), `logout/` (`logout`, POST only), `password_change/`, `password_reset/`, `reset/<uidb64>/<token>/` (`password_reset_confirm`), `me/` (`whoami`). Classes: `LoginView`, `LogoutView`, `PasswordChangeView`, `PasswordResetView` (override `sendResetEmail(c, info)` or pass it to `asView({ sendResetEmail })`; there is no mail package), `PasswordResetConfirmView`, `WhoAmIView`. Reset tokens: `defaultTokenGenerator.makeToken(user)` / `.checkToken(user, token)` (`PasswordResetTokenGenerator`).

Backends (`AUTHENTICATION_BACKENDS`, default `[ModelBackend]`): `ModelBackend`, `AllowAllUsersModelBackend`, `RemoteUserBackend`, `AllowAllUsersRemoteUserBackend`, or subclass `BaseBackend` (implement `authenticate(c, credentials)` and `getUser(userId)`, set `static backendName` because bundlers minify class names).

## Protecting views (exported from `@ghuri/auth`)

```ts
import {
  LoginRequiredMixin, loginRequired, PermissionRequiredMixin, permissionRequired, staffMemberRequired,
  UserPassesTestMixin, userPassesTest,
} from '@ghuri/auth'
import { getUser, path, View } from '@ghuri/core'
import type { Context } from 'hono'
import * as views from './views'

export const urlpatterns = [
  path('drafts/', loginRequired(views.drafts), { name: 'drafts' }),
  path('secret/', loginRequired({ loginUrl: '/login/' })(views.secret)),
  path('<slug:slug>/edit/', permissionRequired('blog.change_post')(views.edit), { name: 'edit' }),
  path('reports/', userPassesTest((u) => u.isStaff === true)(views.reports)),
  path('stats/', staffMemberRequired(views.stats)),
]

export class Dashboard extends LoginRequiredMixin(View) { async get(c: Context) { return c.text('hi') } }
export class Publish extends PermissionRequiredMixin(View) { permissionRequired = 'blog.publish_post' }
export class StaffOnly extends UserPassesTestMixin(View) { testFunc(c: Context) { return getUser(c).isStaff === true } }
```

`AccessOptions`: `loginUrl`, `redirectFieldName` (default `'next'`), `raiseException`. Anonymous browsers -> redirect to `LOGIN_URL?next=...`; JSON clients -> 401; authenticated but denied -> 403 (Django would redirect). Also `redirectToLogin`, `denyAccess`, `AccessMixin`. For REST views use permission classes from `@ghuri/rest` (`IsAuthenticated`, `IsAdminUser`, ...) instead.

## Permissions and groups

```ts
import { ContentType, Group, Permission, User } from '@ghuri/auth'
import { Post } from './models'

const user = await User.objects.get({ username: 'ann' })
await user.hasPerm('blog.change_post')                  // 'appLabel.codename'
await user.hasPerms(['blog.add_post', 'blog.change_post'])
await user.hasModulePerms('blog')
await user.getAllPermissions()                          // Set<string>, cached per instance
user.clearPermCache()

const editors = await Group.objects.create({ name: 'Editors' })
await editors.permissions.add(await Permission.objects.getByNaturalKey('change_post', 'blog', 'post'))
await user.groups.add(editors)
const ct = await ContentType.objects.getForModel(Post)
```

Extra permissions on a model: `static Meta = { permissions: [['publish_post', 'Can publish posts']] }` (array of `[codename, name]`; `defaultPermissions` also exists). Active superusers pass every check; inactive users fail.

## Sessions

API is async: `await session.get('k', fallback)`, `set`, `has`, `delete`, `pop`, `update`, `keys`, `items`, `clear`, `setExpiry(seconds | Date | null)`, `cycleKey`, `flush`. `SESSION_ENGINE`: `'db'` (default, needs `SessionsConfig`), `'kv'` (Workers KV binding `SESSION_KV_BINDING`, default `'SESSIONS'`), `'cache'` (`SESSION_CACHE_ALIAS`), `'signedCookie'`, or a `SessionBase` subclass. Run `npx ghuri clearsessions` from a cron.

## Passwords

Hashers (`PASSWORD_HASHERS`, first one hashes): `PBKDF2PasswordHasher` (default, `pbkdf2_sha256$...`, **100,000 iterations** for Workers CPU limits), `PBKDF2SHA1PasswordHasher`, `ScryptPasswordHasher`. Django hashes verify and are upgraded on login. No bcrypt / Argon2 / MD5. Validators (`AUTH_PASSWORD_VALIDATORS`, empty by default): `UserAttributeSimilarityValidator`, `MinimumLengthValidator` (`{ minLength }`), `CommonPasswordValidator`, `NumericPasswordValidator`.

```ts
import {
  checkPassword, CommonPasswordValidator, makePassword, MinimumLengthValidator, PBKDF2PasswordHasher,
  ScryptPasswordHasher, validatePassword,
} from '@ghuri/auth'
import { defineSettings } from '@ghuri/core'

export default defineSettings((env) => ({
  PASSWORD_HASHERS: [new PBKDF2PasswordHasher({ iterations: 600_000 }), ScryptPasswordHasher], // classes or instances
  AUTH_PASSWORD_VALIDATORS: [
    { NAME: MinimumLengthValidator, OPTIONS: { minLength: 10 } },
    { NAME: CommonPasswordValidator },
  ],
}))

const hash = await makePassword('pw')               // makePassword(null) -> unusable
await checkPassword('pw', hash)                      // true
await validatePassword('123', undefined)            // throws ValidationError with all messages
```

In tests use a fast hasher: `ctx.settings.PASSWORD_HASHERS = [new PBKDF2PasswordHasher({ iterations: 1000 })]`.

## Custom user model

Set it up **before the first migrate**:

```ts
// src/accounts/models.ts
import { AbstractUser, type UserManager } from '@ghuri/auth'
import { Model, TextField, URLField } from '@ghuri/orm'

export class User extends Model({
  website: new URLField({ blank: true }),
  bio: new TextField({ blank: true }),
}, { extends: AbstractUser }) {
  declare static objects: UserManager<User>
}
// settings: INSTALLED_APPS [..., AccountsConfig], AUTH_USER_MODEL: 'accounts.User'
// then: npx ghuri makemigrations accounts && npx ghuri migrate
```

Bases: `AbstractBaseUser` (only `password`, `lastLogin`; set `static USERNAME_FIELD`, `EMAIL_FIELD`, `REQUIRED_FIELDS`), `PermissionsMixin` (= `AbstractBaseUser` + `isSuperuser`, `groups`, `userPermissions`; inheritance is linear, use `{ extends: PermissionsMixin }`), `AbstractUser` (everything `User` has). `permissionsMixinFields()` returns the bare field map. `BaseUserManager` for custom managers (`normalizeEmail`, `getByNaturalKey`, `makeRandomPassword`). Email-as-username: `Account.objects.createUser('a@example.com', undefined, 'pw')`.

Reusable code: `const UserModel = getUserModel()` (also `getUserModelLabel()`, `isUserModelSwapped()`). When swapped, `auth.User` is not installed, `UserAdmin` is not auto-registered, and `Token.user` / `LogEntry.user` point at your model.

## Tokens and JWT (`@ghuri/auth/rest`)

`@ghuri/auth/rest` exports `SessionAuthentication` (enforces CSRF on unsafe methods), `TokenAuthentication` (`Authorization: Token <key>`; override `keyword`, `model`), `JWTAuthentication` (`Authorization: Bearer <access>`), `BasicAuthentication`, `RemoteUserAuthentication`, views `obtainAuthToken` (= `ObtainAuthTokenView.asView()`), `TokenObtainPairView`, `TokenRefreshView`, `TokenVerifyView`, `TokenBlacklistView`, types `BaseAuthentication`, `AuthResult`, `SecuritySchemeInfo`, errors `AuthenticationFailed`, `InvalidToken`, `NotAuthenticated`, `TokenError`, and re-exports `AccessToken`, `RefreshToken`, `UntypedToken`, `JWTToken`, `jwtSettings`, `tokenPairForUser`. They do not import `@ghuri/rest`; first class returning a user wins. Without config, `@ghuri/rest` defaults to its own `MiddlewareAuthentication`.

```ts
import {
  obtainAuthToken, TokenBlacklistView, TokenObtainPairView, TokenRefreshView, TokenVerifyView,
} from '@ghuri/auth/rest'
import { path } from '@ghuri/core'

export const urlpatterns = [
  path('api/auth/token/', obtainAuthToken, { name: 'api-token' }),                 // {username,password} -> {token}
  path('api/auth/jwt/', TokenObtainPairView.asView(), { name: 'jwt-obtain' }),     // -> {refresh, access}
  path('api/auth/jwt/refresh/', TokenRefreshView.asView(), { name: 'jwt-refresh' }), // {refresh} -> {access, refresh?}
  path('api/auth/jwt/verify/', TokenVerifyView.asView(), { name: 'jwt-verify' }),  // {token} -> 200 {} | 401
  path('api/auth/jwt/blacklist/', TokenBlacklistView.asView()),                    // needs TokenBlacklistConfig
]
```

Token endpoints are CSRF-exempt and accept JSON or form data. In code:

```ts
import { AccessToken, RefreshToken, Token, tokenPairForUser, User } from '@ghuri/auth'

const user = await User.objects.get({ username: 'ann' })
const [token] = await Token.objects.getOrCreate({ user })  // token.key: 40 hex chars, never expires
const { refresh, access } = await tokenPairForUser(user)
const r = await RefreshToken.forUser(user)                  // recorded as outstanding if blacklist app installed
r.set('tenant', 't1')                                       // custom claims copied to access tokens
const accessJwt = await r.accessToken.encode()
const parsed = await AccessToken.fromString(accessJwt)     // throws TokenError (bad sig, expired, wrong type)
await r.blacklist()                                         // needs TokenBlacklistConfig
```

`JWT` setting (alias `SIMPLE_JWT`; lifetimes in **seconds**): `ACCESS_TOKEN_LIFETIME` (300), `REFRESH_TOKEN_LIFETIME` (86400), `ROTATE_REFRESH_TOKENS` (false), `BLACKLIST_AFTER_ROTATION` (false), `UPDATE_LAST_LOGIN` (false), `ALGORITHM` (`'HS256'`; RS/PS/ES/EdDSA supported), `SIGNING_KEY` (`SECRET_KEY`), `VERIFYING_KEY`, `AUDIENCE`, `ISSUER`, `LEEWAY` (0), `AUTH_HEADER_TYPES` (`['Bearer']`), `USER_ID_FIELD` (`'id'`), `USER_ID_CLAIM` (`'user_id'`), `TOKEN_TYPE_CLAIM`, `JTI_CLAIM`, `CHECK_REVOKE_TOKEN` (false), `REVOKE_TOKEN_CLAIM`.

## Signing (`django.core.signing` port)

```ts
import { dumps, loads, Signer, TimestampSigner } from '@ghuri/auth'

const s = await dumps({ userId: 1 }, { salt: 'unsubscribe', compress: true })
const data = await loads(s, { salt: 'unsubscribe', maxAge: 3600 })   // throws BadSignature / SignatureExpired
const signed = await new Signer({ salt: 'x' }).sign('value')          // 'value:signature'
await new TimestampSigner().unsign(await new TimestampSigner().sign('v'), 60)
```

Also `signing` namespace object, `BadSignature`, `SignatureExpired`. All async (WebCrypto). Byte-compatible with Django given the same `SECRET_KEY`.

## Auth settings (typed on `GhuriSettings` once `@ghuri/auth` is imported)

`AUTH_USER_MODEL` (`'auth.User'`), `AUTHENTICATION_BACKENDS`, `PASSWORD_HASHERS`, `AUTH_PASSWORD_VALIDATORS`, `SECRET_KEY_FALLBACKS`, `LOGIN_URL` (`'/accounts/login/'`), `LOGIN_REDIRECT_URL` (`'/accounts/profile/'`), `LOGOUT_REDIRECT_URL`, `PASSWORD_RESET_TIMEOUT` (3 days, seconds), `SESSION_ENGINE`, `SESSION_COOKIE_NAME`, `SESSION_COOKIE_AGE`, `SESSION_COOKIE_DOMAIN`, `SESSION_COOKIE_PATH`, `SESSION_COOKIE_SECURE`, `SESSION_COOKIE_HTTPONLY`, `SESSION_COOKIE_SAMESITE`, `SESSION_SAVE_EVERY_REQUEST`, `SESSION_EXPIRE_AT_BROWSER_CLOSE`, `SESSION_KV_BINDING`, `SESSION_CACHE_ALIAS`, `REMOTE_USER_HEADER`, `JWT`.

## Testing

Importing `@ghuri/auth` registers test-client hooks: `await client.forceLogin(user)`, `await client.login({ username, password })` (true/false), `await client.logout()`. With `APIClient` from `@ghuri/rest/testing`: `api.client.forceLogin(user)` or `api.forceAuthenticate(user)`. `db.flush()` recreates content types and permissions.

## Gotchas

- Everything touching passwords, sessions, permissions or tokens is **async**: `await user.setPassword()`, `await user.checkPassword()`, `await user.hasPerm()`, `await session.get()`. A missing `await` on `hasPerm` is always truthy (a Promise).
- `setPassword` does not save; call `await user.save()`. Never set `user.password = 'raw'`.
- `request.user` does not exist: use `getUser(c)`. It is never null (AnonymousUser).
- `SessionMiddleware` before `AuthenticationMiddleware`; `ContentTypesConfig` before `AuthConfig`.
- `loginRequired` etc. are wrapper functions, not decorators (`loginRequired(view)`, `permissionRequired('a.b')(view)`). Logged-in users without access get 403, not a login redirect.
- Field names are camelCase: `isStaff`, `isSuperuser`, `dateJoined`, `userPermissions`, `lastLogin`.
- Permissions are strings `'appLabel.codename'` (`'blog.change_post'`), same as Django.
- Session/JWT lifetimes are seconds, not `timedelta`. The setting key is `JWT` (`SIMPLE_JWT` alias).
- Token/JWT classes and views import from `@ghuri/auth/rest`, not `@ghuri/rest`; `Token`, `AccessToken`, `RefreshToken` are also exported from `@ghuri/auth`.
- `TokenBlacklistView` / `refresh.blacklist()` require `TokenBlacklistConfig`. Blacklisting only affects refresh tokens.
- Swap `AUTH_USER_MODEL` before the first migrate; reusable code should call `getUserModel()` instead of importing `User`.
- PBKDF2 defaults to 100,000 iterations (not Django's 1,000,000) because of Workers CPU limits.
- No mail package: password reset needs your own `sendResetEmail`.
