import type { Metadata, Viewport } from 'next';
import { Navigation } from '@/components/Navigation';
import '@/styles/globals.css';

export const metadata: Metadata = {
  title: 'Beast Mode - Workout Tracker',
  description: 'Push your limits and achieve your fitness goals',
  manifest: '/manifest.json',
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  themeColor: '#f97316',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <main className="page container">
          {children}
        </main>
        <Navigation />
      </body>
    </html>
  );
}
