import { NextResponse } from 'next/server'

import {
  sendSupportEmail,
  SupportEmailConfigurationError,
  SupportEmailDeliveryError,
  validateSupportRequest,
} from '@/lib/supportEmail'

export const runtime = 'nodejs'

const rateLimitWindowMs = 10 * 60 * 1000
const rateLimitMaxRequests = 5
const rateLimitBuckets = new Map<string, { count: number; resetAt: number }>()

function clientKey(request: Request) {
  const forwardedFor = request.headers.get('x-forwarded-for')?.split(',')[0]
  const realIp = request.headers.get('x-real-ip')
  const userAgent = request.headers.get('user-agent') ?? 'unknown-agent'

  return `${forwardedFor ?? realIp ?? 'unknown-ip'}:${userAgent.slice(0, 120)}`
}

function isRateLimited(key: string, now = Date.now()) {
  const bucket = rateLimitBuckets.get(key)

  if (!bucket || bucket.resetAt <= now) {
    rateLimitBuckets.set(key, {
      count: 1,
      resetAt: now + rateLimitWindowMs,
    })
    return false
  }

  bucket.count += 1
  return bucket.count > rateLimitMaxRequests
}

export async function POST(request: Request) {
  let body: unknown

  try {
    body = await request.json()
  } catch {
    return NextResponse.json(
      { ok: false, errors: { form: 'Send a valid JSON request.' } },
      { status: 400 },
    )
  }

  const validation = validateSupportRequest(body)
  if (!validation.ok) {
    return NextResponse.json(
      { ok: false, errors: validation.errors },
      { status: 400 },
    )
  }

  // Honeypot submissions get a success-shaped response without sending mail.
  if (validation.spam) {
    return NextResponse.json({ ok: true }, { status: 202 })
  }

  if (isRateLimited(clientKey(request))) {
    console.warn('Support form rate limit exceeded')
    return NextResponse.json(
      {
        ok: false,
        errors: {
          form: 'Too many support messages. Wait a few minutes and try again.',
        },
      },
      { status: 429 },
    )
  }

  try {
    await sendSupportEmail(validation.value, {
      apiKey: process.env.RESEND_API_KEY ?? '',
      fromEmail: process.env.RESEND_FROM_EMAIL,
      toEmail: process.env.SUPPORT_EMAIL_TO,
    })

    return NextResponse.json({ ok: true }, { status: 202 })
  } catch (error) {
    if (error instanceof SupportEmailConfigurationError) {
      return NextResponse.json(
        {
          ok: false,
          errors: {
            form: 'Support email is not configured yet. Email support@mabryventures.com directly.',
          },
        },
        { status: 503 },
      )
    }

    if (error instanceof SupportEmailDeliveryError) {
      console.error(error.message)
    } else {
      console.error('Unexpected support email failure', error)
    }

    return NextResponse.json(
      {
        ok: false,
        errors: {
          form: 'We could not send that message. Email support@mabryventures.com directly.',
        },
      },
      { status: 502 },
    )
  }
}
