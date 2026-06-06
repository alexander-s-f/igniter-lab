# frozen_string_literal: true

# Entrypoint namespace and loader for the Igniter Virtual Machine (IVM).
module IVM
  VERSION = "0.1.0-poc.1"
end

require_relative "ivm/instructions"
require_relative "ivm/vm"
require_relative "ivm/compiler"
require_relative "ivm/tbackend"
