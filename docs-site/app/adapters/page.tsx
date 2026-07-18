import Link from 'next/link';
import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Adapters',
  description: 'Platform and state adapters for ChatSDK Ruby',
};

type Feature = 'yes' | 'no' | 'partial';

interface Adapter {
  name: string;
  slug: string;
  gem: string;
  type: 'platform' | 'state';
  tagline: string;
  color: string;
  icon: ReactNode;
  features: Record<string, Feature>;
}

function SlackIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="#fff">
      <path d="M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zm1.271 0a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zm0 1.271a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zm10.124 2.521a2.528 2.528 0 0 1 2.52-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.52V8.834zm-1.271 0a2.528 2.528 0 0 1-2.521 2.521 2.528 2.528 0 0 1-2.521-2.521V2.522A2.528 2.528 0 0 1 15.166 0a2.528 2.528 0 0 1 2.521 2.522v6.312zm-2.521 10.124a2.528 2.528 0 0 1 2.521 2.52A2.528 2.528 0 0 1 15.166 24a2.528 2.528 0 0 1-2.521-2.522v-2.52h2.521zm0-1.271a2.528 2.528 0 0 1-2.521-2.521 2.528 2.528 0 0 1 2.521-2.521h6.312A2.528 2.528 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.521h-6.312z" />
    </svg>
  );
}

function TeamsIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="#fff">
      <path d="M20.625 8.073h-5.17V5.478a2.756 2.756 0 1 1 2.756-2.756c0 .627-.213 1.2-.567 1.66h2.98A1.354 1.354 0 0 1 22 5.737v.982a1.354 1.354 0 0 1-1.375 1.354zm-1.19 1.2H14.78v5.832a2.46 2.46 0 0 0 2.459 2.459h.33a2.46 2.46 0 0 0 2.46-2.46V9.868a.6.6 0 0 0-.594-.594zM11.2 4.26H2.4a1.2 1.2 0 0 0-1.2 1.2v9.6a1.2 1.2 0 0 0 1.2 1.2h3v3.48l3.48-3.48h2.32a1.2 1.2 0 0 0 1.2-1.2v-9.6a1.2 1.2 0 0 0-1.2-1.2zM7.8 13.14H4.2v-1.2h3.6v1.2zm1.8-2.4H4.2v-1.2h5.4v1.2zm0-2.4H4.2v-1.2h5.4v1.2z" />
    </svg>
  );
}

function GChatIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="#fff">
      <path d="M22 12c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10zm-10-6a6 6 0 1 0 0 12h4.5a1.5 1.5 0 0 0 1.5-1.5V12a6 6 0 0 0-6-6zm-2 4.5a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3zm4 0a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z" />
    </svg>
  );
}

function MattermostIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="#fff">
      <path d="M12.081.001C7.692.067 3.636 2.587 1.736 6.541c-2.8 5.821-.343 12.797 5.478 15.597a11.99 11.99 0 0 0 10.152-.3A11.97 11.97 0 0 0 23.49 12.5c.1-3.206-1.07-6.34-3.255-8.69A11.93 11.93 0 0 0 12.081.002zm.553 2.133a9.85 9.85 0 0 1 6.79 3.12 9.82 9.82 0 0 1 2.675 7.14 9.84 9.84 0 0 1-5.02 8.18 9.85 9.85 0 0 1-8.34.25C3.876 18.465 1.746 12.78 4.107 7.917a9.83 9.83 0 0 1 8.527-5.783zm-.1 2.42c-2.1.16-3.87 1.58-4.55 3.38-.2.56.51.97.89.52a12.2 12.2 0 0 1 3.53-3.03c.43-.24.55-.83.13-.87zm2.97 1.77a12.18 12.18 0 0 0-4.61 3.26c-.31.35-.06.92.41.78a12.18 12.18 0 0 0 4.37-2.64c.35-.32.15-.93-.35-.76l.18.36z" />
    </svg>
  );
}

function RedisIcon() {
  return (
    <svg viewBox="0 0 24 24" width="20" height="20" fill="#fff">
      <path d="M10.5 2.661l.54.997-1.797.644 2.409.218.748 1.246.467-1.122 2.077-.208-1.61-.618.53-1.157-1.36.652zm8.945 3.932L12 3.124 4.555 6.593 12 10.062zM3.5 18.596l8.5 4.404v-9l-8.5-4.404zm17 0v-9l-8.5 4.404v9z" />
    </svg>
  );
}

