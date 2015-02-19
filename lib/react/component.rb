require "./ext/string"
require 'active_support/core_ext/class/attribute'

module React
  module Component
    def self.included(base)
      base.class_eval do
        class_attribute :before_mount_callbacks, :after_mount_callbacks, :init_state
      end
      base.extend(ClassMethods)
    end

    def initialize(native_element)
      @native = native_element
    end

    def params
      Native(`#{@native}.props`)
    end

    def refs
      Native(`#{@native}.refs`)
    end

    def emit(event_name, *args)
      self.params["_on#{event_name.to_s.event_camelize}"].call(*args)
    end

    def mounted?
      `#{@native}.isMounted()`
    end

    def component_will_mount
      return unless self.class.before_mount_callbacks
      self.class.before_mount_callbacks.each do |callback|
        send(callback)
      end
    end

    def component_did_mount
      return unless self.class.after_mount_callbacks
      self.class.after_mount_callbacks.each do |callback|
        send(callback)
      end
    end

    def method_missing(name, *args, &block)
      unless (React::HTML_TAGS.include?(name) || name == 'present')
        return super
      end

      if name == "present"
        name = args.shift
      end

      if block
        @buffer = [] unless @buffer
        current = @buffer
        @buffer = []
        result = block.call
        element = React.create_element(name, *args) { @buffer.count == 0 ? result : @buffer }
        @buffer = current
      else
        element = React.create_element(name, *args)
      end

      @buffer << element
      element
    end


    module ClassMethods
      def before_mount(*callback)
        self.before_mount_callbacks=  callback
      end

      def after_mount(*callback)
        self.after_mount_callbacks = callback
      end

      def define_state(*states)
        raise "Block could be only given when define exactly one state" if block_given? && states.count > 1

        self.init_state = {} unless self.init_state

        if block_given?
          self.init_state[states[0]] = yield
        end
        states.each do |name|
          # getter
          define_method("#{name}") do
            unless @native
              self.class.init_state[name]
            else
              `#{@native}.state[#{name}]`
            end
          end
          # setter
          define_method("#{name}=") do |new_state|
            unless @native
              self.class.init_state[name] = new_state
            else
              %x{
                state = #{@native}.state || {};
                state[#{name}] = #{new_state};
                #{@native}.setState(state);
              }
            end

            new_state
          end
          # setter with callback
          define_method("set_#{name}") do |new_state, &block|
            unless @native
              self.class.init_state[name] = new_state
            else
              %x{
                state = #{@native}.state || {};
                state[#{name}] = #{new_state};
                #{@native}.setState(state, function(){
                  #{block.call if block}
                });
              }
            end

            new_state
          end

        end
      end
    end
  end
end
