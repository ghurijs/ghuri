# Email (@ghuri/mail)

Covers `django.core.mail` in Ghuri: `sendMail`, `sendMassMail`, `mailAdmins` / `mailManagers`, `EmailMessage` / `EmailMultiAlternatives`, attachments and HTML alternatives, `getConnection`, the `EMAIL_BACKEND` setting and backends (Cloudflare Email Service, Resend, SMTP, console, locmem, dummy), custom backends, errors and the test outbox.

Install: `npm install @ghuri/mail@next` (needs `@ghuri/core` 0.1.0-alpha.1+). It is a library, not an app: nothing goes in `INSTALLED_APPS`. No runtime dependencies.

Entry points (from `packages/mail/package.json`):

| Import | Exports you use |
|---|---|
| `@ghuri/mail` | `sendMail`, `sendMassMail`, `mailAdmins`, `mailManagers`, `EmailMessage`, `EmailMultiAlternatives`, `getConnection`, `BaseEmailBackend`, `cloudflareEmailBackend`, `resendBackend`, `consoleBackend`, `locmemBackend`, `dummyBackend`, `BadHeaderError`, `EmailSendError`, `MIMEPart`, `parseAddress`, `formatAddress`, `sanitizeAddress`, `type EmailBackendConfig` |
| `@ghuri/mail/smtp` | `smtpBackend` (Node only: `node:net` / `node:tls`) |
| `@ghuri/mail/testing` | `outbox`, `useOutbox`, `restoreEmailBackend`, `clearOutbox` |

## Django habit -> Ghuri

| Django | Ghuri |
|---|---|
| `send_mail(subject, message, from_email, recipient_list, html_message=h, fail_silently=True)` | `await sendMail(subject, message, fromEmail, recipientList, { htmlMessage: h, failSilently: true })` |
| `from_email=None` -> `DEFAULT_FROM_EMAIL` | `fromEmail` `null` -> `DEFAULT_FROM_EMAIL` |
| `send_mass_mail(((s, m, f, [to]), ...))` | `await sendMassMail([[s, m, f, [to]], ...])` |
| `mail_admins(s, m)` / `mail_managers(s, m)` | `await mailAdmins(s, m)` / `await mailManagers(s, m)` |
| `EmailMessage(subject, body, from_email, to, bcc, reply_to=..., headers=...)` | `new EmailMessage(subject, body, { fromEmail, to, cc, bcc, replyTo, headers, attachments, connection })` |
| `msg.attach_alternative(html, 'text/html')` | `msg.attachAlternative(html, 'text/html')` (on `EmailMultiAlternatives`) |
| `msg.attach('a.pdf', data, 'application/pdf')` | `msg.attach('a.pdf', bytes, 'application/pdf')` (MIME type guessed when omitted) |
| `msg.attach_file('/path/a.pdf')` | does not exist: read the bytes and `attach()` |
| `msg.content_subtype = 'html'` | `msg.contentSubtype = 'html'` |
| `msg.send()` | `await msg.send()` (returns the number sent) |
| `get_connection()` + `connection.send_messages([...])` | `getConnection()` + `await connection.sendMessages([...])` |
| `EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'` | `EMAIL_BACKEND: smtpBackend()` from `@ghuri/mail/smtp` (Node only) |
| `...backends.console/locmem/dummy.EmailBackend` | `consoleBackend()`, `locmemBackend()`, `dummyBackend()` |
| `ADMINS = [('Jane', 'jane@x.com')]` | `ADMINS: ['Jane <jane@x.com>']` (strings only) |
| `mail.outbox` | `outbox` from `@ghuri/mail/testing` |

## Settings

