# frozen_string_literal: true

has_shareable_proc = defined?(Ractor) && Ractor.respond_to?(:shareable_proc)

require 'ractor/shim'

BUILTIN_SKIPS = [
  "send shareable and unshareable objects", # leaks Ractors on 3.3
  "Ractor::IsolationError cases", # Ractor.make_shareable too permissive on 3.4
  "Ractor.select from two ractors.", # Ractor.select with ports doesn't work on 3.4
  "SystemExit from a Ractor is re-raised", # Ractor::ClosedError on 3.4 instead of Ractor::RemoteError
  "SystemExit from a Thread inside a Ractor is re-raised", # Ractor::ClosedError on 3.4 instead of Ractor::RemoteError
  "Access to global-variables are prohibited (read)", # different error message on 3.4
  "Access to global-variables are prohibited (write)", # different error message on 3.4
  "Ractor-local storage", # more permissive on 3.4
  "Now NoMethodError is copyable", # fails on 3.4
  "bind_call in Ractor [Bug #20934]", # SEGV on 3.4
  "moved objects being corrupted if embeded (Hash)", # broken on 3.4
  "moved objects being corrupted if embeded (MatchData)", # SEGV on 3.4
  "moved objects being corrupted if embeded (Struct)", # broken on 3.4
  "moved objects being corrupted if embeded (Object)", # broken on 3.4
  "moved arrays can't be used", # broken on 3.4
  "moved strings can't be used", # broken on 3.4
  "moved hashes can't be used", # broken on 3.4
  "move objects inside frozen containers", # broken on 3.4
  "moved composite types move their non-shareable parts properly", # broken on 3.4
  "Creating classes inside of Ractors", # OOM on 3.4
  "Ractor#join raises RemoteError when the remote Ractor aborted with an exception", # needs join semantics for exceptions
  "Only one Ractor can call Ractor#value", # need value semantics
  "monitor port returns `:exited` when the monitering Ractor terminated.", # Ractor#monitor
  "monitor port returns `:exited` even if the monitoring Ractor was terminated.", # Ractor#monitor
  "monitor returns false if the monitoring Ractor was terminated.", # Ractor#monitor
  "monitor port returns `:aborted` when the monitering Ractor is aborted.", # Ractor#monitor
  "monitor port returns `:aborted` even if the monitoring Ractor was aborted.", # Ractor#monitor
  "eval with outer locals in a Ractor raises SyntaxError", # can't check
]

SHIM_SKIPS = [
  "Ractor.allocate is not supported",
  "Ractor::IsolationError cases",
  "$DEBUG, $VERBOSE are Ractor local", # mutates global variables like $DEBUG and $VERBOSE
  "SystemExit from a Thread inside a Ractor is re-raised", # internal error on TruffleRuby
  "unshareable object are copied", # expected due to no copy
  "To copy the object, now Marshal#dump is used", # expected due to no copy
  "send shareable and unshareable objects", # expected due to no copy
  "frozen Objects are shareable", # expected due to no copy
  "touching moved object causes an error", # expected due to no move
  "move example2: Array", # expected due to no move
  "Access to global-variables are prohibited (read)", # can't check
  "Access to global-variables are prohibited (write)", # can't check
  "$stdin,out,err is Ractor local, but shared fds", # can't do
  "given block Proc will be isolated, so can not access outer variables.", # can't check
  "ivar in shareable-objects are not allowed to access from non-main Ractor", # not checked
  "ivar in shareable-objects are not allowed to access from non-main Ractor, by @iv (get)", # not checked
  "ivar in shareable-objects are not allowed to access from non-main Ractor, by @iv (set)", # not checked
  "and instance variables of classes/modules are accessible if they refer shareable objects", # not checked
  "cvar in shareable-objects are not allowed to access from non-main Ractor", # can't check
  "also cached cvar in shareable-objects are not allowed to access from non-main Ractor", # can't check
  "Getting non-shareable objects via constants by other Ractors is not allowed", # can't check
  "Constant cache should care about non-shareable constants", # can't check
  "The correct constant path shall be reported", # can't check
  "Setting non-shareable objects into constants by other Ractors is not allowed", # can't check
  "define_method is not allowed", # can't check
  "ObjectSpace._id2ref can not handle unshareable objects with Ractors", # can't check
  "Ractor.make_shareable(obj)", # expected due to no freeze
  "Ractor.make_shareable(obj) doesn't freeze shareable objects", # expected due to no freeze
  "Ractor.shareable?(recursive_objects)", # expected, due to all are shareable
  "Ractor.make_shareable(recursive_objects)", # expected, due to all are shareable
  "Ractor.make_shareable(obj, copy: true) makes copied shareable object.", # expected, due to all are shareable
  "Can not trap with not isolated Proc on non-main ractor", # can't check
  "Ractor-local storage with Thread inheritance of current Ractor", # hard
  "Chilled strings are not shareable", # expected, due to all are shareable
  "moved arrays can't be used", # expected due to no move
  "moved strings can't be used", # expected due to no move
  "moved hashes can't be used", # expected due to no move
  "moved composite types move their non-shareable parts properly", # expected due to no move
  "Only one Ractor can call Ractor#value", # could be implemented
  "eval with outer locals in a Ractor raises SyntaxError", # can't check
  "Ractor.make_shareable(Method/UnboundMethod)", # can't check
]

