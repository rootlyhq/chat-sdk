import Link from 'next/link';

export default function HomePage() {
  return (
    <main className="flex flex-col items-center px-4">
      {/* Hero */}
      <section className="max-w-4xl w-full py-24 text-center">
        <div className="inline-flex items-center gap-2 px-3 py-1 mb-6 text-sm font-medium rounded-full bg-red-50 text-red-700 dark:bg-red-950 dark:text-red-300 border border-red-200 dark:border-red-800">
          <span className="inline-block w-2 h-2 rounded-full bg-red-500" />
          Beta — under active development
        </div>
        <h1 className="text-5xl sm:text-6xl font-bold tracking-tight mb-6">
          One SDK.<br />
          <span className="text-red-600 dark:text-red-400">Every chat platform.</span>
        </h1>
        <p className="text-lg text-muted-foreground max-w-2xl mx-auto mb-8">
          Build chat bots in Ruby that work across Slack, Teams, Google Chat, and Mattermost.
          Normalized events, cards DSL, streaming, and pluggable adapters — write once, deploy everywhere.
        </p>
        <div className="flex gap-4 justify-center">
          <Link
            href="/docs/getting-started"
            className="px-6 py-3 rounded-lg bg-red-600 text-white font-medium hover:bg-red-700 transition-colors"
          >
            Get Started
          </Link>
          <Link
            href="https://github.com/rootlyhq/chat-sdk"
            className="px-6 py-3 rounded-lg border border-gray-300 dark:border-gray-700 font-medium hover:bg-gray-50 dark:hover:bg-gray-900 transition-colors"
          >
            GitHub
          </Link>
        </div>
      </section>

      {/* Code example */}
      <section className="max-w-3xl w-full mb-20">
        <pre className="rounded-xl bg-gray-950 text-gray-100 p-6 text-sm overflow-x-auto leading-relaxed">
          <code>{`gem "chat_sdk"
gem "chat_sdk-slack"

bot = ChatSDK::Chat.new(
  user_name: "mybot",
  adapters: { slack: ChatSDK::Slack::Adapter.new },
  state: ChatSDK::State::Memory.new
)

bot.on_new_mention do |thread, message|
  thread.subscribe
  thread.post("Hello! I'm listening.")
end

bot.on_action("incident:ack") do |event|
  event.thread.post("Acknowledged ✓")
end`}</code>
        </pre>
      </section>

      {/* Features grid */}
      <section className="max-w-5xl w-full grid grid-cols-1 md:grid-cols-3 gap-6 mb-20">
        {[
          {
            title: 'Normalized Events',
            desc: 'Mentions, messages, reactions, actions, slash commands — same handler signature regardless of platform.',
          },
          {
            title: 'Cards DSL',
            desc: 'Ruby blocks instead of JSX. One card renders as Block Kit, Adaptive Cards, or Card V2 automatically.',
          },
          {
            title: 'AI Ready',
            desc: 'Convert message history to LLM format. Provider-agnostic tool definitions with approval gates.',
          },
          {
            title: 'Streaming',
            desc: 'Progressive message editing with throttled updates. Pass any Enumerable from your LLM.',
          },
          {
            title: 'Pluggable State',
            desc: 'Memory for development, Redis for production. Distributed locks, deduplication, TTL storage.',
          },
          {
            title: 'Escape Hatches',
            desc: 'Three tiers: normalized → adapter contract → raw platform client. Never locked in.',
          },
        ].map((feature) => (
          <div
            key={feature.title}
            className="p-6 rounded-xl border border-gray-200 dark:border-gray-800"
          >
            <h3 className="font-semibold mb-2">{feature.title}</h3>
            <p className="text-sm text-muted-foreground">{feature.desc}</p>
          </div>
        ))}
      </section>

      {/* Adapter logos / badges */}
      <section className="max-w-3xl w-full text-center mb-20">
        <h2 className="text-2xl font-bold mb-6">Platform Adapters</h2>
        <div className="flex flex-wrap gap-3 justify-center">
          {['Slack', 'Teams', 'Google Chat', 'Mattermost'].map((name) => (
            <span
              key={name}
              className="px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-900 text-sm font-medium"
            >
              {name}
            </span>
          ))}
          <span className="px-4 py-2 rounded-lg bg-gray-100 dark:bg-gray-900 text-sm font-medium text-muted-foreground">
            + more coming
          </span>
        </div>
      </section>

      {/* Footer CTA */}
      <section className="max-w-2xl w-full text-center pb-20">
        <p className="text-muted-foreground mb-4">
          Built by{' '}
          <a href="https://rootly.com" className="font-medium underline">
            Rootly
          </a>
          . MIT licensed. Ruby port of{' '}
          <a href="https://chat-sdk.dev" className="font-medium underline">
            chat-sdk.dev
          </a>
          .
        </p>
      </section>
    </main>
  );
}
