import type { BaseLayoutProps } from 'fumadocs-ui/layouts/shared';
import { appName, gitConfig } from './shared';

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: `💎 ${appName}`,
    },
    links: [
      { text: 'Docs', url: '/docs' },
      { text: 'API', url: '/docs/api/chat' },
      { text: 'Adapters', url: '/adapters' },
      { text: 'Examples', url: '/docs/examples' },
      { text: 'RubyDoc', url: 'https://rubydoc.info/gems/chat_sdk', external: true },
    ],
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
  };
}
