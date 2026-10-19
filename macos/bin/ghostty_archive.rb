require 'fileutils'
require 'open3'
require 'tmpdir'

# Xcode 27's libtool drops members when merging Zig 0.14 archives directly.
# Extract the exact inputs recorded by Zig, then archive their object files.
class GhosttyArchive
  def initialize(source_root)
    @source_root = File.expand_path(source_root)
  end

  def stage(destination)
    inputs = archive_inputs
    abort 'Unexpected libintl input; check the Ghostty build patch.' if inputs.any? { |path| File.basename(path) == 'libintl.a' }
    Dir.mktmpdir('ghostty-archive-', File.join(@source_root, '.zig-cache')) do |temporary|
      objects = inputs.each_with_index.flat_map do |archive, index|
        directory = File.join(temporary, index.to_s)
        FileUtils.mkdir_p(directory)
        Dir.chdir(directory) { run('/usr/bin/ar', '-x', archive) }
        Dir.children(directory).map do |name|
          next if name.start_with?('__.SYMDEF')
          path = File.join(directory, name)
          next unless File.file?(path)
          FileUtils.chmod(0o644, path)
          # Distinct names preserve same-named objects from separate libraries.
          renamed = File.join(directory, "#{index}_#{name}")
          FileUtils.mv(path, renamed)
          renamed
        end.compact
      end
      abort 'No Ghostty object files found' if objects.empty?
      run('/usr/bin/libtool', '-static', '-o', File.expand_path(destination), *objects)
    end
    symbols, status = Open3.capture2('/usr/bin/nm', '-g', destination)
    abort 'Staged archive does not export ghostty_init' unless status.success? && symbols.match?(/\bT _ghostty_init$/)
  end

  private

  def archive_inputs
    # For this pinned Ghostty release, the libtool step's Zig cache manifest
    # records every input archive, including the core and native dependencies.
    candidates = Dir[File.join(@source_root, '.zig-cache/h/*.txt')].map do |manifest|
      paths = File.readlines(manifest).map do |line|
        relative = line.split.last
        File.join(@source_root, relative) if relative&.match?(%r{\A\.zig-cache/o/[^/]+/[^/]+\.a\z})
      end.compact
      next unless paths.any? { |p| File.basename(p) == 'libghostty.a' } &&
                  paths.any? { |p| File.basename(p) == 'libpng.a' } && paths.all? { |p| File.file?(p) }
      [File.mtime(manifest), paths]
    end.compact
    abort 'Could not locate Ghostty archive input manifest; rerun dependency setup.' if candidates.empty?
    candidates.max_by(&:first).last
  end

  def run(*arguments)
    abort "Command failed: #{arguments.join(' ')}" unless system(*arguments)
  end
end
