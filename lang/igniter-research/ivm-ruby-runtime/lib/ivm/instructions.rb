# frozen_string_literal: true

module IVM
  # Bytecode Instruction Definitions for the Igniter Virtual Machine.
  # Specifies opcodes as 8-bit integers and their human-readable mnemonics.
  module Instructions
    # Opcodes mapping to unique 8-bit integers
    OP_PUSH_LIT    = 0x01 # Argument: literal value (Integer, Float, String, Bool)
    OP_LOAD_REF    = 0x02 # Argument: string symbol name
    OP_STORE_REG   = 0x03 # Argument: register index (Integer)
    OP_LOAD_REG    = 0x04 # Argument: register index (Integer)
    OP_ADD         = 0x05 # None
    OP_SUB         = 0x06 # None
    OP_MUL         = 0x07 # None
    OP_DIV         = 0x08 # None
    OP_EQ          = 0x09 # None
    OP_JMP         = 0x0A # Argument: instruction pointer offset (Integer)
    OP_JMP_IF      = 0x0B # Argument: instruction pointer offset (Integer)
    OP_JMP_UNLESS  = 0x0C # Argument: instruction pointer offset (Integer)
    OP_LOAD_AS_OF  = 0x0D # Arguments: [store_name, as_of_input_ref]
    OP_EMIT_OBS    = 0x0E # Argument: observation kind (String)
    OP_RET         = 0x0F # None
    OP_GT          = 0x10 # None
    OP_UNSUPPORTED = 0x99 # None

    # Mnemonic lookup mapping
    MNEMONICS = {
      OP_PUSH_LIT   => "PUSH_LIT",
      OP_LOAD_REF   => "LOAD_REF",
      OP_STORE_REG  => "STORE_REG",
      OP_LOAD_REG   => "LOAD_REG",
      OP_ADD        => "ADD",
      OP_SUB        => "SUB",
      OP_MUL        => "MUL",
      OP_DIV        => "DIV",
      OP_EQ         => "EQ",
      OP_GT         => "GT",
      OP_JMP        => "JMP",
      OP_JMP_IF     => "JMP_IF",
      OP_JMP_UNLESS => "JMP_UNLESS",
      OP_LOAD_AS_OF => "LOAD_AS_OF",
      OP_EMIT_OBS   => "EMIT_OBS",
      OP_RET        => "RET",
      OP_UNSUPPORTED => "UNSUPPORTED"
    }.freeze

    # Simple instruction wrapper representing a compiled instruction tuple
    class Instruction
      attr_reader :opcode, :args

      def initialize(opcode, *args)
        @opcode = opcode
        @args = args
      end

      def mnemonic
        MNEMONICS[@opcode] || "UNKNOWN(0x#{@opcode.to_s(16)})"
      end

      def to_s
        if @args.empty?
          mnemonic
        else
          "#{mnemonic} #{@args.map(&:inspect).join(', ')}"
        end
      end
    end
  end
end
