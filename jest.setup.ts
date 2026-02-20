import React from 'react';
import '@testing-library/jest-dom';
import { beforeAll, beforeEach, jest } from '@jest/globals';

const mockUsePathname = jest.fn(() => '/');
const mockUseRouter = jest.fn(() => ({ push: jest.fn() }));

jest.mock('next/navigation', () => ({
  usePathname: () => mockUsePathname(),
  useRouter: () => mockUseRouter(),
}));

jest.mock('next/link', () => ({
  __esModule: true,
  default: ({ href, children, ...props }: { href: string; children: React.ReactNode }) => (
    React.createElement('a', { href, ...props }, children)
  ),
}));

Object.defineProperty(globalThis, '__mockUsePathname', {
  value: mockUsePathname,
  writable: false,
});

Object.defineProperty(globalThis, '__mockUseRouter', {
  value: mockUseRouter,
  writable: false,
});

beforeAll(() => {
  if (typeof window !== 'undefined') {
    Object.defineProperty(window, 'confirm', {
      value: jest.fn(),
      writable: true,
    });

    Object.defineProperty(window, 'alert', {
      value: jest.fn(),
      writable: true,
    });

    if (typeof navigator !== 'undefined' && !('vibrate' in navigator)) {
      Object.defineProperty(navigator, 'vibrate', {
        value: jest.fn(),
        writable: true,
      });
    }

    Object.defineProperty(URL, 'createObjectURL', {
      value: jest.fn(() => 'blob:mock'),
      writable: true,
    });

    Object.defineProperty(URL, 'revokeObjectURL', {
      value: jest.fn(),
      writable: true,
    });
  }
});

beforeEach(() => {
  if (typeof localStorage !== 'undefined') {
    localStorage.clear();
  }
  jest.clearAllMocks();
});
