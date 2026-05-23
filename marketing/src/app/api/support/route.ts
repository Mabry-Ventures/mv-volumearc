import { NextResponse } from 'next/server'

import {
  sendSupportEmail,
  SupportEmailConfigurationError,
  SupportEmailDeliveryError,
  validateSupportRequest,
} from '@/lib/supportEmail'

export const runtime = 'nodejs'

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
