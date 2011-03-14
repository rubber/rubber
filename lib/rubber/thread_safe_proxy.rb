
module Rubber
  class ThreadSafeProxy
    instance_methods.each { |m| undef_method m unless m =~ /(^__|^send$|^object_id$)/ }

    def initialize(&block)
      @target_block = block
    end
    
    protected

    def method_missing(name, *args, &block)
      target.send(name, *args, &block)
    end

    def target
      Thread.current["thread_safe_proxy_target_#{object_id}"] ||= @target_block.call
    end

  end
end
