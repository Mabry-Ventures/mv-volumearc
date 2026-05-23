export type SupportCategory =
  | 'app-help'
  | 'bug-report'
  | 'subscription'
  | 'privacy'
  | 'press'
  | 'other'

export type SupportRequest = {
  name: string
  email: string
  category: SupportCategory
  message: string
  company?: string
}

export type ValidSupportRequest = Omit<SupportRequest, 'company'>

type ValidationResult =
  | { ok: true; value: ValidSupportRequest; spam: boolean }
  | { ok: false; errors: Record<string, string> }

type SupportEmailConfig = {
  apiKey: string
  fromEmail?: string
  toEmail?: string
}

type FetchLike = typeof fetch

export class SupportEmailConfigurationError extends Error {
  constructor() {
    super('RESEND_API_KEY is not configured')
    this.name = 'SupportEmailConfigurationError'
  }
}

export class SupportEmailDeliveryError extends Error {
  status: number

  constructor(status: number, message: string) {
    super(message)
    this.name = 'SupportEmailDeliveryError'
    this.status = status
  }
}

const categoryLabels: Record<SupportCategory, string> = {
  'app-help': 'App help',
  'bug-report': 'Bug report',
  subscription: 'Subscription',
  privacy: 'Privacy',
  press: 'Press',
  other: 'Other',
}

const validCategories = new Set<SupportCategory>(
  Object.keys(categoryLabels) as SupportCategory[],
)

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function stringField(value: unknown) {
  return typeof value === 'string' ? value.trim() : ''
}

function truncate(value: string, maxLength: number) {
  return value.length > maxLength ? value.slice(0, maxLength) : value
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

export function validateSupportRequest(input: unknown): ValidationResult {
  const data =
    input !== null && typeof input === 'object'
      ? (input as Record<string, unknown>)
      : {}
  const name = truncate(stringField(data.name), 80)
  const email = truncate(stringField(data.email).toLowerCase(), 254)
  const category = stringField(data.category) as SupportCategory
  const message = truncate(stringField(data.message), 4000)
  const company = stringField(data.company)
  const errors: Record<string, string> = {}

  if (!name) {
    errors.name = 'Enter your name.'
  }

  if (!email || !emailPattern.test(email)) {
    errors.email = 'Enter a valid email address.'
  }

  if (!validCategories.has(category)) {
    errors.category = 'Choose a support category.'
  }

  if (message.length < 20) {
    errors.message = 'Tell us what happened in at least 20 characters.'
  }

  if (Object.keys(errors).length > 0) {
    return { ok: false, errors }
  }

  return {
    ok: true,
    spam: company.length > 0,
    value: {
      name,
      email,
      category,
      message,
    },
  }
}

export function buildSupportEmailPayload(request: ValidSupportRequest) {
  const categoryLabel = categoryLabels[request.category]
  const subject = `[VolumeArc support] ${categoryLabel} from ${request.name}`
  const text = [
    subject,
    '',
    `From: ${request.name} <${request.email}>`,
    `Category: ${categoryLabel}`,
    '',
    request.message,
  ].join('\n')
  const escapedMessage = escapeHtml(request.message).replace(/\n/g, '<br />')

  return {
    from: process.env.RESEND_FROM_EMAIL || 'VolumeArc <noreply@volumearc.app>',
    to: [process.env.SUPPORT_EMAIL_TO || 'support@mabryventures.com'],
    reply_to: request.email,
    subject,
    text,
    html: [
      `<p><strong>From:</strong> ${escapeHtml(request.name)} &lt;${escapeHtml(
        request.email,
      )}&gt;</p>`,
      `<p><strong>Category:</strong> ${escapeHtml(categoryLabel)}</p>`,
      `<p>${escapedMessage}</p>`,
    ].join(''),
    tags: [
      { name: 'source', value: 'support-form' },
      { name: 'category', value: request.category },
    ],
  }
}

export async function sendSupportEmail(
  request: ValidSupportRequest,
  config: SupportEmailConfig,
  fetchImpl: FetchLike = fetch,
) {
  if (!config.apiKey) {
    throw new SupportEmailConfigurationError()
  }

  const payload = buildSupportEmailPayload(request)
  const response = await fetchImpl('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      ...payload,
      from: config.fromEmail || payload.from,
      to: [config.toEmail || payload.to[0]],
    }),
  })

  if (!response.ok) {
    const body = await response.text()
    throw new SupportEmailDeliveryError(
      response.status,
      `Resend rejected the support email (${response.status}): ${body.slice(
        0,
        240,
      )}`,
    )
  }

  return response.json().catch(() => ({}))
}