```ts
// src/settings.ts
import { defineSettings } from '@ghuri/core'
import { cloudflareEmailBackend, consoleBackend, resendBackend } from '@ghuri/mail'

export default defineSettings((env) => ({
  // ...
  EMAIL_BACKEND:
    env.DEBUG === 'true'
      ? consoleBackend()
      : env.RESEND_API_KEY
        ? resendBackend({ apiKey: env.RESEND_API_KEY })
        : cloudflareEmailBackend({ binding: 'EMAIL' }),
  DEFAULT_FROM_EMAIL: 'Shop <noreply@shop.example.com>',
  SERVER_EMAIL: 'errors@shop.example.com',
  ADMINS: ['Jane <jane@shop.example.com>'],
  MANAGERS: ['orders@shop.example.com'],
  EMAIL_SUBJECT_PREFIX: '[Shop] ',
}))
```

| Key | Default | |
|---|---|---|
| `EMAIL_BACKEND` | `consoleBackend()` in `DEBUG`, otherwise none | Sending with none raises `ImproperlyConfigured`. There is NO default SMTP backend. |
| `DEFAULT_FROM_EMAIL` | `'webmaster@localhost'` | Sender when none is given. |
| `SERVER_EMAIL` | `'root@localhost'` | Sender of `mailAdmins` / `mailManagers`. |
| `EMAIL_SUBJECT_PREFIX` | `'[Ghuri] '` | Prefix for `mailAdmins` / `mailManagers`. |
| `ADMINS` / `MANAGERS` | `[]` | Address strings (`'Jane <jane@example.com>'`). |
| `EMAIL_TIMEOUT` | `null` | Seconds for network backends (Resend, SMTP). |
| `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `EMAIL_USE_TLS`, `EMAIL_USE_SSL` | `'localhost'`, `25`, `''`, `''`, `false`, `false` | Read by `smtpBackend()` only. TLS = STARTTLS (587), SSL = implicit TLS (465). |

Cloudflare Email Service needs a `send_email` binding in `wrangler.jsonc` and a sender domain onboarded to Email Sending:

```jsonc
{ "send_email": [{ "name": "EMAIL" }] }
```

Secrets (`RESEND_API_KEY`, SMTP password) come from `env` in the settings factory (`npx wrangler secret put RESEND_API_KEY`), never `process.env` in app code.

## Sending

```ts
import { EmailMultiAlternatives, getConnection, mailAdmins, sendMail, sendMassMail } from '@ghuri/mail'

await sendMail('Welcome', 'Thanks for signing up.', null, [user.email])            // returns 1
await sendMail('Subject', 'Plain text.', 'from@example.com', ['to@example.com'], {
  htmlMessage: '<p>HTML version</p>',
})

await sendMassMail([
  ['Subject', 'Message.', 'from@example.com', ['first@example.com', 'other@example.com']],
  ['Subject', 'Message.', 'from@example.com', ['second@example.com']],
])

const email = new EmailMultiAlternatives('Your invoice', 'Invoice attached.', {
  to: ['Jane <jane@example.com>'],
  bcc: ['archive@example.com'],
  replyTo: ['billing@example.com'],
  headers: { 'List-Unsubscribe': '<mailto:unsubscribe@example.com>' },
})
email.attachAlternative('<p>Invoice attached.</p>', 'text/html')
email.attach('invoice.pdf', pdfBytes)
await email.send()

const connection = getConnection()                 // one connection for many messages
await connection.sendMessages([email1, email2])

