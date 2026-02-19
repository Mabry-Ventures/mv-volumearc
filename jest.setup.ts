import React from 'react';
import '@testing-library/jest-dom';

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
  Object.defineProperty(window, 'confirm', {
    value: jest.fn(),
    writable: true,
  });

  Object.defineProperty(window, 'alert', {
    value: jest.fn(),
    writable: true,
  });

  if (!('vibrate' in navigator)) {
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
});

beforeEach(() => {
  localStorage.clear();
  jest.clearAllMocks();
});
