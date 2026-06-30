# frozen_string_literal: true

require "fileutils"

module TBackendRubyExtension
  module_function

  def build_and_require!(root: __dir__)
    Dir.chdir(root) do
      cmd = "RUSTFLAGS='-C link-arg=-undefined -C link-arg=dynamic_lookup' cargo build --release --features ffi"
      system(cmd) || raise("Failed to compile TBackend Rust extension")
      ensure_ruby_extension_alias!(File.join(root, "target", "release"))
    end

    $LOAD_PATH.unshift(File.join(root, "target", "release"))
    require "igniter_tbackend_playground"
  end

  def ensure_ruby_extension_alias!(release_dir)
    aliases = [
      ["libigniter_tbackend_playground.dylib", "igniter_tbackend_playground.bundle"],
      ["libigniter_tbackend_playground.so", "igniter_tbackend_playground.so"]
    ]

    aliases.each do |source_name, alias_name|
      source = File.join(release_dir, source_name)
      target = File.join(release_dir, alias_name)
      next unless File.exist?(source)
      next if File.exist?(target)

      begin
        File.symlink(source_name, target)
      rescue NotImplementedError, SystemCallError
        FileUtils.cp(source, target)
      end
    end
  end
end
