require 'active_support/concern'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/kernel/singleton_class'
require 'active_support/core_ext/object/try'

module SimpleStates
  class TransitionException < RuntimeError; end

  autoload :Event,  'simple_states/event'
  autoload :States, 'simple_states/states'

  extend ActiveSupport::Concern

  included do
    class_attribute :state_names, :initial_state, :events
    after_initialize :init_state if respond_to?(:after_initialize)
    self.initial_state = :created
    self.events = []
  end

  module ClassMethods
    def new(*)
      super.tap { |object| States.init(object) }
    end

    def allocate
      super.tap { |object| States.init(object) }
    end

    def states(*args)
      if args.empty?
        self.state_names ||= add_states(self.initial_state)
      else
        options = args.last.is_a?(Hash) ? args.pop : {}
        self.initial_state = options[:initial].to_sym if options.key?(:initial)
        add_states(*[self.initial_state].concat(args))
      end
    end

    def add_states(*states)
      self.state_names = (self.state_names || []).concat(states.compact.map(&:to_sym)).uniq
    end

    def event(name, options = {})
      add_states(options[:to], *options[:from])
      self.events += [Event.new(name, options)]
    end
  end

  attr_reader :past_states
  attr_accessor :state_transitions

  def init_state
    self.state = self.class.initial_state if state.nil?
  end

  def past_states
    @past_states ||= []
  end

  def state_transitions(requirements = {})
    on ||= requirements[:on]
    from ||= requirements[:from]
    to ||= requirements[:to]
    events.map { |event| { :options => event.options, :name => event.name} }.select { |event|  
      if on.present?
        event[:name].eql?(on.try(:to_sym))
      elsif from.present? && to.present?
        [*event[:options].from].include?(from.try(:to_sym)) && [*event[:options].to].include?(to.try(:to_sym))
      elsif from.present?
        [*event[:options].from].include?(from.try(:to_sym))
      elsif to.present?
        [*event[:options].to].include?(to.try(:to_sym))
      else
        from = self.state
        [*event[:options].to].include?(from.try(:to_sym))
      end
    }.map { |event| { :event => event[:name], :from => from.present? ? from : event[:options].from, :to => to.present? ? to : event[:options].to } }
  end

  def state?(state, include_past = false)
    include_past ? was_state?(state) : self.state.try(:to_sym) == state.to_sym
  end

  def was_state?(state)
    past_states.concat([self.state.try(:to_sym)]).compact.include?(state.to_sym)
  end

  def respond_to?(method, include_private = false)
    method.to_s =~ /(was_|^)(#{self.class.states.join('|')})\?$/ && self.class.state_names.include?($2.to_sym) || super
  end

  def method_missing(method, *args, &block)
    method.to_s =~ /(was_|^)(#{self.class.states.join('|')})\?$/ ? send(:"#{$1}state?", $2, *args) : super
  end
end

