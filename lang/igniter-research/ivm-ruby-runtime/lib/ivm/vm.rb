# frozen_string_literal: true

require "digest"
require "json"
require_relative "instructions"
require_relative "stdlib"

module IVM
  # Stack-based, register-gated execution Virtual Machine (IVM).
  # Decodes and executes linear lists of Compiled IVM Instructions.
  class VM
    # Base error class for VM execution errors.
    class ExecutionError < StandardError; end
    class StackUnderflowError < ExecutionError; end
    class RegisterBoundsError < ExecutionError; end
    class ConditionTypeError < ExecutionError; end
    class OutOfBoundsJumpError < ExecutionError; end
    class TemporalBackendError < ExecutionError; end

    attr_reader :stack, :registers, :observation_sink, :ip

    def initialize(backend: nil)
      @backend          = backend
      @stack            = []
      @registers        = {}
      @observation_sink = []
      @ip               = 0 # Instruction Pointer
    end

    # Run the compiled bytecode.
    #
    # instructions     - Array of IVM::Instructions::Instruction instances.
    # inputs           - Hash of input variable values.
    # temporal_context - Hash containing bitemporal coordinates (e.g., {"as_of" => "ISO8601"})
    #
    # Returns the value remaining at the top of the stack after OP_RET execution.
    def execute(instructions, inputs = {}, temporal_context = {})
      @stack.clear
      @registers.clear
      @ip = 0

      total_instructions = instructions.length

      while @ip < total_instructions
        inst = instructions[@ip]
        opcode = inst.opcode
        args = inst.args

        case opcode
        when Instructions::OP_PUSH_LIT
          # Push static literal value directly
          @stack.push(args[0])
          @ip += 1

        when Instructions::OP_LOAD_REF
          # Load referenced input or temporal coordinate
          name = args[0]
          val = if inputs.key?(name)
                  inputs[name]
                elsif temporal_context.key?(name)
                  temporal_context[name]
                else
                  raise ExecutionError, "Reference symbol '#{name}' not found in inputs or temporal context"
                end
          @stack.push(val)
          @ip += 1

        when Instructions::OP_STORE_REG
          # Store top of stack to register index
          reg_idx = args[0]
          raise StackUnderflowError, "Stack is empty; cannot store in register #{reg_idx}" if @stack.empty?
          @registers[reg_idx] = @stack.pop
          @ip += 1

        when Instructions::OP_LOAD_REG
          # Load from register index to top of stack
          reg_idx = args[0]
          unless @registers.key?(reg_idx)
            raise RegisterBoundsError, "Register index #{reg_idx} is uninitialized"
          end
          @stack.push(@registers[reg_idx])
          @ip += 1

        when Instructions::OP_ADD
          # Pop two values, add them, push result
          b = pop_stack("ADD second operand")
          a = pop_stack("ADD first operand")
          if is_decimal?(a) && is_decimal?(b)
            a_val, a_scale = extract_decimal(a)
            b_val, b_scale = extract_decimal(b)
            begin
              res_val, res_scale = IVM::Stdlib.decimal_add(a_val, a_scale, b_val, b_scale)
              @stack.push({ value: res_val, scale: res_scale })
            rescue IVM::Stdlib::ScaleMismatchError => e
              raise ExecutionError, e.message
            rescue IVM::Stdlib::StdlibError => e
              raise ExecutionError, e.message
            end
          else
            @stack.push(a + b)
          end
          @ip += 1

        when Instructions::OP_SUB
          # Pop two, sub, push
          b = pop_stack("SUB second operand")
          a = pop_stack("SUB first operand")
          if is_decimal?(a) && is_decimal?(b)
            a_val, a_scale = extract_decimal(a)
            b_val, b_scale = extract_decimal(b)
            begin
              res_val, res_scale = IVM::Stdlib.decimal_sub(a_val, a_scale, b_val, b_scale)
              @stack.push({ value: res_val, scale: res_scale })
            rescue IVM::Stdlib::ScaleMismatchError => e
              raise ExecutionError, e.message
            rescue IVM::Stdlib::StdlibError => e
              raise ExecutionError, e.message
            end
          else
            @stack.push(a - b)
          end
          @ip += 1

        when Instructions::OP_MUL
          # Pop two, mul, push
          b = pop_stack("MUL second operand")
          a = pop_stack("MUL first operand")
          if is_decimal?(a) && is_decimal?(b)
            a_val, a_scale = extract_decimal(a)
            b_val, b_scale = extract_decimal(b)
            begin
              res_val, res_scale = IVM::Stdlib.decimal_mul(a_val, a_scale, b_val, b_scale)
              @stack.push({ value: res_val, scale: res_scale })
            rescue IVM::Stdlib::StdlibError => e
              raise ExecutionError, e.message
            end
          else
            @stack.push(a * b)
          end
          @ip += 1

        when Instructions::OP_DIV
          # Pop two, div, push
          b = pop_stack("DIV second operand")
          a = pop_stack("DIV first operand")
          if is_decimal?(a) && is_decimal?(b)
            a_val, a_scale = extract_decimal(a)
            b_val, b_scale = extract_decimal(b)
            begin
              res_val, res_scale = IVM::Stdlib.decimal_div(a_val, a_scale, b_val, b_scale)
              @stack.push({ value: res_val, scale: res_scale })
            rescue IVM::Stdlib::DivisionError => e
              raise ExecutionError, e.message
            rescue IVM::Stdlib::StdlibError => e
              raise ExecutionError, e.message
            end
          else
            @stack.push(a / b)
          end
          @ip += 1

        when Instructions::OP_EQ
          # Pop two, compare, push Bool
          b = pop_stack("EQ second operand")
          a = pop_stack("EQ first operand")
          @stack.push(a == b)
          @ip += 1

        when Instructions::OP_GT
          # Pop two, compare a > b, push Bool
          b = pop_stack("GT second operand")
          a = pop_stack("GT first operand")
          @stack.push(a > b)
          @ip += 1

        when Instructions::OP_JMP
          # Unconditional jump
          target = args[0]
          validate_jump_target!(target, total_instructions)
          @ip = target

        when Instructions::OP_JMP_IF
          # Pop Bool; jump if true
          cond = pop_stack("JMP_IF condition")
          unless cond == true || cond == false
            raise ConditionTypeError, "JMP_IF condition must evaluate to Bool; got #{cond.class}: #{cond.inspect}"
          end

          if cond
            target = args[0]
            validate_jump_target!(target, total_instructions)
            @ip = target
          else
            @ip += 1
          end

        when Instructions::OP_JMP_UNLESS
          # Pop Bool; jump if false (lazy branches)
          cond = pop_stack("JMP_UNLESS condition")
          unless cond == true || cond == false
            raise ConditionTypeError, "JMP_UNLESS condition must evaluate to Bool; got #{cond.class}: #{cond.inspect}"
          end

          unless cond
            target = args[0]
            validate_jump_target!(target, total_instructions)
            @ip = target
          else
            @ip += 1
          end

        when Instructions::OP_LOAD_AS_OF
          # Arguments: [store_name, as_of_input_ref]
          # Pop as_of value (or resolve it), query temporal backend
          store_name = args[0]
          as_of_ref = args[1]

          raise TemporalBackendError, "No temporal backend attached to VM" unless @backend

          as_of = if inputs.key?(as_of_ref)
                    inputs[as_of_ref]
                  elsif temporal_context.key?(as_of_ref)
                    temporal_context[as_of_ref]
                  else
                    raise ExecutionError, "as_of coordinate ref '#{as_of_ref}' not resolved"
                  end

          result, prov_obs = @backend.read_as_of(store_name, as_of)

          # Unwrap option envelope result and push raw value to stack
          val = (result["kind"] == "some") ? result["value"] : nil
          @stack.push(val)

          # Auto-emit read observation trace (AT-10 style compliance)
          obs_id = "obs/live-read/#{Digest::SHA256.hexdigest("#{store_name}-#{as_of}")[0, 16]}"
          @observation_sink << {
            "kind" => "temporal_live_read_observation",
            "observation_id" => obs_id,
            "store" => store_name,
            "axis" => "valid_time",
            "as_of" => as_of,
            "result_present" => result.is_a?(Hash) && result["kind"] == "some",
            "result_value" => result,
            "backend_observation" => prov_obs,
            "timestamp" => Time.now.to_s
          }

          @ip += 1

        when Instructions::OP_EMIT_OBS
          # Pop value, package as observation envelope, and push back
          obs_kind = args[0]
          val = pop_stack("EMIT_OBS value")

          obs_id = "obs/eval/#{Digest::SHA256.hexdigest("#{obs_kind}-#{val.inspect}")[0, 16]}"
          @observation_sink << {
            "kind" => obs_kind,
            "observation_id" => obs_id,
            "value" => val,
            "timestamp" => Time.now.to_s
          }
          @stack.push(val) # Push value back onto stack
          @ip += 1

        when Instructions::OP_RET
          # Pop top value and return it immediately, halting execution
          raise StackUnderflowError, "Stack empty on RET instruction" if @stack.empty?
          return @stack.pop

        when Instructions::OP_UNSUPPORTED
          raise ExecutionError, "Decoded unsupported selected-path bytecode instruction"

        else
          raise ExecutionError, "Unknown instruction opcode: 0x#{opcode.to_s(16)}"
        end
      end

      # Default fallback return value if RET was not executed (should not happen in correct code)
      raise ExecutionError, "Evaluation halted without explicit RET instruction"
    end

    private

    def is_decimal?(val)
      val.is_a?(Hash) && (val.key?(:value) || val.key?("value")) && (val.key?(:scale) || val.key?("scale"))
    end

    def extract_decimal(val)
      v = val.key?(:value) ? val[:value] : val["value"]
      s = val.key?(:scale) ? val[:scale] : val["scale"]
      [v.to_i, s.to_i]
    end

    def pop_stack(action)
      raise StackUnderflowError, "Stack underflow during: #{action}" if @stack.empty?
      @stack.pop
    end

    def validate_jump_target!(target, total_instructions)
      if target < 0 || target >= total_instructions
        raise OutOfBoundsJumpError, "Cannot jump to out-of-bounds offset #{target} (total #{total_instructions})"
      end
    end
  end
end
