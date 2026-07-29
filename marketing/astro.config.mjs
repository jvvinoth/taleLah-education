// TaleLah marketing site — static, Cloudflare Pages ready.
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://talelah.app',
  output: 'static',
  integrations: [sitemap()],
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'ta', 'zh', 'ms'],
    routing: {
      // English at the root, mother tongues prefixed: /ta /zh /ms
      prefixDefaultLocale: false,
    },
  },
});
