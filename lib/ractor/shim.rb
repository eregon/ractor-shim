# frozen_string_literal: true

builtin_ractor = !!defined?(Ractor)
class Ractor
end
Ractor.define_singleton_method(:builtin?) { builtin_ractor }
Ractor.define_singleton_method(:shim?) { !builtin_ractor }

if Ractor.shim?
  class Ractor
    class Error < RuntimeError
    end

    class RemoteError < Error
      attr_reader :ractor
      def initialize(ractor)
        @ractor = ractor
      end
    end

    class ClosedError < StopIteration
    end

    @count = 1
    COUNT_MUTEX = Mutex.new
    CHANGE_COUNT = -> delta {
      COUNT_MUTEX.synchronize { @count += delta }
    }

    @id = 0
    ID_MUTEX = Mutex.new
    GET_ID = -> {
      ID_MUTEX.synchronize { @id += 1 }
    }

    SELECT_MUTEX = Mutex.new
    SELECT_CV = ConditionVariable.new

    def self.main
      MAIN_RACTOR
    end

    def self.main?
      current == main
    end

    def self.current
      Thread.current.thread_variable_get(:current_ractor) or raise "Could not find current Ractor"
    end

    def self.count
      COUNT_MUTEX.synchronize { @count }
    end

    def self.receive
      Ractor.current.__send__(:receive)
    end

    # def self.select_simple_spinning(*ractors)
    #   raise ArgumentError, "specify at least one ractor or `yield_value`" if ractors.empty?
    #   while true
    #     ractors.each do |ractor_or_port|
    #       if Ractor === ractor_or_port
    #         queue = ractor_or_port.out_queue
    #       elsif Ractor::Port === ractor_or_port
    #         queue = ractor_or_port.queue
    #       else
    #         raise ArgumentError, "Unexpected argument for Ractor.select: #{ractor_or_port}"
    #       end
    #
    #       begin
    #         value = queue.pop(true)
    #         return [ractor_or_port, value]
    #       rescue ThreadError
    #         Thread.pass
    #       end
    #     end
    #   end
    # end

    def self.select(*ractors)
      raise ArgumentError, "specify at least one ractor or `yield_value`" if ractors.empty?

      SELECT_MUTEX.synchronize do
        while true
          ractors.each do |ractor_or_port|
            if Ractor === ractor_or_port
              queue = ractor_or_port.out_queue
            elsif Ractor::Port === ractor_or_port
              queue = ractor_or_port.queue
            else
              raise ArgumentError, "Unexpected argument for Ractor.select: #{ractor_or_port}"
            end

            begin
              value = queue.pop(true)
              return [ractor_or_port, value]
            rescue ThreadError
              # keep looping
            end
          end

          # Wait until an item is added to a relevant Queue
          SELECT_CV.wait(SELECT_MUTEX)
        end
      end
    end

    def self.make_shareable(object, copy: false)
      # no copy, just return the object
      object
    end

    def self.shareable?(object)
      true
    end

    def self.store_if_absent(var, &block)
      Ractor.current.__send__(:store_if_absent, var, &block)
    end

    def self._require(feature)
      Kernel.require(feature)
    end

    attr_reader :name

    attr_reader :in_queue, :out_queue

    def initialize(*args, name: nil, &block)
      raise ArgumentError, "must be called with a block" unless block
      initialize_common(name, block)
      CHANGE_COUNT.call(1)

      @thread = Thread.new {
        Thread.current.thread_variable_set(:current_ractor, self)
        begin
          result = self.instance_exec(*args, &block)
          SELECT_MUTEX.synchronize {
            unless @out_queue.closed?
              @out_queue << result
              SELECT_CV.broadcast
            end
          }
          result
        rescue Exception => e
          @exception = e
          nil
        ensure
          @termination_mutex.synchronize {
            CHANGE_COUNT.call(-1)
            @status = :terminated

            monitor_message = @exception ? :aborted : :exited
            @monitors.each { |monitor|
              monitor << monitor_message
            }
            @monitors.clear
          }
        end
      }
    end

    private def initialize_main
      initialize_common(nil, nil)
      @thread = nil
    end

    private def initialize_common(name, block)
      @name = name.nil? ? nil : (String.try_convert(name) or raise TypeError)
      @id = GET_ID.call
      @status = :running
      @from = block ? block.source_location.join(":") : nil
      @in_queue = Queue.new
      @out_queue = Queue.new
      @storage = {}
      @exception = nil
      @monitors = []
      @termination_mutex = Mutex.new
    end

    def [](var)
      raise "Cannot get ractor local storage for non-current ractor" unless Ractor.current == self
      @storage[var]
    end

    def []=(var, value)
      raise "Cannot set ractor local storage for non-current ractor" unless Ractor.current == self
      @storage[var] = value
    end

    private def store_if_absent(var, &block)
      if value = @storage[var]
        value
      else
        value = block.call
        @storage[var] = value
        value
      end
    end

    def send(message, move: false)
      raise Ractor::ClosedError, "The port was already closed" if @status == :terminated || @in_queue.closed?
      @in_queue << message
      self
    end
    alias_method :<<, :send

    private def receive
      @in_queue.pop
    end

    # def take
    #   @out_queue.pop
    # end

    def close_incoming
      @in_queue.close
      self
    end

    def close_outgoing
      SELECT_MUTEX.synchronize {
        @out_queue.close
        SELECT_CV.broadcast
      }
      self
    end

    def monitor(port)
      @termination_mutex.synchronize {
        if @status == :terminated
          port << (@exception ? :aborted : :exited)
          false
        else
          @monitors << port
        end
      }
    end

    def unmonitor(port)
      @termination_mutex.synchronize {
        @monitors.delete port
      }
    end

    def join
      value
      self
    end

    def value
      @thread.join

      if exc = @exception
        remote_error = RemoteError.new(self)
        raise remote_error, cause: exc
      end

      @thread.value
    end

    def inspect
      ["#<Ractor:##{@id}", @name, @from, "#{@status}>"].compact.join(' ')
    end

    MAIN_RACTOR = Ractor.allocate
    MAIN_RACTOR.__send__(:initialize_main)
    Thread.main.thread_variable_set(:current_ractor, MAIN_RACTOR)
  end
