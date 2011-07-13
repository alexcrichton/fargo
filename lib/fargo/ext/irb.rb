require 'irb'

module IRB
  # Starts a new IRB session within the binding provided. The functions of the
  # binding will be available at the IRB prompt. This function does not return
  # until the IRB session has ended.
  #
  # This code was adapted from:
  # http://jameskilton.com/2009/04/02/embedding-irb-into-your-ruby-application/
  def self.start_session(binding)
    unless @__initialized
      args = ARGV
      ARGV.replace(ARGV.dup)
      IRB.setup(nil)
      ARGV.replace(args)
      @__initialized = true
    end

    workspace = WorkSpace.new(binding)

    irb = Irb.new(workspace)

    trap('SIGINT') do
      irb.signal_handle
    end

    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context
    @CONF[:PROMPT][@CONF[:PROMPT_MODE]][:RETURN].replace ''

    yield if block_given?

    catch(:IRB_EXIT) do
      irb.eval_input
    end
  end
end
