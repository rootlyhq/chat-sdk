import Link from 'next/link';
import type { Metadata } from 'next';

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
  features: Record<string, Feature>;
}

const adapters: Adapter[] = [
  {
    name: 'Slack',
    slug: 'slack',
    gem: 'chat_sdk-slack',
    type: 'platform',
    tagline: 'Full-featured adapter wrapping slack-ruby-client',
    color: '#4A154B',
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
    features: {},
  },
  {
    name: 'Memory',
    slug: 'state-memory',
    gem: 'chat_sdk (built-in)',
    type: 'state',
    tagline: 'In-process state for development and testing',
    color: '#6B7280',
    features: {},
  },
];

const featureLabels: Record<string, string> = {
  post: 'Post', edit: 'Edit', delete: 'Delete', ephemeral: 'Ephemeral',
  reactions: 'Reactions', files: 'Files', modals: 'Modals', streaming: 'Streaming',
  dms: 'DMs', history: 'History', typing: 'Typing',
};

function FeatureBadge({ status }: { status: Feature }) {
  if (status === 'yes') return <span className="text-green-600 dark:text-green-400">&#10003;</span>;
  if (status === 'partial') return <span className="text-yellow-600 dark:text-yellow-400">~</span>;
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
      <div className="grid gap-4 mb-12">
        {platformAdapters.map((adapter) => (
          <Link
            key={adapter.slug}
            href={`/docs/adapters/${adapter.slug}`}
            className="group flex items-start gap-5 p-5 rounded-xl border border-gray-200 dark:border-gray-800 hover:border-red-500/30 dark:hover:border-red-500/30 transition-colors bg-white dark:bg-gray-950"
          >
            <div
              className="w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold text-sm shrink-0 mt-0.5"
              style={{ backgroundColor: adapter.color }}
            >
              {adapter.name[0]}
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-3 mb-1">
                <h3 className="font-semibold group-hover:text-red-600 dark:group-hover:text-red-400 transition-colors">
                  {adapter.name}
                </h3>
                <code className="text-xs text-gray-400 bg-gray-100 dark:bg-gray-900 px-2 py-0.5 rounded">
                  {adapter.gem}
                </code>
              </div>
              <p className="text-sm text-gray-500 dark:text-gray-400 mb-3">{adapter.tagline}</p>
              <div className="flex flex-wrap gap-x-4 gap-y-1">
                {Object.entries(adapter.features).map(([key, val]) => (
                  <span key={key} className="text-xs flex items-center gap-1">
                    <FeatureBadge status={val} />
                    <span className="text-gray-500 dark:text-gray-400">{featureLabels[key]}</span>
                  </span>
                ))}
              </div>
            </div>
            <span className="text-gray-300 dark:text-gray-600 group-hover:text-red-500 transition-colors mt-2">
              →
            </span>
          </Link>
        ))}
      </div>

      {/* Feature matrix */}
      <h2 className="text-2xl font-bold mb-6">Feature Matrix</h2>
      <div className="overflow-x-auto mb-12">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-200 dark:border-gray-800">
              <th className="text-left py-3 pr-4 font-semibold">Feature</th>
              {platformAdapters.map((a) => (
                <th key={a.slug} className="text-center py-3 px-3 font-semibold">{a.name}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {Object.entries(featureLabels).map(([key, label]) => (
              <tr key={key} className="border-b border-gray-100 dark:border-gray-900">
                <td className="py-2.5 pr-4 text-gray-600 dark:text-gray-400">{label}</td>
                {platformAdapters.map((a) => (
                  <td key={a.slug} className="text-center py-2.5 px-3">
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
      <div className="grid gap-4 md:grid-cols-2 mb-12">
        {stateAdapters.map((adapter) => (
          <Link
            key={adapter.slug}
            href={`/docs/adapters/${adapter.slug}`}
            className="group p-5 rounded-xl border border-gray-200 dark:border-gray-800 hover:border-red-500/30 dark:hover:border-red-500/30 transition-colors bg-white dark:bg-gray-950"
          >
            <div className="flex items-center gap-3 mb-2">
              <div
                className="w-8 h-8 rounded-lg flex items-center justify-center text-white font-bold text-xs"
                style={{ backgroundColor: adapter.color }}
              >
                {adapter.name[0]}
              </div>
              <h3 className="font-semibold group-hover:text-red-600 dark:group-hover:text-red-400 transition-colors">
                {adapter.name}
              </h3>
            </div>
            <p className="text-sm text-gray-500 dark:text-gray-400 mb-2">{adapter.tagline}</p>
            <code className="text-xs text-gray-400 bg-gray-100 dark:bg-gray-900 px-2 py-0.5 rounded">
              {adapter.gem}
            </code>
          </Link>
        ))}
      </div>

      {/* Build your own CTA */}
      <div className="rounded-xl border border-dashed border-gray-300 dark:border-gray-700 p-8 text-center">
        <h3 className="font-semibold mb-2">Build your own adapter</h3>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          Extend ChatSDK with shared contract specs and the adapter base class.
        </p>
        <Link
          href="/docs/contributing/building-adapters"
          className="text-sm font-medium text-red-600 dark:text-red-400 hover:underline"
        >
          Read the guide →
        </Link>
      </div>
    </main>
  );
}