end

if Ractor.builtin?
  class Ractor
    unless method_defined?(:join)
      alias_method :join, :take
    end

    unless method_defined?(:value)
      alias_method :value, :take
    end

    unless respond_to?(:main?)
      def self.main?
        self == Ractor.main
      end
    end
  end
end

# common
class Ractor
  unless method_defined?(:close)
    def close
      close_incoming
      close_outgoing
    end
  end
end

# Ractor.{shareable_proc,shareable_lambda}

class << Ractor
  if Ractor.builtin?
    unless method_defined?(:shareable_proc)
      def shareable_proc(&b)
        Ractor.make_shareable(b)
      end
    end

    unless method_defined?(:shareable_lambda)
      def shareable_lambda(&b)
        Ractor.make_shareable(b)
      end
    end
  else
    unless method_defined?(:shareable_proc)
      alias_method :shareable_proc, :proc
      public :shareable_proc
    end

    unless method_defined?(:shareable_lambda)
      alias_method :shareable_lambda, :lambda
      public :shareable_lambda
    end
  end
end

# Ractor::Port

if Ractor.builtin?
  class Ractor::Port
    QUIT = Object.new.freeze

    def initialize
      @pipe = Ractor.new do
        while true
          msg = Ractor.receive
          break if QUIT.equal?(msg)
          Ractor.yield msg
        end
      end
    end

    def <<(message)
      @pipe.send(message)
    end

    def receive
      @pipe.take
    end

    def close
      @pipe.send(QUIT)
    end
  end unless defined?(Ractor::Port)
else
  class Ractor::Port
    attr_reader :queue

    def initialize
      @queue = Queue.new
    end

    def <<(message)
      Ractor::SELECT_MUTEX.synchronize {
        @queue << message
        Ractor::SELECT_CV.broadcast
      }
      self
    end

    def receive
      @queue.pop
    end

    def close
      Ractor::SELECT_MUTEX.synchronize {
        @queue.close
        Ractor::SELECT_CV.broadcast
      }
      self
    end
  end
end
