#!/usr/bin/env ruby
# frozen_string_literal: true

# Mechanical consistency checks across SKILL.md, README.md, and references/.
#
# This is not a test suite; the real check is a live run (see CLAUDE.md). These
# catch only the class of defect that comes from editing one file and not its
# pair: dangling references, unbound slots, drifted vocabulary.
#
# Usage: ruby scripts/check-consistency.rb

ROOT = File.expand_path('..', __dir__)
SKILL  = File.read(File.join(ROOT, 'SKILL.md'))
TPL    = File.read(File.join(ROOT, 'references/templates.md'))
EX     = File.read(File.join(ROOT, 'references/example.md'))
README = File.read(File.join(ROOT, 'README.md'))

fails = []
check = ->(ok, msg) { fails << msg unless ok }

# Slots an instantiator is expected to fill. A new one must be added here
# deliberately, which is the point: an unbound slot is how a template starts
# asking for something no phase produces.
SLOTS = [
  '{command}', '{conventions entry id}',
  '{correctness and regressions | security and edge cases}',
  '{decision entry ids}', '{diff file path}', '{entry ids with paths}',
  '{files}', '{id}', '{list}', '{name}', '{one-line task statement}',
  '{paths}', '{skill-path}', '{slug}', '{spec path}', '{task-id}',
  '{the question}'
].freeze
ANGLES = ['<agent-name>', '<base ref from plan.md>', '<n>', '<slug>'].freeze

# 1. No undeclared placeholder in the templates.
undeclared = TPL.scan(/\{[^{}\n]+\}/).uniq - SLOTS
check.call(undeclared.empty?,
           "templates.md: undeclared slot(s) #{undeclared.sort}")

# 2. No undeclared angle placeholder in the playbook.
undeclared = SKILL.scan(/<[a-z][^<>\n]*>/).uniq - ANGLES
check.call(undeclared.empty?,
           "SKILL.md: undeclared placeholder(s) #{undeclared.sort}")

# 3. Every prompt template the playbook sends an agent to actually exists.
headings = TPL.scan(/^## (.+?) prompt$/).flatten
%w[Scout Worker Integrator Reviewer].push('Plan reviewer').each do |role|
  check.call(headings.include?(role), "templates.md: no '## #{role} prompt' heading")
end

# 4. Nothing created inside a skippable phase is depended on outside it.
phase = nil
SKILL.each_line do |line|
  phase = Regexp.last_match(1) if line =~ /^### (.+)$/
  next unless line =~ %r{> (\.claude/swarm/[^\s`]+)}

  path = Regexp.last_match(1)
  next unless phase&.downcase&.include?('skip')

  fails << "SKILL.md: #{path} is created in a skippable phase " \
           "(#{phase.inspect}) but read elsewhere"
end

# 5. Entry ids in the worked example obey the agent-namespaced rule.
EX.scan(/`((?:lead|scout|worker|integrator)[a-z0-9-]*)`/).flatten.each do |eid|
  check.call(eid.match?(/\A(lead|(?:scout|worker)-\d+)-\d+\z/),
             "example.md: `#{eid}` is not <agent>-<n>")
end

# 6. Shared vocabulary has not drifted between the files that use it.
%w[DONE_WITH_CONCERNS NEEDS_CONTEXT BLOCKED].each do |word|
  check.call(SKILL.include?(word) && TPL.include?(word),
             "status #{word} missing from a file")
end
{ 'REVISE-PLAN' => [SKILL, TPL, EX],
  'RETURN-TO-WORKERS' => [TPL, EX] }.each do |verdict, files|
  check.call(files.all? { |f| f.include?(verdict) },
             "verdict #{verdict} missing from a file")
end

# 7. The playbook's phase list and the README's flow agree.
%w[Plan Scout Gate Work Integrate Review].each do |ph|
  check.call(README.include?(ph), "README.md: phase #{ph} missing from the flow")
end

fails.each { |f| puts "FAIL: #{f}" }
puts(fails.empty? ? "\nall checks pass" : "\n#{fails.size} failure(s)")
exit(fails.empty? ? 0 : 1)
