# frozen_string_literal: true

require "rspec/core/rake_task"

GEMS = %w[chat_sdk chat_sdk-slack chat_sdk-teams chat_sdk-gchat chat_sdk-mattermost chat_sdk-state-redis].freeze

GEMS.each do |gem_dir|
  namespace gem_dir.tr("-", "_") do
    RSpec::Core::RakeTask.new(:spec) do |t|
      t.pattern = "#{gem_dir}/spec/**/*_spec.rb"
    end
  end
end

namespace :integration do
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = "chat_sdk/spec/integration/**/*_spec.rb"
  end
end

desc "Run all specs"
task :spec do
  GEMS.each do |gem_dir|
    sh "bundle exec rspec #{gem_dir}/spec" if Dir.exist?("#{gem_dir}/spec")
  end
end

desc "Run integration specs"
task integration: "integration:spec"

desc "Run all specs including integration"
task all: %i[spec integration]

task default: :spec
