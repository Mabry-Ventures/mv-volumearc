import type { NextAuthOptions } from 'next-auth';
import CredentialsProvider from 'next-auth/providers/credentials';

const configuredAuthSecret = process.env.AUTH_SECRET || process.env.NEXTAUTH_SECRET;
const hasConfiguredAuthSecret =
  typeof configuredAuthSecret === 'string' && configuredAuthSecret.trim().length > 0;

const resolveAuthSecret = (): string =>
  hasConfiguredAuthSecret ? (configuredAuthSecret as string) : 'beast-mode-dev-secret';

export const authOptions: NextAuthOptions = {
  secret: resolveAuthSecret(),
  session: {
    strategy: 'jwt',
    maxAge: 60 * 60 * 24 * 30,
  },
  providers: [
    CredentialsProvider({
      id: 'beast-mode-credentials',
      name: 'Beast Mode Credentials',
      credentials: {
        userId: { label: 'User ID', type: 'text' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        const userId = credentials?.userId?.trim();
        const password = credentials?.password || '';
        const expectedPassword = process.env.BEAST_MODE_ALPHA_AUTH_PASSWORD;

        if (process.env.NODE_ENV === 'production' && !hasConfiguredAuthSecret) {
          return null;
        }

        if (!userId || userId.length < 3) {
          return null;
        }

        if (expectedPassword && password !== expectedPassword) {
          return null;
        }

        // Do not allow open credential sign-in in production.
        if (!expectedPassword && process.env.NODE_ENV === 'production') {
          return null;
        }

        // Minimal alpha auth path for local dev sync rollout.
        if (!expectedPassword && password.length < 4) {
          return null;
        }

        return {
          id: userId,
          name: userId,
          email: `${userId}@local.beast`,
        };
      },
    }),
  ],
  callbacks: {
    async jwt({ token, user }) {
      if (user?.id) token.sub = user.id;
      return token;
    },
    async session({ session, token }) {
      if (session.user && token.sub) {
        session.user.id = token.sub;
      }
      return session;
    },
  },
  pages: {
    signIn: '/settings',
  },
};
