import type { Metadata } from 'next';
import { Navigation } from '@/components/Navigation';
import '@/styles/globals.css';

export const metadata: Metadata = {
  title: 'Beast Mode - Workout Tracker',
  description: 'Push your limits and achieve your fitness goals',
  manifest: '/manifest.json',
  themeColor: '#f97316',
  viewport: 'width=device-width, initial-scale=1, maximum-scale=1',
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
