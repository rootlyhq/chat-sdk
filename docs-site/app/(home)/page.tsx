import Link from 'next/link';
import { createHighlighter } from 'shiki';

const platforms = [
  {
    name: 'Slack', color: '#4A154B',
    icon: <svg viewBox="0 0 16 16" width="14" height="14" fill="#fff"><path d="M3.362 10.11c0 .926-.756 1.681-1.681 1.681S0 11.036 0 10.111.756 8.43 1.68 8.43h1.682zm.846 0c0-.924.756-1.68 1.681-1.68s1.681.756 1.681 1.68v4.21c0 .924-.756 1.68-1.68 1.68a1.685 1.685 0 0 1-1.682-1.68zM5.89 3.362c-.926 0-1.682-.756-1.682-1.681S4.964 0 5.89 0s1.68.756 1.68 1.68v1.682zm0 .846c.924 0 1.68.756 1.68 1.681S6.814 7.57 5.89 7.57H1.68C.757 7.57 0 6.814 0 5.89c0-.926.756-1.682 1.68-1.682zm6.749 1.682c0-.926.755-1.682 1.68-1.682S16 4.964 16 5.889s-.756 1.681-1.68 1.681h-1.681zm-.848 0c0 .924-.755 1.68-1.68 1.68A1.685 1.685 0 0 1 8.43 5.89V1.68C8.43.757 9.186 0 10.11 0c.926 0 1.681.756 1.681 1.68zm-1.681 6.748c.926 0 1.682.756 1.682 1.681S11.036 16 10.11 16s-1.681-.756-1.681-1.68v-1.682h1.68zm0-.847c-.924 0-1.68-.755-1.68-1.68s.756-1.681 1.68-1.681h4.21c.924 0 1.68.756 1.68 1.68 0 .926-.756 1.681-1.68 1.681z"/></svg>,
  },
  {
    name: 'Teams', color: '#6264A7',
    icon: <svg viewBox="0 0 16 16" width="14" height="14" fill="#fff"><path d="M9.186 4.797a2.42 2.42 0 1 0-2.86-2.448h1.178c.929 0 1.682.753 1.682 1.682zm-4.295 7.738h2.613c.929 0 1.682-.753 1.682-1.682V5.58h2.783a.7.7 0 0 1 .682.716v4.294a4.197 4.197 0 0 1-4.093 4.293c-1.618-.04-3-.99-3.667-2.35Zm10.737-9.372a1.674 1.674 0 1 1-3.349 0 1.674 1.674 0 0 1 3.349 0m-2.238 9.488-.12-.002a5.2 5.2 0 0 0 .381-2.07V6.306a1.7 1.7 0 0 0-.15-.725h1.792c.39 0 .707.317.707.707v3.765a2.6 2.6 0 0 1-2.598 2.598z"/><path d="M.682 3.349h6.822c.377 0 .682.305.682.682v6.822a.68.68 0 0 1-.682.682H.682A.68.68 0 0 1 0 10.853V4.03c0-.377.305-.682.682-.682Zm5.206 2.596v-.72h-3.59v.72h1.357V9.66h.87V5.945z"/></svg>,
  },
  {
    name: 'Google Chat', color: '#00AC47',
    icon: <svg viewBox="0 0 24 24" width="14" height="14" fill="#fff"><path d="M1.637 0C.733 0 0 .733 0 1.637v16.5c0 .904.733 1.636 1.637 1.636h3.955v3.323c0 .804.97 1.207 1.539.638l3.963-3.96h11.27c.903 0 1.636-.733 1.636-1.637V5.592L18.408 0Zm3.955 5.592h12.816v8.59H8.455l-2.863 2.863Z"/></svg>,
  },
  {
    name: 'Mattermost', color: '#0058CC',
    icon: <svg viewBox="0 0 24 24" width="14" height="14" fill="#fff"><path d="M12.081 0C7.048-.034 2.339 3.125.637 8.153c-2.125 6.276 1.24 13.086 7.516 15.21 6.276 2.125 13.086-1.24 15.21-7.516 1.727-5.1-.172-10.552-4.311-13.557l.126 2.547c2.065 2.282 2.88 5.512 1.852 8.549-1.534 4.532-6.594 6.915-11.3 5.321-4.708-1.593-7.28-6.559-5.745-11.092 1.031-3.046 3.655-5.121 6.694-5.67l1.642-1.94A4.87 4.87 0 0 0 12.08 0zm3.528 1.094a.284.284 0 0 0-.123.024l-.004.001a.33.33 0 0 0-.109.071c-.145.142-.657.828-.657.828L13.6 3.4l-1.3 1.585-2.232 2.776s-1.024 1.278-.798 2.851c.226 1.574 1.396 2.34 2.304 2.648.907.307 2.302.408 3.438-.704 1.135-1.112 1.098-2.75 1.098-2.75l-.087-3.56-.07-2.05-.047-1.775s.01-.856-.02-1.057a.33.33 0 0 0-.035-.107l-.006-.012-.007-.011a.277.277 0 0 0-.229-.14z"/></svg>,
  },
];

