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

function SlackIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 16 16" width={size} height={size} fill="#fff">
      <path d="M3.362 10.11c0 .926-.756 1.681-1.681 1.681S0 11.036 0 10.111.756 8.43 1.68 8.43h1.682zm.846 0c0-.924.756-1.68 1.681-1.68s1.681.756 1.681 1.68v4.21c0 .924-.756 1.68-1.68 1.68a1.685 1.685 0 0 1-1.682-1.68zM5.89 3.362c-.926 0-1.682-.756-1.682-1.681S4.964 0 5.89 0s1.68.756 1.68 1.68v1.682zm0 .846c.924 0 1.68.756 1.68 1.681S6.814 7.57 5.89 7.57H1.68C.757 7.57 0 6.814 0 5.89c0-.926.756-1.682 1.68-1.682zm6.749 1.682c0-.926.755-1.682 1.68-1.682S16 4.964 16 5.889s-.756 1.681-1.68 1.681h-1.681zm-.848 0c0 .924-.755 1.68-1.68 1.68A1.685 1.685 0 0 1 8.43 5.89V1.68C8.43.757 9.186 0 10.11 0c.926 0 1.681.756 1.681 1.68zm-1.681 6.748c.926 0 1.682.756 1.682 1.681S11.036 16 10.11 16s-1.681-.756-1.681-1.68v-1.682h1.68zm0-.847c-.924 0-1.68-.755-1.68-1.68s.756-1.681 1.68-1.681h4.21c.924 0 1.68.756 1.68 1.68 0 .926-.756 1.681-1.68 1.681z" />
    </svg>
  );
}

function TeamsIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 16 16" width={size} height={size} fill="#fff">
      <path d="M9.186 4.797a2.42 2.42 0 1 0-2.86-2.448h1.178c.929 0 1.682.753 1.682 1.682zm-4.295 7.738h2.613c.929 0 1.682-.753 1.682-1.682V5.58h2.783a.7.7 0 0 1 .682.716v4.294a4.197 4.197 0 0 1-4.093 4.293c-1.618-.04-3-.99-3.667-2.35Zm10.737-9.372a1.674 1.674 0 1 1-3.349 0 1.674 1.674 0 0 1 3.349 0m-2.238 9.488-.12-.002a5.2 5.2 0 0 0 .381-2.07V6.306a1.7 1.7 0 0 0-.15-.725h1.792c.39 0 .707.317.707.707v3.765a2.6 2.6 0 0 1-2.598 2.598z" />
      <path d="M.682 3.349h6.822c.377 0 .682.305.682.682v6.822a.68.68 0 0 1-.682.682H.682A.68.68 0 0 1 0 10.853V4.03c0-.377.305-.682.682-.682Zm5.206 2.596v-.72h-3.59v.72h1.357V9.66h.87V5.945z" />
    </svg>
  );
}

function GChatIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M1.637 0C.733 0 0 .733 0 1.637v16.5c0 .904.733 1.636 1.637 1.636h3.955v3.323c0 .804.97 1.207 1.539.638l3.963-3.96h11.27c.903 0 1.636-.733 1.636-1.637V5.592L18.408 0Zm3.955 5.592h12.816v8.59H8.455l-2.863 2.863Z" />
    </svg>
  );
}

function MattermostIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M12.081 0C7.048-.034 2.339 3.125.637 8.153c-2.125 6.276 1.24 13.086 7.516 15.21 6.276 2.125 13.086-1.24 15.21-7.516 1.727-5.1-.172-10.552-4.311-13.557l.126 2.547c2.065 2.282 2.88 5.512 1.852 8.549-1.534 4.532-6.594 6.915-11.3 5.321-4.708-1.593-7.28-6.559-5.745-11.092 1.031-3.046 3.655-5.121 6.694-5.67l1.642-1.94A4.87 4.87 0 0 0 12.08 0zm3.528 1.094a.284.284 0 0 0-.123.024l-.004.001a.33.33 0 0 0-.109.071c-.145.142-.657.828-.657.828L13.6 3.4l-1.3 1.585-2.232 2.776s-1.024 1.278-.798 2.851c.226 1.574 1.396 2.34 2.304 2.648.907.307 2.302.408 3.438-.704 1.135-1.112 1.098-2.75 1.098-2.75l-.087-3.56-.07-2.05-.047-1.775s.01-.856-.02-1.057a.33.33 0 0 0-.035-.107l-.006-.012-.007-.011a.277.277 0 0 0-.229-.14z" />
    </svg>
  );
}

function DiscordIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03z" />
    </svg>
  );
}

function TelegramIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.479.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z" />
    </svg>
  );
}

function TwilioIcon({ size = 22 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm0 20.4a8.4 8.4 0 1 1 0-16.8 8.4 8.4 0 0 1 0 16.8zm3.6-11.4a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0zm0 6a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0zm-6 0a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0zm0-6a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0z" />
    </svg>
  );
}

function RedisIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M10.5 2.661l.54.997-1.797.644 2.409.218.748 1.246.467-1.122 2.077-.208-1.61-.618.53-1.157-1.36.652zm8.945 3.932L12 3.124 4.555 6.593 12 10.062zM3.5 18.596l8.5 4.404v-9l-8.5-4.404zm17 0v-9l-8.5 4.404v9z" />
    </svg>
  );
}

function PostgresIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M17.128 0a10.134 10.134 0 0 0-2.755.403l-.063.02A10.922 10.922 0 0 0 12.6.258C11.422.238 10.41.524 9.594 1 8.79.721 7.122.24 5.364.336 4.14.403 2.804.775 1.814 1.82.828 2.862.392 4.371.538 6.395c.04.563.36 2.31.96 4.06.302.882.675 1.79 1.15 2.545.236.376.516.727.88.99.37.265.836.4 1.296.336.39-.054.72-.244.97-.472a4.444 4.444 0 0 0 .496-.518c.09.084.18.164.276.242.261.213.565.396.896.498a2.29 2.29 0 0 0-.09.618c-.01.635.216 1.206.59 1.522.39.33.862.323 1.217.18a2.63 2.63 0 0 0 .756-.47c.123-.112.228-.222.31-.318.065.424.192.78.397 1.07.321.452.77.65 1.186.657.415.007.8-.166 1.09-.41a4.1 4.1 0 0 0 .9-1.14 8.828 8.828 0 0 0 .506-1.14c.023.187.05.37.084.546.167.888.474 1.647 1.03 2.166.557.519 1.353.74 2.287.514.85-.206 1.37-.86 1.613-1.564.244-.705.287-1.485.28-2.173a8.805 8.805 0 0 0-.083-1.117l.006-.003c.49-.24.937-.592 1.263-.97a3.56 3.56 0 0 0 .73-1.738c.082-.56.058-1.144-.132-1.678-.19-.534-.56-.993-1.066-1.32-.123-.08-.239-.142-.348-.196.396-.63.657-1.3.796-1.982.17-.83.15-1.674-.07-2.435-.217-.76-.63-1.44-1.226-1.96a5.132 5.132 0 0 0-2.283-1.19A10.343 10.343 0 0 0 17.128 0z" />
    </svg>
  );
}

function MysqlIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="#fff">
      <path d="M16.405 5.501c-.115 0-.193.014-.274.033v.013h.014c.054.104.146.18.214.273.054.107.1.214.154.32l.014-.015c.094-.066.14-.172.14-.333-.04-.047-.046-.094-.08-.14-.04-.067-.126-.1-.18-.153zM5.77 18.695h-.927a66.27 66.27 0 0 1-.454-8.852c.007-.107.007-.12.007-.12l.927.007c-.007 2.96.134 5.966.447 8.965zm1.6.12h-.774c-.4-2.96-.6-5.952-.614-8.959l.92-.007a66.353 66.353 0 0 0 .467 8.966zm7.18-12.88c.04.233.06.453.06.674.54.534.534 1.4.534 2.14 0 .366-.014.74-.04 1.106 0 .066-.007.14-.007.206-.094 1.167-.36 2.42-1.334 2.987-.154.087-.327.147-.494.167-.04.007-.087.007-.12.013h-.047c-.08 0-.153-.013-.233-.033-.6-.147-.8-.7-.867-1.254-.327.54-.754 1.007-1.247 1.354-.194.134-.407.247-.627.314-.14.04-.294.073-.44.073h-.094c-.474-.033-.674-.447-.74-.86 0-.027-.007-.054-.007-.08-.46.607-1.094 1.12-1.794 1.367a2.36 2.36 0 0 1-.46.093h-.134c-.527-.04-.72-.534-.787-1.014-.32.507-.72.954-1.2 1.307-.207.154-.447.28-.694.354a1.52 1.52 0 0 1-.394.06h-.08c-.267-.014-.48-.14-.614-.334-.194-.267-.28-.6-.327-.933l-.007-.047a65.73 65.73 0 0 1-.454-8.966l.927-.006a66.387 66.387 0 0 0 .373 8.579c.027.2.06.407.127.587.04.12.094.2.194.247.033.013.073.02.12.02.6-.1 1.207-.767 1.58-1.34.38-.58.594-1.233.68-1.894.02-.16.027-.313.027-.473v-.467c-.034-2.027-.374-4.007-.674-6.007l.887-.134c.247 1.654.527 3.307.6 4.973.034.654.027 1.32-.033 1.974a4.394 4.394 0 0 1-.187.974c.54-.5 1.007-1.08 1.347-1.727.247-.467.414-.987.467-1.52.02-.153.02-.314.02-.467v-.44c-.04-1.614-.267-3.22-.527-4.807l.887-.134c.2 1.307.387 2.62.46 3.94.033.6.04 1.2.007 1.794a4.953 4.953 0 0 1-.16 1.02c.527-.54.98-1.153 1.307-1.833.2-.42.354-.874.42-1.334a5.53 5.53 0 0 0 .06-.8c0-.193-.007-.394-.02-.587-.087-1.467-.314-2.92-.567-4.36l.887-.134c.166 1.067.326 2.147.413 3.227.047.554.074 1.114.06 1.667a5.25 5.25 0 0 1-.12 1.12c.474-.527.86-1.12 1.134-1.774.167-.407.293-.84.347-1.28.033-.294.04-.587.033-.88-.007-.154-.007-.314-.02-.467-.073-1.334-.253-2.66-.467-3.974l.9-.133z" />
    </svg>
  );
}

function MemoryIcon({ size = 20 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
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
    name: 'Discord',
    slug: 'discord',
    gem: 'chat_sdk-discord',
    type: 'platform',
    tagline: 'REST API v10 adapter with Ed25519 verification and embed rendering',
    color: '#5865F2',
    icon: <DiscordIcon />,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'no',
      reactions: 'yes', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'yes', typing: 'no',
    },
  },
  {
    name: 'Telegram',
    slug: 'telegram',
    gem: 'chat_sdk-telegram',
    type: 'platform',
    tagline: 'Bot API adapter with webhook secret token verification and inline keyboard rendering',
    color: '#26A5E4',
    icon: <TelegramIcon />,
    features: {
      post: 'yes', edit: 'yes', delete: 'yes', ephemeral: 'no',
      reactions: 'yes', files: 'yes', modals: 'no', streaming: 'yes',
      dms: 'yes', history: 'no', typing: 'yes',
    },
  },
  {
    name: 'Twilio',
    slug: 'twilio',
    gem: 'chat_sdk-twilio',
    type: 'platform',
    tagline: 'SMS/MMS adapter with HMAC-SHA1 signature verification',
    color: '#F22F46',
    icon: <TwilioIcon />,
    features: {
      post: 'yes', edit: 'no', delete: 'no', ephemeral: 'no',
      reactions: 'no', files: 'no', modals: 'no', streaming: 'no',
      dms: 'yes', history: 'no', typing: 'no',
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
    name: 'PostgreSQL',
    slug: 'state-pg',
    gem: 'chat_sdk-state-pg',
    type: 'state',
    tagline: 'Production state backend with auto-migration and JSONB storage',
    color: '#336791',
    icon: <PostgresIcon />,
    features: {},
  },
  {
    name: 'MySQL',
    slug: 'state-mysql',
    gem: 'chat_sdk-state-mysql',
    type: 'state',
    tagline: 'Production state backend with auto-migration and JSON storage',
    color: '#00758F',
    icon: <MysqlIcon />,
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