await mailAdmins('Payment webhook failed', String(err))
```

- `sendMail` options: `htmlMessage`, `failSilently`, `authUser`, `authPassword`, `connection`. Everyone in `recipientList` sees each other in `To`; send one message per user for private mail.
- `EmailMessage` also accepts one object: `new EmailMessage({ subject, body, to, ... })`. Members: `attach(filename, content, mimetype?)` or `attach({ filename, content, mimetype })`, `send(failSilently?)`, `recipients()`, `message()` (a `MIMEPart`; `.asString()` is the RFC 5322 source), `contentSubtype`, `extraHeaders`. `EmailMultiAlternatives` adds `attachAlternative()` and `bodyContains(text)`.
- Sending needs a Ghuri context (settings + `env`): views, signal receivers, `onQueue` / `onSchedule` handlers, management commands, or tests after `app.setup(env)`. Outside one, `getConnection()` raises `ImproperlyConfigured` unless you pass a connection.
- For slow providers or bulk mail, send from an `onQueue` consumer, not inside the request (see signals-cache-tasks-commands.md).
- A newline in a subject, address or header raises `BadHeaderError` (header injection protection). Delivery failures raise `EmailSendError` (`status`, `code`, `response`); with `failSilently` they are swallowed and not counted. `ImproperlyConfigured` always raises.
- No template rendering: build subject and body strings (or JSX rendered to a string) in your own helper.

## Backends

| Factory | Runs on | Notes |
|---|---|---|
| `cloudflareEmailBackend({ binding = 'EMAIL' })` | Workers | `send_email` binding from the request's `env`. One Reply-To address; only `X-*` and a short allowlist of custom headers. |
| `resendBackend({ apiKey, baseUrl?, timeout?, fetch? })` | anywhere with `fetch` | Resend HTTP API, one request per message. |
| `smtpBackend({ host, port, username, password, useTls, useSsl, timeout, tlsOptions })` | Node only | From `@ghuri/mail/smtp`. Omitted options fall back to the `EMAIL_*` settings. |
| `consoleBackend({ stream? })` | anywhere | Prints the MIME source. Default in `DEBUG`. |
| `locmemBackend()` | anywhere | Appends to `outbox`. |
| `dummyBackend()` | anywhere | Does nothing. |

API backends (Cloudflare, Resend) send fields, not MIME: the body becomes `text` (or `html` when `contentSubtype === 'html'`), a `text/html` or `text/plain` alternative fills the other; any other alternative type raises `EmailSendError`. `To` / `Cc` headers are not sent (recipient lists are).

Custom backend:

```ts
import { BaseEmailBackend, type EmailBackendConfig, type EmailMessage } from '@ghuri/mail'

class WebhookBackend extends BaseEmailBackend {
  async sendMessages(messages: EmailMessage[]): Promise<number> {
    for (const m of messages) await fetch('https://hooks.example.com/mail', { method: 'POST', body: m.message().asString() })
    return messages.length
  }
}
export const webhookBackend = (): EmailBackendConfig => ({ backend: 'webhook', create: (env, options) => new WebhookBackend(options) })
```

## Testing

```ts
import { outbox, restoreEmailBackend, useOutbox } from '@ghuri/mail/testing'

beforeEach(() => useOutbox())          // route EMAIL_BACKEND to locmem and empty the outbox
afterEach(() => restoreEmailBackend())

it('sends a welcome email', async () => {
  await client.post('/signup/', { form: { email: 'jane@example.com' } })
  expect(outbox).toHaveLength(1)
  expect(outbox[0].subject).toBe('Welcome')
  expect(outbox[0].to).toEqual(['jane@example.com'])
})
```

`outbox` is always the same array (`clearOutbox()` empties it in place). Alternative: `EMAIL_BACKEND: locmemBackend()` in test settings.

## Gotchas

- `sendMail(to, subject, body)` / `sendMail({ to, subject, html })` are wrong: the order is Django's `(subject, message, fromEmail, recipientList, options)` and `recipientList` is an array.
- `EMAIL_BACKEND: 'smtp'` or a dotted string is wrong: use a factory (`smtpBackend()`).
- `@ghuri/mail/smtp` in Worker code breaks the bundle (Workers cannot open SMTP sockets). On Workers use Cloudflare or Resend.
- Forgetting `await` on `sendMail` / `send()` drops the message when the Worker finishes; for fire-and-forget use a queue or `getContext().executionCtx?.waitUntil(sendMail(...))`.
- No `attachFile()`, no templated email helper, and no nodemailer: use the factories above.
