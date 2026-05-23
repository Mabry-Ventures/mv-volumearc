'use client'

import { type FormEvent, useState } from 'react'

const categories = [
  { value: 'app-help', label: 'App help' },
  { value: 'bug-report', label: 'Bug report' },
  { value: 'subscription', label: 'Subscription' },
  { value: 'privacy', label: 'Privacy' },
  { value: 'press', label: 'Press' },
  { value: 'other', label: 'Other' },
] as const

type FormState = 'idle' | 'sending' | 'sent' | 'error'

type FieldErrors = Partial<
  Record<'name' | 'email' | 'category' | 'message' | 'form', string>
>

export function SupportForm() {
  const [state, setState] = useState<FormState>('idle')
  const [errors, setErrors] = useState<FieldErrors>({})

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setState('sending')
    setErrors({})

    const form = event.currentTarget
    const data = new FormData(form)

    let response: Response
    let result: { errors?: FieldErrors } | null

    try {
      response = await fetch('/api/support', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: data.get('name'),
          email: data.get('email'),
          category: data.get('category'),
          message: data.get('message'),
          company: data.get('company'),
        }),
      })
      result = (await response.json().catch(() => null)) as
        | { errors?: FieldErrors }
        | null
    } catch {
      setErrors({
        form: 'We could not send that message. Email support@mabryventures.com directly.',
      })
      setState('error')
      return
    }

    if (!response.ok) {
      setErrors(
        result?.errors ?? {
          form: 'We could not send that message. Email support@mabryventures.com directly.',
        },
      )
      setState('error')
      return
    }

    form.reset()
    setState('sent')
  }

  return (
    <form
      className="mt-5 grid gap-4 border-t border-gray-200 pt-6"
      onSubmit={handleSubmit}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label
            className="block text-sm font-medium text-gray-900"
            htmlFor="support-name"
          >
            Name
          </label>
          <input
            className="mt-2 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm outline-none focus:border-sunrise-600 focus:ring-2 focus:ring-sunrise-600/20"
            id="support-name"
            name="name"
            type="text"
            autoComplete="name"
            maxLength={80}
            aria-invalid={Boolean(errors.name)}
            aria-describedby={errors.name ? 'support-name-error' : undefined}
            required
          />
          {errors.name ? (
            <p className="mt-1 text-sm text-red-700" id="support-name-error">
              {errors.name}
            </p>
          ) : null}
        </div>

        <div>
          <label
            className="block text-sm font-medium text-gray-900"
            htmlFor="support-email"
          >
            Email
          </label>
          <input
            className="mt-2 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm outline-none focus:border-sunrise-600 focus:ring-2 focus:ring-sunrise-600/20"
            id="support-email"
            name="email"
            type="email"
            autoComplete="email"
            maxLength={254}
            aria-invalid={Boolean(errors.email)}
            aria-describedby={errors.email ? 'support-email-error' : undefined}
            required
          />
          {errors.email ? (
            <p className="mt-1 text-sm text-red-700" id="support-email-error">
              {errors.email}
            </p>
          ) : null}
        </div>
      </div>

      <div>
        <label
          className="block text-sm font-medium text-gray-900"
          htmlFor="support-category"
        >
          Topic
        </label>
        <select
          className="mt-2 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm outline-none focus:border-sunrise-600 focus:ring-2 focus:ring-sunrise-600/20"
          id="support-category"
          name="category"
          defaultValue="app-help"
          aria-invalid={Boolean(errors.category)}
          aria-describedby={
            errors.category ? 'support-category-error' : undefined
          }
          required
        >
          {categories.map((category) => (
            <option key={category.value} value={category.value}>
              {category.label}
            </option>
          ))}
        </select>
        {errors.category ? (
          <p className="mt-1 text-sm text-red-700" id="support-category-error">
            {errors.category}
          </p>
        ) : null}
      </div>

      <div aria-hidden="true" className="hidden">
        <label htmlFor="support-company">Company</label>
        <input
          id="support-company"
          name="company"
          type="text"
          tabIndex={-1}
          autoComplete="off"
        />
      </div>

      <div>
        <label
          className="block text-sm font-medium text-gray-900"
          htmlFor="support-message"
        >
          Message
        </label>
        <textarea
          className="mt-2 block min-h-36 w-full resize-y rounded-md border border-gray-300 bg-white px-3 py-2 text-gray-900 shadow-sm outline-none focus:border-sunrise-600 focus:ring-2 focus:ring-sunrise-600/20"
          id="support-message"
          name="message"
          maxLength={4000}
          aria-invalid={Boolean(errors.message)}
          aria-describedby={
            errors.message ? 'support-message-error' : undefined
          }
          required
        />
        {errors.message ? (
          <p className="mt-1 text-sm text-red-700" id="support-message-error">
            {errors.message}
          </p>
        ) : null}
      </div>

      {errors.form ? (
        <p className="text-sm text-red-700" role="alert">
          {errors.form}
        </p>
      ) : null}

      {state === 'sent' ? (
        <p className="text-sm text-emerald-700" role="status">
          Message sent. We&rsquo;ll reply within one business day.
        </p>
      ) : null}

      <div>
        <button
          className="inline-flex min-h-11 items-center justify-center rounded-md bg-sunrise-700 px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-sunrise-800 focus:outline-none focus:ring-2 focus:ring-sunrise-600 focus:ring-offset-2 disabled:cursor-not-allowed disabled:bg-gray-400"
          type="submit"
          disabled={state === 'sending'}
        >
          {state === 'sending' ? 'Sending...' : 'Send message'}
        </button>
      </div>
    </form>
  )
}
