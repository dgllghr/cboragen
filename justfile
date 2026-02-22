# Build a language codegen binary in release mode
# Usage: just build <lang-dir> [output-dir]
# Example: just build rust, just build typescript ~/.local/bin
build lang output_dir="~/.local/bin":
    cd languages/{{lang}}/codegen && zig build -Doptimize=ReleaseFast
    cp languages/{{lang}}/codegen/zig-out/bin/cboragen-* {{output_dir}}/
