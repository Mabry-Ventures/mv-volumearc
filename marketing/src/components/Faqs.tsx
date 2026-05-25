import { Container } from '@/components/Container'

const faqs = [
  [
    {
      question: 'How is VolumeArc’s AI coach different from a chatbot?',
      answer:
        'VolumeArc’s coach runs through a structured prompt template — system persona, intent envelope, and a context block built from your readiness, recent sessions, and current program. Every prompt is regression-tested against a 20-fixture eval matrix before it ships. We publish the eval results at /quality.',
    },
    {
      question: 'Does the AI coach work offline?',
      answer:
        'Yes. On supported devices (iOS 26+ with Apple Intelligence enabled), the coach falls back to Apple’s on-device Foundation Models when the network is unavailable, so you can still get readiness-aware advice in the basement gym, on a plane, or anywhere there is no signal.',
    },
    {
      question: 'What data does VolumeArc send to its servers?',
      answer:
        'Workout history and personal information stay in your private CloudKit container — Apple holds the encryption keys, not us. The AI coach forwards a redacted prompt envelope to a Cloudflare Worker that proxies to Gemini Pro or Flash Lite. We strip personally identifying fields before any payload leaves the device. Read the full Privacy Policy for the data-flow diagram.',
    },
  ],
  [
    {
      question: 'Why is the Apple Watch experience first-class?',
      answer:
        'Most strength apps treat the Watch as a notification surface. VolumeArc runs a real HKWorkoutSession with a native rest timer, set logging, coach cues, and offline payload queueing. The Watch can run a session start-to-finish even when your phone is off.',
    },
    {
      question: 'What does Premium unlock?',
      answer:
        'Premium ($9.99/month or $79.99/year) routes the coach to Gemini Pro for deeper context handling, unlocks single-turn voice coaching, and gates priority features. Cloud sync, on-device AI, Live Activities, and the full workout tracker stay free for everyone.',
    },
    {
      question: 'Will VolumeArc come to Android or the web?',
      answer:
        'No. VolumeArc’s wedge is being the deepest Apple-ecosystem strength coach. Cross-platform tools chase breadth; VolumeArc trades breadth for depth so the Watch + Live Activities + Health integration can be best-in-class.',
    },
  ],
  [
    {
      question: 'How do you handle HealthKit data?',
      answer:
        'HealthKit reads (workouts, HRV, sleep, Workout Effort, wrist temperature, respiratory rate, heart rate, and active energy where available) feed the Readiness model and the coach prompt. Your raw HealthKit data never leaves the device. Computed summaries (e.g., "HRV down 8%") may be included in the redacted coach prompt envelope, but only with explicit permission and only when you ask the coach a question.',
    },
    {
      question: 'Can I import my workout history from another app?',
      answer:
        'Today, VolumeArc imports anything Apple Health already has — completed strength sessions logged by other apps, manual workouts, and cardio context. Direct Hevy / Strong / Fitbod imports are on the roadmap.',
    },
    {
      question: 'I have a problem or feedback. How do I reach you?',
      answer:
        'Use the in-app Send Feedback flow under Profile → Help, or email support@volumearc.com. Bug reports include redacted diagnostics so we can reproduce the issue without seeing your personal data.',
    },
  ],
]

export function Faqs() {
  return (
    <section
      id="faqs"
      aria-labelledby="faqs-title"
      className="border-t border-gray-200 py-20 sm:py-32"
    >
      <Container>
        <div className="mx-auto max-w-2xl lg:mx-0">
          <h2
            id="faqs-title"
            className="text-3xl font-medium tracking-tight text-gray-900"
          >
            Frequently asked questions
          </h2>
          <p className="mt-2 text-lg text-gray-600">
            Anything else?{' '}
            <a
              href="mailto:support@volumearc.com"
              className="font-medium text-sunrise-700 underline decoration-sunrise-300 underline-offset-4 hover:decoration-sunrise-500"
            >
              support@volumearc.com
            </a>
            .
          </p>
        </div>
        <ul
          role="list"
          className="mx-auto mt-16 grid max-w-2xl grid-cols-1 gap-8 sm:mt-20 lg:max-w-none lg:grid-cols-3"
        >
          {faqs.map((column, columnIndex) => (
            <li key={columnIndex}>
              <ul role="list" className="space-y-10">
                {column.map((faq, faqIndex) => (
                  <li key={faqIndex}>
                    <h3 className="text-lg/6 font-semibold text-gray-900">
                      {faq.question}
                    </h3>
                    <p className="mt-4 text-sm text-gray-700">{faq.answer}</p>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ul>
      </Container>
    </section>
  )
}
