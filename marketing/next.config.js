/** @type {import('next').NextConfig} */
const appStoreUrl = 'https://apps.apple.com/app/volumearc'

const nextConfig = {
  async redirects() {
    return [
      {
        source: '/app',
        destination: appStoreUrl,
        permanent: false,
      },
      {
        source: '/download',
        destination: appStoreUrl,
        permanent: false,
      },
    ]
  },
}

module.exports = nextConfig