GLOBAL_SKIPS = [
  "Ractor.make_shareable(a_proc) requires a shareable receiver", # because this harness uses Object as outer self
  "threads in a ractor will killed", # leaks Ractors
  "TracePoint with normal Proc should be Ractor local", # line numbers differ due to test harness
  "Can yield back values while GC is sweeping [Bug #18117]", # too slow and leaks
  "check experimental warning", # harness disables experimental warnings
  "failed in autolaod in Ractor", # need more isolation
  "fork after creating Ractor", # fork, leaks
  "fork after creating many Ractors", # fork, leaks
  "fork after creating many Ractors 2", # fork, slow
  "Ractors should be terminated after fork", # fork, hangs
  "st_table, which can call malloc.", # leaks
  "Creating classes inside of Ractors", # leaks
  "defining ractor, even if it is GC'd", # too noisy
  "move object with generic ivars and existing id2ref table", # "NNN" is the id of an unshareable object on multi-ractor (RangeError)
]

NO_SHAREABLE_PROC_SKIPS = [
  "Ractor.shareable_proc makes a copy of given Proc",
  "Ractor.shareable_proc keeps the original Proc intact",
  "because in most cases it would raise anyway due to not-shared self or not-shared captured variable value",
]

skips = GLOBAL_SKIPS
skips += BUILTIN_SKIPS if Ractor.builtin? && RUBY_VERSION < "4.0"
skips += SHIM_SKIPS if Ractor.shim?
skips += NO_SHAREABLE_PROC_SKIPS if !has_shareable_proc

if Ractor.builtin? && RUBY_VERSION < "4.0"
  # fails on 3.4
  skips += [
    "Ractor.make_shareable(Method/UnboundMethod)",
  ]
end
if Ractor.builtin? && RUBY_VERSION < "3.4"
  # fails on 3.3
  skips += [
    "unshareable frozen objects should still be frozen in new ractor after move",
    "ivar in shareable-objects are not allowed to access from non-main Ractor",
    "ivar in shareable-objects are not allowed to access from non-main Ractor, by @iv (get)",
    "ivar in shareable-objects are not allowed to access from non-main Ractor, by @iv (set)",
    "defined? on ivar of module",
    "moved objects have their shape properly set to original object's shape",
    "Ractor-local storage with Thread inheritance of current Ractor",
    "require in Ractor",
    "autolaod in Ractor",
    "moved objects being corrupted if embeded (String)",
    "move object with generic ivar",
    "move object with many generic ivars", # SEGV
    "move object with complex generic ivars",
  ]