function MemoryIcon() {
  return (
    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 19v-3m4 3v-3m4 3v-3m4 3v-3" />
      <rect x="2" y="6" width="20" height="10" rx="2" />
      <path d="M6 10h0m4 0h0m4 0h0m4 0h0" />
    </svg>
  );
}

const adapters: Adapter[] = [
  {
    name: 'Slack',
    slug: 'slack',
    gem: 'chat_sdk-slack',
    type: 'platform',
    tagline: 'Full-featured adapter wrapping slack-ruby-client',
    color: '#4A154B',
    icon: <SlackIcon />,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'yes',
      reactions: 'yes', files: 'yes', modals: 'yes', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'yes',
    },
  },
  {
    name: 'Microsoft Teams',
    slug: 'teams',
    gem: 'chat_sdk-teams',
    type: 'platform',
    tagline: 'Bot Framework connector with JWT verification',
    color: '#6264A7',
    icon: <TeamsIcon />,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'no',
      reactions: 'partial', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'no',
    },
  },
  {
    name: 'Google Chat',
    slug: 'gchat',
    gem: 'chat_sdk-gchat',
    type: 'platform',
    tagline: 'Official google-apps-chat-v1 client with OIDC token verification',
    color: '#00AC47',
    icon: <GChatIcon />,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'yes',
      reactions: 'yes', files: 'no', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'no',
    },
  },
  {
    name: 'Mattermost',
    slug: 'mattermost',
    gem: 'chat_sdk-mattermost',
    type: 'platform',
    tagline: 'REST API adapter with webhook token auth',
    color: '#0058CC',
    icon: <MattermostIcon />,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'yes',
      reactions: 'yes', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'yes',
    },
  },
  {
    name: 'Redis',
    slug: 'state-redis',
    gem: 'chat_sdk-state-redis',
    type: 'state',
    tagline: 'Production state backend with Lua-guarded locks',
    color: '#DC382D',
    icon: <RedisIcon />,
    features: {},
  },
  {
    name: 'Memory',
    slug: 'state-memory',
    gem: 'chat_sdk (built-in)',
    type: 'state',
    tagline: 'In-process state for development and testing',
    color: '#6B7280',
    icon: <MemoryIcon />,
    features: {},
  },
];

const featureLabels: Record<string, string> = {
  post: 'Post', edit: 'Edit', delete: 'Delete', ephemeral: 'Ephemeral',
  reactions: 'Reactions', files: 'Files', modals: 'Modals', streaming: 'Streaming',
  dms: 'DMs', history: 'History', typing: 'Typing',
};

function FeatureBadge({ status }: { status: Feature }) {
  if (status === 'yes') return <span className="text-green-600 dark:text-green-400 font-bold">&#10003;</span>;
  if (status === 'partial') return <span className="text-yellow-600 dark:text-yellow-400 font-bold">~</span>;
  return <span className="text-gray-300 dark:text-gray-600">&#10005;</span>;
}

