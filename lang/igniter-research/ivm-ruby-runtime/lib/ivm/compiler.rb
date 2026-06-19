# frozen_string_literal: true

require "digest"
require_relative "instructions"

module IVM
  # Ahead-of-Time (AOT) Compiler that translates structured
  # SemanticIR AST node graphs into Compiled IVM Bytecode.
  class Compiler
    class CompilationError < StandardError; end

    attr_reader :instructions

    def initialize
      @instructions = []
    end

    # Compile a high-level contract graph into linear bytecode instructions.
    #
    # contract - Hash representing the contract and its SemanticIR nodes:
    #            {
    #              "contract_id" => "Name",
    #              "inputs" => ["input1", ...],
    #              "expression" => { ... AST Expression Node ... }
    #            }
    #
    # Returns an Array of IVM::Instructions::Instruction.
    def compile(contract)
      @instructions.clear

      expr = contract.fetch("expression") do
        raise CompilationError, "Contract is missing 'expression' AST node"
      end

      # 1. Compile the main expression recursively
      compile_expr(expr)

      # 2. Emit RET to return final value at the top of the stack and halt VM
      emit(Instructions::OP_RET)

      # 3. Resolve jump labels and offsets
      resolve_jumps!

      # Return a frozen array of compiled instruction instances
      @instructions.dup.freeze
    end

    private

    # Emit a bytecode instruction
    def emit(opcode, *args)
      inst = Instructions::Instruction.new(opcode, *args)
      @instructions << inst
      @instructions.length - 1 # Return instruction pointer offset
    end

    # Recursively translate SemanticIR expression nodes to bytecode instructions.
    def compile_expr(node)
      unless node.is_a?(Hash) && node.key?("kind")
        raise CompilationError, "Expression node must be a Hash with a 'kind' key; got #{node.class}"
      end

      kind = node.fetch("kind")

      case kind
      when "literal"
        emit(Instructions::OP_PUSH_LIT, node.fetch("value"))

      when "ref"
        emit(Instructions::OP_LOAD_REF, node.fetch("name"))

      when "binary_op"
        # Compile left, then right, then apply operator instruction
        compile_expr(node.fetch("left"))
        compile_expr(node.fetch("right"))

        op = node.fetch("operator")
        case op
        when "+"  then emit(Instructions::OP_ADD)
        when "-"  then emit(Instructions::OP_SUB)
        when "*"  then emit(Instructions::OP_MUL)
        when "/"  then emit(Instructions::OP_DIV)
        when "==" then emit(Instructions::OP_EQ)
        when ">"  then emit(Instructions::OP_GT)
        else
          raise CompilationError, "Unsupported binary operator: #{op.inspect}"
        end

      when "if_expr"
        # Lazy branch evaluation logic:
        #
        #   [Compile condition]
        #   JMP_UNLESS -> ELSE_LABEL
        #   [Compile then_branch]
        #   JMP -> END_LABEL
        #   ELSE_LABEL:
        #   [Compile else_branch]
        #   END_LABEL:

        compile_expr(node.fetch("condition"))

        # Emit placeholder JMP_UNLESS jump target
        jmp_unless_idx = emit(Instructions::OP_JMP_UNLESS, :placeholder_else)

        compile_expr(node.fetch("then_branch"))

        # Emit placeholder unconditional JMP target to skip else branch
        jmp_end_idx = emit(Instructions::OP_JMP, :placeholder_end)

        # Label: start of else branch is the current instruction pointer offset
        else_branch_start_idx = @instructions.length

        compile_expr(node.fetch("else_branch"))

        # Label: end is the current instruction pointer offset
        end_idx = @instructions.length

        # Re-emit instructions with resolved placeholder targets
        @instructions[jmp_unless_idx] = Instructions::Instruction.new(
          Instructions::OP_JMP_UNLESS,
          else_branch_start_idx
        )
        @instructions[jmp_end_idx] = Instructions::Instruction.new(
          Instructions::OP_JMP,
          end_idx
        )

      when "temporal_read"
        # Arguments: store_ref, as_of_ref
        emit(
          Instructions::OP_LOAD_AS_OF,
          node.fetch("store_ref"),
          node.fetch("as_of_ref")
        )

      when "emit_observation"
        # Evaluate inner expression first, then package value into the sink
        compile_expr(node.fetch("expression"))
        emit(Instructions::OP_EMIT_OBS, node.fetch("observation_kind"))

      when "unsupported"
        emit(Instructions::OP_UNSUPPORTED)

      else
        raise CompilationError, "Unsupported AST expression kind: #{kind.inspect}"
      end
    end

    # Resolve any remaining placeholder jumps
    def resolve_jumps!
      @instructions.each_with_index do |inst, idx|
        if inst.args.include?(:placeholder_else) || inst.args.include?(:placeholder_end)
          raise CompilationError, "Unresolved placeholder jump at instruction offset #{idx}: #{inst}"
        end
      end
    end
  end
end
