# frozen_string_literal: true

module RSpecTurbo
  # Discovers *_spec.rb files under the given folders (or all of spec/ if none
  # are given), de-duplicates them and applies --exclude-pattern glob filters.
  #
  # Returned paths are relative to spec/ (e.g. "models/user_spec.rb").
  class FileDiscovery
    FNMATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB

    def initialize(folders, exclude_patterns: [])
      @folders = folders
      @exclude_patterns = exclude_patterns
    end

    def files
      raw = collect_files

      return raw if @exclude_patterns.empty?

      raw.reject do |file|
        @exclude_patterns.any? { |pattern| File.fnmatch(pattern, "spec/#{file}", FNMATCH_FLAGS) }
      end
    end

    private

    def collect_files
      seen = Set.new
      found = []
      bases = @folders.empty? ? [""] : @folders

      bases.each do |folder|
        folder = folder.delete_prefix("spec/")
        folder = "" if folder == "spec"  # bare "spec" means the whole spec/ tree
        base = folder.empty? ? "spec" : File.join("spec", folder)

        if File.file?(base)
          found << folder if seen.add?(folder)
        elsif File.directory?(base)
          Dir.glob("#{base}/**/*_spec.rb").sort.each do |path|
            rel = path.delete_prefix("spec/")
            found << rel if seen.add?(rel)
          end
        else
          warn "▶ Skipping #{base} (not found)"
        end
      end

      found
    end
  end
end