export default function AdaptersPage() {
  const platformAdapters = adapters.filter((a) => a.type === 'platform');
  const stateAdapters = adapters.filter((a) => a.type === 'state');

  return (
    <main className="max-w-5xl mx-auto px-6 py-16">
      <h1 className="text-4xl font-bold mb-3">Adapters</h1>
      <p className="text-lg text-gray-500 dark:text-gray-400 mb-12">
        Connect ChatSDK to your chat platforms and state backends.
      </p>

      {/* Platform adapters */}
      <h2 className="text-2xl font-bold mb-6">Platform Adapters</h2>
      <div className="grid gap-4 mb-16">
        {platformAdapters.map((adapter) => (
          <Link
            key={adapter.slug}
            href={`/docs/adapters/${adapter.slug}`}
            className="group flex items-start gap-5 p-6 rounded-2xl border border-gray-200 dark:border-gray-800 hover:border-red-500/30 dark:hover:border-red-500/30 transition-all hover:shadow-md bg-white dark:bg-gray-950"
          >
            <div
              className="w-12 h-12 rounded-xl flex items-center justify-center shrink-0"
              style={{ backgroundColor: adapter.color }}
            >
              {adapter.icon}
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-3 mb-1.5 flex-wrap">
                <h3 className="font-semibold text-lg group-hover:text-red-600 dark:group-hover:text-red-400 transition-colors">
                  {adapter.name}
                </h3>
                <code className="text-xs text-gray-400 bg-gray-100 dark:bg-gray-900 px-2 py-0.5 rounded">
                  {adapter.gem}
                </code>
              </div>
              <p className="text-sm text-gray-500 dark:text-gray-400 mb-3">{adapter.tagline}</p>
              <div className="flex flex-wrap gap-x-4 gap-y-1.5">
                {Object.entries(adapter.features).map(([key, val]) => (
                  <span key={key} className="text-xs flex items-center gap-1.5">
                    <FeatureBadge status={val} />
                    <span className="text-gray-500 dark:text-gray-400">{featureLabels[key]}</span>
                  </span>
                ))}
              </div>
            </div>
            <span className="text-gray-300 dark:text-gray-600 group-hover:text-red-500 transition-colors mt-3 text-lg">
              →
            </span>
          </Link>
        ))}
      </div>

      {/* Feature matrix */}
      <h2 className="text-2xl font-bold mb-6">Feature Matrix</h2>
      <div className="overflow-x-auto mb-16 rounded-xl border border-gray-200 dark:border-gray-800">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 dark:bg-gray-900">
              <th className="text-left py-3.5 pl-5 pr-4 font-semibold">Feature</th>
              {platformAdapters.map((a) => (
                <th key={a.slug} className="text-center py-3.5 px-4 font-semibold">
                  <div className="flex items-center justify-center gap-2">
                    <span className="w-4 h-4 rounded" style={{ backgroundColor: a.color }} />
                    <span>{a.name}</span>
                  </div>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {Object.entries(featureLabels).map(([key, label], i) => (
              <tr key={key} className={i % 2 === 0 ? 'bg-white dark:bg-gray-950' : 'bg-gray-50/50 dark:bg-gray-900/50'}>
                <td className="py-3 pl-5 pr-4 text-gray-600 dark:text-gray-400">{label}</td>
                {platformAdapters.map((a) => (
                  <td key={a.slug} className="text-center py-3 px-4">
                    <FeatureBadge status={a.features[key] || 'no'} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* State adapters */}
      <h2 className="text-2xl font-bold mb-6">State Adapters</h2>
      <div className="grid gap-4 md:grid-cols-2 mb-16">
        {stateAdapters.map((adapter) => (
          <Link
            key={adapter.slug}
            href={`/docs/adapters/${adapter.slug}`}
            className="group p-6 rounded-2xl border border-gray-200 dark:border-gray-800 hover:border-red-500/30 dark:hover:border-red-500/30 transition-all hover:shadow-md bg-white dark:bg-gray-950"
          >
            <div className="flex items-center gap-3 mb-3">
              <div
                className="w-10 h-10 rounded-lg flex items-center justify-center"
                style={{ backgroundColor: adapter.color }}
              >
                {adapter.icon}
              </div>
              <div>
                <h3 className="font-semibold group-hover:text-red-600 dark:group-hover:text-red-400 transition-colors">
                  {adapter.name}
                </h3>
                <code className="text-xs text-gray-400">{adapter.gem}</code>
              </div>
            </div>
            <p className="text-sm text-gray-500 dark:text-gray-400">{adapter.tagline}</p>
          </Link>
        ))}
      </div>

      {/* Build your own CTA */}
      <div className="rounded-2xl border border-dashed border-gray-300 dark:border-gray-700 p-8 text-center bg-gray-50/50 dark:bg-gray-900/50">
        <h3 className="font-semibold text-lg mb-2">Build your own adapter</h3>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          Extend ChatSDK with shared contract specs and the adapter base class.
        </p>
        <Link
          href="/docs/contributing/building-adapters"
          className="inline-flex items-center gap-1 text-sm font-medium text-red-600 dark:text-red-400 hover:underline"
        >
          Read the guide <span>→</span>
        </Link>
      </div>
    </main>
  );
}
