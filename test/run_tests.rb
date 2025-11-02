# frozen_string_literal: true

GLOBAL_SKIPS = [
  "Ractor.make_shareable(a_proc) requires a shareable receiver", # because this harness uses Object as outer self
  "threads in a ractor will killed", # leaks Ractors
  "TracePoint with normal Proc should be Ractor local", # line numbers differ due to test harness
  "Can yield back values while GC is sweeping [Bug #18117]", # too slow and leaks
  "check experimental warning", # harness disables experimental warnings
  "failed in autolaod in Ractor", # need more isolation
  "fork after creating Ractor", # fork, leaks
  "Ractors should be terminated after fork", # fork, hangs
  "st_table, which can call malloc.", # leaks
  "Creating classes inside of Ractors", # leaks
]

skips = GLOBAL_SKIPS
if RUBY_VERSION >= "3.5"
  # fails on 3.5+
  skips += [
    # "move object with generic ivar", # SEGV
    # "move object with many generic ivars", # SEGV
    # "move object with complex generic ivars", # SEGV
    # "moved composite types move their non-shareable parts properly", # SEGV
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
