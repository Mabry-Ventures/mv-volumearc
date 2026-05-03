import nextPlugin from '@next/eslint-plugin-next'
import tseslint from 'typescript-eslint'

// ESLint 9 native flat config for Next.js 16. Replaces the legacy
// `.eslintrc.json` ("next/core-web-vitals") that shipped with the
// Tailwind Plus Pocket template — `next lint` itself is deprecated in
// Next 15+ and removed in 16, so we run ESLint directly via npm scripts.
//
// Coverage: TypeScript strict-ish defaults + Next.js core-web-vitals
// rules over `src/**`. Build output and generated files are ignored.
export default [
  {
    ignores: [
      '.next/**',
      '.vercel/**',
      'node_modules/**',
      'next-env.d.ts',
      'public/**',
    ],
  },
  ...tseslint.configs.recommended,
  {
    files: ['src/**/*.{ts,tsx}'],
    plugins: {
      '@next/next': nextPlugin,
    },
    rules: {
      ...nextPlugin.configs.recommended.rules,
      ...nextPlugin.configs['core-web-vitals'].rules,
      // Pocket-template `let` style is intentional; don't churn it into `const`
      'prefer-const': 'off',
      // Hero / PrimaryFeatures use `<a>` for anchor jumps; SF Symbols-style
      // svg elements with hardcoded width/height are intentional.
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
    },
  },
]
