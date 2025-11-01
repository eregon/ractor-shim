# Based on https://github.com/truffleruby/truffleruby/blob/master/spec/truffle/methods_spec.rb

# How to regenerate files:
#
# - switch to MRI, the version we are compatible with
# - run `jt -u ruby test spec/truffle/methods_spec.rb`

# jt test and jt tag can be used as normal,
# but instead of jt untag, jt purge must be used to remove tags:
# $ jt purge spec/truffle/methods_spec.rb

# socket modules are found with:
# m1=ObjectSpace.each_object(Module).to_a; require "socket"; m2=ObjectSpace.each_object(Module).to_a; p m2-m1

modules = %w[
  Ractor Ractor.singleton_class
  Ractor::Port Ractor::Port.singleton_class
]

def ruby(code, *flags)
  IO.popen([RbConfig.ruby, *flags], "r+") { |pipe|
    pipe.write code
    pipe.close_write
    pipe.read
  }
end

if RUBY_ENGINE == "ruby" && RUBY_VERSION >= "3.5"
  modules.each do |mod|
    file = "#{__dir__}/methods/#{mod}.txt"
    code = "puts #{mod}.public_instance_methods(false).sort"
    methods = ruby(code)
    methods = methods.lines.map { |line| line.chomp.to_sym }
    contents = methods.map { |meth| "#{meth}\n" }.join
    File.write file, contents
  end
end

code = <<-RUBY
require "ractor/shim"
#{modules.inspect}.each { |m|
  puts m
  puts eval(m).public_instance_methods(false).sort
  puts
}
RUBY
all_methods = {}
ruby(code, "-I#{File.dirname(__dir__)}/lib").rstrip.split("\n\n").each do |group|
  mod, *methods = group.lines.map(&:chomp)
  all_methods[mod] = methods.map(&:to_sym)
end

modules.each do |mod|
  file = "#{__dir__}/methods/#{mod}.txt"
  expected = File.readlines(file).map { |line| line.chomp.to_sym }
  methods = all_methods[mod]

  if methods != expected
    extras = methods - expected
    if mod == "Ractor.singleton_class"
      extras -= %i[builtin? shim?] # intended extras
    end

    raise "#{mod} methods should not include #{extras}" unless extras.empty?

    missing = expected - methods
    raise "#{mod} methods should include #{missing}" unless missing.empty?
  end
end

puts "#{__FILE__}: OK"