const features = [
  {
    icon: '⚡',
    title: 'Normalized Events',
    desc: 'Mentions, messages, reactions, actions, slash commands — one handler signature across every platform.',
    href: '/docs/handling-events',
  },
  {
    icon: '💎',
    title: 'Cards DSL',
    desc: 'Ruby blocks that render as Slack Block Kit, Teams Adaptive Cards, or Google Chat Card V2.',
    href: '/docs/cards',
  },
  {
    icon: '🤖',
    title: 'AI Ready',
    desc: 'Convert chat history to LLM format. Provider-agnostic tool definitions with approval gates.',
    href: '/docs/ai',
  },
  {
    icon: '🌊',
    title: 'Streaming',
    desc: 'Progressive message editing with throttled updates. Pass any Enumerable from your LLM.',
    href: '/docs/streaming',
  },
  {
    icon: '🔌',
    title: 'Pluggable Adapters',
    desc: 'Slack, Teams, Google Chat, Mattermost — or build your own with shared contract specs.',
    href: '/adapters',
  },
  {
    icon: '🔒',
    title: 'Production State',
    desc: 'Distributed locks, message dedup, TTL storage. Memory for dev, Redis for prod.',
    href: '/docs/state-adapters',
  },
];

const codeSnippets = [
  {
    title: 'setup.rb',
    accent: true,
    code: `bot = ChatSDK::Chat.new(
  user_name: "my-bot",
  adapters: {
    slack: ChatSDK::Slack::Adapter.new,
    teams: ChatSDK::Teams::Adapter.new
  },
  state: ChatSDK::State::Redis.new
)`,
  },
  {
    title: 'events.rb',
    accent: false,
    code: `bot.on_new_mention do |thread, message|
  thread.subscribe
  thread.post("Hi #{message.author.name}!")
end

bot.on_reaction(%w[thumbsup]) do |event|
  event.thread.post("Thanks for the reaction!")
end

bot.on_slash_command("/weather") do |event|
  forecast = Weather.fetch(event.text)
  event.respond(forecast)
end`,
  },
  {
    title: 'cards.rb',
    accent: false,
    code: `thread.post(ChatSDK.card(title: "Deploy v2.1.0") do
  text "Ready to ship to production"
  fields do
    field "Branch", "main"
    field "Author", "@alice"
  end
  actions do
    button "Approve", id: "deploy:approve", style: :primary
    button "Cancel", id: "deploy:cancel", style: :danger
    link_button "View diff", url: "https://github.com/..."
  end
end)`,
  },
  {
    title: 'ai.rb',
    accent: false,
    code: `bot.on_new_mention do |thread, message|
  # Fetch conversation history
  history = ChatSDK::AI.to_ai_messages(thread.messages)

  # Stream any LLM response back to chat
  response = MyLLM.stream(messages: history)
  thread.post_ai_stream(response)
end`,
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
                <span className="w-6 h-6 rounded-full flex items-center justify-center" style={{ backgroundColor: p.color }}>
                  {p.icon}
                </span>
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
            <Link
              key={f.title}
              href={f.href}
              className="group p-6 rounded-2xl border border-gray-200 dark:border-gray-800 hover:border-red-500/30 dark:hover:border-red-500/30 transition-colors bg-white dark:bg-gray-950"
            >
              <span className="text-2xl mb-3 block">{f.icon}</span>
              <h3 className="font-semibold mb-1.5 group-hover:text-red-600 dark:group-hover:text-red-400 transition-colors">{f.title}</h3>
              <p className="text-sm text-gray-500 dark:text-gray-400 leading-relaxed">{f.desc}</p>
            </Link>
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
                { tier: '2', label: 'Adapter', code: 'adapter.post_message(...)', desc: 'Platform-aware, normalized format' },
                { tier: '3', label: 'Raw Client', code: 'client.chat_postMessage(...)', desc: 'Full native API access' },
              ].map((t) => (
                <div key={t.tier} className="p-4 rounded-xl bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-800 overflow-hidden">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="w-6 h-6 rounded-full bg-red-500/10 text-red-600 dark:text-red-400 text-xs font-bold flex items-center justify-center shrink-0">{t.tier}</span>
                    <span className="font-semibold text-sm">{t.label}</span>
                  </div>
                  <code className="text-xs text-gray-600 dark:text-gray-400 block mb-2 font-mono truncate">{t.code}</code>
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
        Inspired by{' '}
        <a href="https://chat-sdk.dev" className="font-medium text-gray-600 dark:text-gray-300 hover:underline">
          Vercel&apos;s Chat SDK
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
