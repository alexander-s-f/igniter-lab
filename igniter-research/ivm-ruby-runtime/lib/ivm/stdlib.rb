# frozen_string_literal: true

require "fiddle"

module IVM
  # FFI wrapper binding the Igniter Virtual Machine to the Rust stdlib
  module Stdlib
    class StdlibError < StandardError; end
    class ScaleMismatchError < StdlibError; end
    class DivisionError < StdlibError; end

    # Paths to compiled stdlib binaries
    LIB_NAME = RUBY_PLATFORM.include?("darwin") ? "libigniter_stdlib.dylib" : "libigniter_stdlib.so"
    LIB_PATH = File.expand_path("../../../../igniter-stdlib/target/release/#{LIB_NAME}", __dir__)

    begin
      @extern = Fiddle.dlopen(LIB_PATH)

      # Bind FFI functions
      @stdlib_decimal_add = Fiddle::Function.new(
        @extern["stdlib_decimal_add"],
        [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )

      @stdlib_decimal_sub = Fiddle::Function.new(
        @extern["stdlib_decimal_sub"],
        [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )

      @stdlib_decimal_mul = Fiddle::Function.new(
        @extern["stdlib_decimal_mul"],
        [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_VOID
      )

      @stdlib_decimal_div = Fiddle::Function.new(
        @extern["stdlib_decimal_div"],
        [Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_INT
      )

      @loaded = true
    rescue => e
      @loaded = false
      # Fallback mode warning
      warn "[!] Igniter Stdlib dynamic library load failed (operating in fallback mode): #{e.message}"
    end

    def self.loaded?
      @loaded == true
    end

    # FFI decimal addition
    def self.decimal_add(a_val, a_scale, b_val, b_scale)
      raise StdlibError, "stdlib not loaded" unless loaded?
      
      out_val = Fiddle::Pointer.to_ptr("\x00" * 8)
      out_scale = Fiddle::Pointer.to_ptr("\x00" * 4)

      err = @stdlib_decimal_add.call(a_val, a_scale, b_val, b_scale, out_val, out_scale)
      if err == 1
        raise ScaleMismatchError, "OOF-TC5: Scale mismatch on addition: Decimal[#{a_scale}] + Decimal[#{b_scale}]"
      end

      [out_val[0, 8].unpack1("q"), out_scale[0, 4].unpack1("l")]
    end

    # FFI decimal subtraction
    def self.decimal_sub(a_val, a_scale, b_val, b_scale)
      raise StdlibError, "stdlib not loaded" unless loaded?
      
      out_val = Fiddle::Pointer.to_ptr("\x00" * 8)
      out_scale = Fiddle::Pointer.to_ptr("\x00" * 4)

      err = @stdlib_decimal_sub.call(a_val, a_scale, b_val, b_scale, out_val, out_scale)
      if err == 1
        raise ScaleMismatchError, "OOF-TC5: Scale mismatch on subtraction: Decimal[#{a_scale}] - Decimal[#{b_scale}]"
      end

      [out_val[0, 8].unpack1("q"), out_scale[0, 4].unpack1("l")]
    end

    # FFI decimal multiplication
    def self.decimal_mul(a_val, a_scale, b_val, b_scale)
      raise StdlibError, "stdlib not loaded" unless loaded?
      
      out_val = Fiddle::Pointer.to_ptr("\x00" * 8)
      out_scale = Fiddle::Pointer.to_ptr("\x00" * 4)

      @stdlib_decimal_mul.call(a_val, a_scale, b_val, b_scale, out_val, out_scale)
      [out_val[0, 8].unpack1("q"), out_scale[0, 4].unpack1("l")]
    end

    # FFI decimal division
    def self.decimal_div(a_val, a_scale, b_val, b_scale)
      raise StdlibError, "stdlib not loaded" unless loaded?
      
      out_val = Fiddle::Pointer.to_ptr("\x00" * 8)
      out_scale = Fiddle::Pointer.to_ptr("\x00" * 4)

      err = @stdlib_decimal_div.call(a_val, a_scale, b_val, b_scale, out_val, out_scale)
      if err == 2
        raise DivisionError, "OOF-DM2: Division by zero or scale underflow error"
      end

      [out_val[0, 8].unpack1("q"), out_scale[0, 4].unpack1("l")]
    end
  end
end
