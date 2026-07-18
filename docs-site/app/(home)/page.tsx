import Link from 'next/link';
import { createHighlighter } from 'shiki';

const platforms = [
  { name: 'Slack', color: 'bg-[#4A154B]' },
  { name: 'Teams', color: 'bg-[#6264A7]' },
  { name: 'Google Chat', color: 'bg-[#00AC47]' },
  { name: 'Mattermost', color: 'bg-[#0058CC]' },
];

const features = [
  {
    icon: '⚡',
    title: 'Normalized Events',
    desc: 'Mentions, messages, reactions, actions, slash commands — one handler signature across every platform.',
  },
  {
    icon: '💎',
    title: 'Cards DSL',
    desc: 'Ruby blocks that render as Slack Block Kit, Teams Adaptive Cards, or Google Chat Card V2.',
  },
  {
    icon: '🤖',
    title: 'AI Ready',
    desc: 'Convert chat history to LLM format. Provider-agnostic tool definitions with approval gates.',
  },
  {
    icon: '🌊',
    title: 'Streaming',
    desc: 'Progressive message editing with throttled updates. Pass any Enumerable from your LLM.',
  },
  {
    icon: '🔌',
    title: 'Pluggable Adapters',
    desc: 'Slack, Teams, Google Chat, Mattermost — or build your own with shared contract specs.',
  },
  {
    icon: '🔒',
    title: 'Production State',
    desc: 'Distributed locks, message dedup, TTL storage. Memory for dev, Redis for prod.',
  },
];

const codeSnippets = [
  {
    title: 'config.rb — setup',
    accent: true,
    code: `bot = ChatSDK::Chat.new(
  user_name: "rootly-bot",
  adapters: {
    slack: ChatSDK::Slack::Adapter.new,
    teams: ChatSDK::Teams::Adapter.new
  },
  state: ChatSDK::State::Redis.new
)`,
  },
  {
    title: 'handlers.rb — events',
    accent: false,
    code: `bot.on_new_mention do |thread, message|
  thread.subscribe
  thread.post("Hello! I'm listening.")
end`,
  },
  {
    title: 'cards.rb — rich messages',
    accent: false,
    code: `thread.post(ChatSDK.card(title: "Incident #4821") do
  text "Database CPU at 98%"
  fields do
    field "Service", "postgres-primary"
    field "On-call", "@quentin"
  end
  actions do
    button "Ack", id: "incident:ack", style: :primary
    button "Resolve", id: "incident:resolve", style: :danger
  end
end)`,
  },
  {
    title: 'ai.rb — LLM integration',
    accent: false,
    code: `# Convert chat history → LLM messages
ai_msgs = ChatSDK::AI.to_ai_messages(thread.messages)

# Stream LLM response back to chat
thread.post_ai_stream(llm.chat(ai_msgs))`,
  },
];

async function getHighlighter() {
  return createHighlighter({
    themes: ['github-dark'],
    langs: ['ruby'],
  });
}