end
if Ractor.builtin? && RUBY_VERSION < "3.3"
  # fails on 3.2
  skips += [
    "check moved object", # SEGV
    "fstring pool 2", # spurious, probably a fstring table bug
  ]
end
if Ractor.builtin? && RUBY_VERSION < "3.1"
  # fails on 3.0
  skips += [
    "and instance variables of classes/modules are accessible if they refer shareable objects",
    "define_method is not allowed",
    "check method cache invalidation", # SEGV
  ]
end
if Ractor.shim? && RUBY_ENGINE == "ruby" && RUBY_VERSION < "3.0"
  # fails on 2.7
  skips += [
    "check method cache invalidation", # syntax
  ]
end
if Ractor.shim? && RUBY_ENGINE == "jruby"
  skips += [
    "ObjectSpace.each_object can not handle unshareable objects with Ractors",
    "fstring pool 2", # spurious, probably a fstring table bug
  ]
end
if $DEBUG
  # fails probably Due to Thread.abort_on_exception being true with $DEBUG true
  skips += [
    "an exception in a Ractor non-main thread will not be re-raised at Ractor#receive",
  ]
end
SKIPS = skips

def new_empty_binding
  # we need a shareable self for shareable procs/lambdas, but also preserve the default definee of Object
  Object.class_eval { binding }
end

def skip(reason = nil)
  throw :skip, :skip
end

TEST_LINES = [""] + File.readlines("#{__dir__}/test_ractor.rb").map(&:chomp)

def generic_assert(expected, code, check, &error_message)
  test_info = caller_locations(2, 1)[0]
  line = test_info.lineno
  test_name = TEST_LINES[line-1]
  test_name = TEST_LINES[line-2] if test_name.start_with?("# [Bug")
  warn "Could not find test name for test at line #{line}" unless test_name.start_with?("# ")
  test_name = test_name[2..-1]

  print "Running test from line #{line}: "
  if SKIPS.include?(line) or SKIPS.include?(test_name)
    puts "SKIP"
    return
  end

  begin
    actual = catch(:skip) do
      eval(code, new_empty_binding, test_info.path, line).to_s
    end
    return if :skip == actual
  rescue => e
    puts "ERROR"
    e.set_backtrace(e.backtrace.reject { |b|
      b.include?(__FILE__)
    }.map { |b|
      b.sub(/(Object#)?new_empty_binding/, 'test')
    })
    raise e
  end

  if check.call(actual, expected)
    puts "PASS #{actual}"
  else
    puts "FAIL"
    raise RuntimeError, error_message.call(actual, expected), caller(2)
  end

  wait_ms = 10
  waited = 0
  while (leaked = Ractor.count - 1) > 0 and waited < wait_ms
    sleep 0.001
    waited += 1
  end
  unless leaked == 0
    raise "Test at line #{line} leaked #{leaked} Ractors"
  end

  # cleanup global state
  Object.send(:remove_const, :A) if Object.const_defined?(:A)

  unless Ractor::RemoteError.is_a? Class
    raise "Ractor::RemoteError is no longer a Class!: #{Ractor::RemoteError.inspect}"
  end
end

def assert_equal(expected, code, frozen_string_literal: nil)
  generic_assert(expected, code, -> a, e { e == a }) { |actual, expected|
    "Expected #{expected.inspect} but got #{actual.inspect}"
  }
end

def assert_match(expected, code, frozen_string_literal: nil)
  generic_assert(expected, code, -> a, e { e.match?(a) }) { |actual, expected|
    "Expected #{expected} =~ #{actual.inspect} but it was false"
  }
end

def assert_normal_exit(code)
  # Skip because such tests need to run in their own process
  return
  # generic_assert(:unused, code, -> a, e { true }) { |actual, expected|
  #   raise "unreachable"
  # }
end

def yjit_enabled?
  false
end

Warning[:experimental] = false

require_relative 'test_ractor'

require_relative 'ractor_methods_test'

puts "\n\e[0;32mSUCCESS!\e[0m"
