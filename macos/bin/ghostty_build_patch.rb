# Our embedding build disables i18n. Ghostty 1.2.3 nevertheless bundles libintl
# unconditionally on macOS; make that dependency follow the existing option.
class GhosttyBuildPatch
  def initialize(source_root)
    @path = File.join(source_root, 'src/build/SharedDeps.zig')
    @metal_path = File.join(source_root, 'src/build/MetallibStep.zig')
  end

  def apply
    # Honor our local xcrun wrapper for explicit SDK/toolchain selection.
    metal = File.read(@metal_path)
    File.write(@metal_path, metal.gsub('"/usr/bin/xcrun"', '"xcrun"'))
    original = '        if (b.lazyDependency("libintl", .{'
    replacement = '        if (self.config.i18n) if (b.lazyDependency("libintl", .{'
    source = File.read(@path)
    return if source.include?(replacement)
    abort 'Ghostty libintl build changed; review the licensing patch.' unless source.scan(original).length == 1
    start = source.index(original)
    ending = source.index("\n        }\n", start)
    abort 'Cannot locate Ghostty libintl block' unless ending
    source[ending, "\n        }\n".length] = "\n        };\n"
    File.write(@path, source.sub(original, replacement))
  end
end
