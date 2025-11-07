module Assignments
  class NoCapacityError < StandardError
    attr_reader :requested, :available

    def initialize(requested:, available:)
      @requested = requested
      @available = available
      super("Insufficient capacity: requested #{requested}, available #{available}")
    end
  end
end
