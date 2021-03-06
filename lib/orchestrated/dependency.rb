require 'state_machine'

module Orchestrated
  class OrchestrationDependency < ActiveRecord::Base
    belongs_to :prerequisite, :class_name => 'CompletionExpression'
    belongs_to :dependent, :class_name => 'CompletionExpression'
    before_validation :constrain

    state_machine :initial => :incomplete, :action => :save_avoiding_recursion do
      state :incomplete
      state :complete
      state :canceled
      event :prerequisite_completed do
        transition :incomplete => :complete
      end
      event :prerequisite_canceled do
        transition :incomplete => :canceled
      end
      after_transition any => :complete do |dependency, transition|
        dependency.call_dependent{|d| d.prerequisite_complete}
      end
      after_transition any => :canceled do |dependency, transition|
        dependency.call_dependent{|d| d.prerequisite_canceled}
      end
    end
    def call_dependent(&block)
      yield dependent unless dependent.nil?
    end
    def constrain
      @saving = true
      _constrain.tap{@saving = false}
    end
    def _constrain
      if prerequisite.present?
        # This method can be called more than once in general since it is called
        # as part of validation. Rather than loosening the state machine (to allow
        # e.g. complete=>complete) we explicitly avoid re-submitting events here.
        prerequisite_completed if prerequisite.complete? && can_prerequisite_completed?
        prerequisite_canceled if prerequisite.canceled? && can_prerequisite_canceled?
      end
      true
    end
    def save_avoiding_recursion
      # Default action of state_machine is "save", however that is
      # a problem when we need to transition state during validation
      # (see constrain method above). If were are validating then we
      # dursnt call save again.
      if @saving
        true # allow state transition but don't save ActiveRecord
      else
        save # save ActiveRecord as usual and return true/false
      end
    end
  end
end
