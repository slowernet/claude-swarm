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

# The prose files hold non-ASCII marks, so read them as UTF-8 whatever the
# shell locale says; a C locale would otherwise turn each scan into a byte error.
def read_utf8(rel)
  File.read(File.join(ROOT, rel), encoding: 'UTF-8')
end

SKILL  = read_utf8('SKILL.md')
TPL    = read_utf8('references/templates.md')
ENTRY  = read_utf8('references/entry.md')
EX     = read_utf8('references/example.md')
README = read_utf8('README.md')

fails = []
check = ->(ok, msg) { fails << msg unless ok }

# Slots an instantiator is expected to fill. A new one must be added here
# deliberately, which is the point: an unbound slot is how a template starts
# asking for something no phase produces.
SLOTS = [
  '{command}', '{conventions entry id}',
  '{correctness and regressions | security and edge cases}',
  '{decision entry ids}', '{diff file path}', '{entry ids with paths}',
  '{files}', '{id}', '{list}', '{name}',
  '{none | message your plan and stop until the lead replies}',
  '{one-line task statement}',
  '{paths}', '{skill-path}', '{slug}', '{spec path}', '{task-id}',
  '{the question}'
].freeze
ANGLES = ['<agent-name>', '<base ref from plan.md>', '<n>', '<slug>'].freeze

# 1. No undeclared placeholder in the templates or the entry format.
{ 'templates.md' => TPL, 'entry.md' => ENTRY }.each do |name, text|
  loose = text.scan(/\{[^{}\n]+\}/).uniq - SLOTS
  check.call(loose.empty?, "#{name}: undeclared slot(s) #{loose.sort}")
end

# 2. No undeclared angle placeholder in the playbook.
undeclared = SKILL.scan(/<[a-z][^<>\n]*>/).uniq - ANGLES
check.call(undeclared.empty?,
           "SKILL.md: undeclared placeholder(s) #{undeclared.sort}")

# 3. Every prompt template the playbook sends an agent to actually exists.
headings = TPL.scan(/^## (.+?) prompt$/).flatten
%w[Scout Worker Integrator Reviewer].push('Plan reviewer').each do |role|
  check.call(headings.include?(role), "templates.md: no '## #{role} prompt' heading")
end

# 4. Nothing created inside a conditional phase is depended on outside it.
phase = nil
SKILL.each_line do |line|
  phase = Regexp.last_match(1) if line =~ /^### (.+)$/
  next unless line =~ %r{> (\.claude/swarm/[^\s`]+)}

  path = Regexp.last_match(1)
  next unless phase&.downcase&.match?(/skip|only when/)

  fails << "SKILL.md: #{path} is created in a conditional phase " \
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
%w[Plan Scout Gate Work Merge Review].each do |ph|
  check.call(README.include?(ph), "README.md: phase #{ph} missing from the flow")
end

# 8. The model policy agrees between the playbook and the README: the worker
# tier is stated relative to the lead's, never pinned to a named model, so
# neither file goes stale when the user picks a different model.
{ 'SKILL.md' => SKILL, 'README.md' => README }.each do |name, text|
  check.call(text.include?('one tier below'),
             "#{name}: model policy missing the relative rule 'one tier below'")
  pinned = text.lines.select { |l| l.match?(/opus/i) && l.match?(/worker/i) }
  check.call(pinned.empty?,
             "#{name}: worker tier pinned to a named model, not a relative rule")
end

# 9. The worked example walks the same phases as the playbook. Its headings
# carry the example's own wording, which is plural where the playbook's is
# not ("Scouts" for the Scout phase).
ex_phases = EX.scan(/^## (.+)$/).flatten
%w[Plan Scouts Gate Work Merge Review].each do |ph|
  check.call(ex_phases.include?(ph),
             "example.md: no '## #{ph}' heading for the #{ph} phase")
end

fails.each { |f| puts "FAIL: #{f}" }
puts(fails.empty? ? "\nall checks pass" : "\n#{fails.size} failure(s)")
exit(fails.empty? ? 0 : 1)
