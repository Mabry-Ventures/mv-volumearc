import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

import ts from 'typescript'

const sourcePath = new URL('../src/lib/supportEmail.ts', import.meta.url)
const source = await readFile(sourcePath, 'utf8')
const compiled = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.ES2022,
    target: ts.ScriptTarget.ES2022,
  },
})
const tempDir = await mkdtemp(join(tmpdir(), 'volumearc-support-email-'))
const compiledPath = join(tempDir, 'supportEmail.mjs')

try {
  await writeFile(compiledPath, compiled.outputText)
  const {
    buildSupportEmailPayload,
    sendSupportEmail,
    validateSupportRequest,
  } = await import(pathToFileURL(compiledPath).href)

  const valid = validateSupportRequest({
    name: 'Jared Mabry',
    email: 'JARED@example.com',
    category: 'bug-report',
    message: 'The coach response panel got stuck after a streamed reply.',
    company: '',
  })

  assert.equal(valid.ok, true)
  assert.equal(valid.value.email, 'jared@example.com')
  assert.equal(valid.value.category, 'bug-report')

  const invalid = validateSupportRequest({
    name: '',
    email: 'not-an-email',
    category: 'bug-report',
    message: 'too short',
  })

  assert.equal(invalid.ok, false)
  assert.equal(invalid.errors.name, 'Enter your name.')
  assert.equal(invalid.errors.email, 'Enter a valid email address.')
  assert.equal(
    invalid.errors.message,
    'Tell us what happened in at least 20 characters.',
  )

  const payload = buildSupportEmailPayload(valid.value)
  assert.equal(
    payload.subject,
    '[VolumeArc support] Bug report from Jared Mabry',
  )
  assert.equal(payload.reply_to, 'jared@example.com')
  assert.deepEqual(payload.to, ['support@mabryventures.com'])
  assert.match(payload.text, /coach response panel got stuck/)
  assert.match(payload.html, /coach response panel got stuck/)

  let capturedRequest
  const response = await sendSupportEmail(
    valid.value,
    {
      apiKey: 're_test_key',
      fromEmail: 'VolumeArc <noreply@mail.volumearc.app>',
      toEmail: 'support@mabryventures.com',
    },
    async (url, init) => {
      capturedRequest = { url, init }
      return new Response(JSON.stringify({ id: 'email_123' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    },
  )

  assert.deepEqual(response, { id: 'email_123' })
  assert.equal(capturedRequest.url, 'https://api.resend.com/emails')
  assert.equal(capturedRequest.init.method, 'POST')
  assert.equal(
    capturedRequest.init.headers.Authorization,
    'Bearer re_test_key',
  )
  const sentBody = JSON.parse(capturedRequest.init.body)
  assert.equal(sentBody.from, 'VolumeArc <noreply@mail.volumearc.app>')
  assert.deepEqual(sentBody.to, ['support@mabryventures.com'])
  assert.equal(sentBody.reply_to, 'jared@example.com')
  assert.deepEqual(sentBody.tags, [
    { name: 'source', value: 'support-form' },
    { name: 'category', value: 'bug-report' },
  ])
} finally {
  await rm(tempDir, { recursive: true, force: true })
}
