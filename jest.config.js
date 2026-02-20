const nextJest = require('next/jest');

const createJestConfig = nextJest({
  dir: './',
});

const customJestConfig = {
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
  testEnvironment: 'jsdom',
  coverageProvider: 'v8',
  collectCoverageFrom: ['src/**/*.{ts,tsx}', '!src/**/*.d.ts', '!src/**/__tests__/**'],
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '\\.(css|less|scss|sass)$': '<rootDir>/__mocks__/styleMock.js',
  },
};

module.exports = createJestConfig(customJestConfig);