export default async function HomePage() {
  const highlighter = await getHighlighter();

  const highlighted = codeSnippets.map((s) => ({
    ...s,
    html: highlighter.codeToHtml(s.code, { lang: 'ruby', theme: 'github-dark' }),
  }));

  return (
    <main className="flex flex-col items-center">
      {/* Hero */}
      <section className="relative w-full overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-red-50/50 via-transparent to-transparent dark:from-red-950/20 dark:via-transparent" />
        <div className="relative max-w-5xl mx-auto px-6 pt-28 pb-20 text-center">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 mb-8 text-xs font-medium rounded-full bg-red-500/10 text-red-600 dark:text-red-400 border border-red-500/20">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
              <span className="relative inline-flex rounded-full h-2 w-2 bg-red-500" />
            </span>
            Beta — under active development
          </div>

          <h1 className="text-5xl sm:text-7xl font-extrabold tracking-tight mb-6 bg-gradient-to-br from-gray-900 via-gray-800 to-gray-600 dark:from-white dark:via-gray-200 dark:to-gray-400 bg-clip-text text-transparent">
            Chat SDK for Ruby
          </h1>

          <p className="text-xl text-gray-600 dark:text-gray-400 max-w-2xl mx-auto mb-10 leading-relaxed">
            Build bots that work across every chat platform.
            One API, normalized events, cards DSL, streaming — write once, deploy to Slack, Teams, Google Chat, and more.
          </p>

          <div className="flex gap-4 justify-center mb-16">
            <Link
              href="/docs/getting-started"
              className="group px-7 py-3.5 rounded-xl bg-red-600 text-white font-semibold hover:bg-red-700 transition-all shadow-lg shadow-red-500/25 hover:shadow-red-500/40"
            >
              Get Started
              <span className="inline-block ml-1 transition-transform group-hover:translate-x-0.5">→</span>
            </Link>
            <Link
              href="https://github.com/rootlyhq/chat-sdk"
              className="px-7 py-3.5 rounded-xl border border-gray-300 dark:border-gray-700 font-semibold hover:bg-gray-50 dark:hover:bg-gray-900 transition-colors"
            >
              GitHub
            </Link>
          </div>

          {/* Platform pills */}
          <div className="flex flex-wrap gap-3 justify-center">
            {platforms.map((p) => (
              <div
                key={p.name}
                className="flex items-center gap-2.5 px-4 py-2 rounded-full bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 shadow-sm"
              >
                <span className={`w-2.5 h-2.5 rounded-full ${p.color}`} />
                <span className="text-sm font-medium">{p.name}</span>
              </div>
            ))}
            <div className="flex items-center gap-2.5 px-4 py-2 rounded-full bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 shadow-sm text-gray-400">
              <span className="text-sm">+ more adapters</span>
            </div>
          </div>
        </div>
      </section>

      {/* Code examples — stacked */}
      <section className="max-w-4xl w-full px-6 mb-24">
        <div className="grid gap-6 md:grid-cols-2">
          <div className="space-y-6">
            {highlighted.slice(0, 2).map((s) => (
              <CodeBlock key={s.title} title={s.title} html={s.html} accent={s.accent} />
            ))}
          </div>
          <div className="space-y-6">
            {highlighted.slice(2, 4).map((s) => (
              <CodeBlock key={s.title} title={s.title} html={s.html} accent={s.accent} />
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="max-w-5xl w-full px-6 mb-24">
        <h2 className="text-3xl font-bold text-center mb-4">Everything you need</h2>
        <p className="text-center text-gray-500 dark:text-gray-400 mb-12 max-w-xl mx-auto">
          A complete framework for multi-platform chat bots — from webhook ingestion to LLM streaming.
        </p>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {features.map((f) => (
            <div
              key={f.title}
              className="group p-6 rounded-2xl border border-gray-200 dark:border-gray-800 hover:border-red-500/30 dark:hover:border-red-500/30 transition-colors bg-white dark:bg-gray-950"
            >
              <span className="text-2xl mb-3 block">{f.icon}</span>
              <h3 className="font-semibold mb-1.5">{f.title}</h3>
              <p className="text-sm text-gray-500 dark:text-gray-400 leading-relaxed">{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Escape hatches */}
      <section className="max-w-4xl w-full px-6 mb-24">
        <div className="rounded-2xl border border-gray-200 dark:border-gray-800 overflow-hidden">
          <div className="p-8 bg-gradient-to-br from-gray-50 to-white dark:from-gray-900 dark:to-gray-950">
            <h2 className="text-2xl font-bold mb-3">Three tiers of control</h2>
            <p className="text-gray-500 dark:text-gray-400 mb-6">Use the normalized API or drop down when you need platform-specific access.</p>
            <div className="grid md:grid-cols-3 gap-4">
              {[
                { tier: '1', label: 'Normalized', code: 'thread.post("hello")', desc: 'Cross-platform, zero config' },
                { tier: '2', label: 'Adapter', code: 'bot.adapter(:slack).post_message(...)', desc: 'Platform-aware, still normalized format' },
                { tier: '3', label: 'Raw Client', code: 'bot.adapter(:slack).client.chat_postMessage(...)', desc: 'Full native API access' },
              ].map((t) => (
                <div key={t.tier} className="p-4 rounded-xl bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="w-6 h-6 rounded-full bg-red-500/10 text-red-600 dark:text-red-400 text-xs font-bold flex items-center justify-center">{t.tier}</span>
                    <span className="font-semibold text-sm">{t.label}</span>
                  </div>
                  <code className="text-xs text-gray-600 dark:text-gray-400 block mb-2 font-mono">{t.code}</code>
                  <p className="text-xs text-gray-400">{t.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Install CTA */}
      <section className="max-w-3xl w-full px-6 mb-24 text-center">
        <h2 className="text-3xl font-bold mb-4">Start building</h2>
        <p className="text-gray-500 dark:text-gray-400 mb-8">Add to your Gemfile and go.</p>
        <div className="inline-block rounded-xl bg-gray-950 text-gray-100 px-8 py-4 text-left font-mono text-sm mb-8">
          <span className="text-gray-500">$</span> gem install chat_sdk chat_sdk-slack
        </div>
        <div className="flex gap-4 justify-center">
          <Link
            href="/docs/getting-started"
            className="px-6 py-3 rounded-xl bg-red-600 text-white font-semibold hover:bg-red-700 transition-all"
          >
            Read the docs
          </Link>
          <Link
            href="https://rubygems.org/gems/chat_sdk"
            className="px-6 py-3 rounded-xl border border-gray-300 dark:border-gray-700 font-semibold hover:bg-gray-50 dark:hover:bg-gray-900 transition-colors"
          >
            RubyGems
          </Link>
        </div>
      </section>

      {/* Footer */}
      <footer className="w-full border-t border-gray-200 dark:border-gray-800 py-8 text-center text-sm text-gray-400">
        Built by{' '}
        <a href="https://rootly.com" className="font-medium text-gray-600 dark:text-gray-300 hover:underline">
          Rootly
        </a>
        {' · '}MIT Licensed{' · '}
        Ruby port of{' '}
        <a href="https://chat-sdk.dev" className="font-medium text-gray-600 dark:text-gray-300 hover:underline">
          chat-sdk.dev
        </a>
      </footer>
    </main>
  );
}

function CodeBlock({ title, html, accent = false }: { title: string; html: string; accent?: boolean }) {
  return (
    <div className={`rounded-2xl overflow-hidden ${accent ? 'ring-1 ring-red-500/20' : 'ring-1 ring-gray-200 dark:ring-gray-800'}`}>
      <div className="flex items-center gap-2 px-4 py-2.5 bg-gray-100 dark:bg-gray-900 border-b border-gray-200 dark:border-gray-800">
        <div className="flex gap-1.5">
          <span className="w-3 h-3 rounded-full bg-red-400/80" />
          <span className="w-3 h-3 rounded-full bg-yellow-400/80" />
          <span className="w-3 h-3 rounded-full bg-green-400/80" />
        </div>
        <span className="text-xs text-gray-500 dark:text-gray-400 ml-2 font-mono">{title}</span>
      </div>
      <div
        className="[&_pre]:!bg-gray-950 [&_pre]:!p-5 [&_pre]:!m-0 [&_pre]:text-[13px] [&_pre]:leading-relaxed [&_pre]:overflow-x-auto [&_code]:!bg-transparent"
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </div>
  );
}
