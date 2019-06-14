require 'sprockets/digest_utils'
require 'sprockets/uglifier_compressor'

module SprocketsUglifierWithSM
  class Compressor < Sprockets::UglifierCompressor

    DEFAULTS = { comments: false }

    def initialize(options = {})
      @options = DEFAULTS.merge(Rails.application.config.assets.uglifier.to_h).merge!(options)
      super @options
    end

    def call(input)
      data = input.fetch(:data)
      name = input.fetch(:name)

      if name.include? '-bundle'
        # Each webpack bundle already has a corresponding sourcemap, so let's use that
        sourcemap = JSON.parse(File.read("#{input[:filename]}.map"))
        sourcemap_json = sourcemap.to_json

        # Each webpack bundle is already minified, so let's only strip the existing
        # sourcemap reference; we'll replace it with a fingerprinted version below.
        compressed_data = data.sub(/\/\/# sourceMappingURL=.*$/, '').rstrip
      elsif /sourceMappingURL=data:application\/json;charset=utf-8;base64/.match(data).present?
        extra_options = {
          source_map: {
            :input_source_map => 'inline',
            :sources_content => true
          }
        }

        @options.merge extra_options
        uglifier = Sprockets::Autoload::Uglifier.new(@options)
        compressed_data, sourcemap_json = uglifier.compile_with_map(data)
      else
        uglifier = Sprockets::Autoload::Uglifier.new(@options)

        compressed_data, sourcemap_json = uglifier.compile_with_map(data)

        sourcemap = JSON.parse(sourcemap_json)

        if Rails.application.config.assets.sourcemaps_embed_source
          sourcemap['sourcesContent'] = [data]
        else
          uncompressed_filename = File.join(Rails.application.config.assets.prefix, Rails.application.config.assets.uncompressed_prefix, "#{name}-#{digest(data)}.js")
          uncompressed_path     = File.join(Rails.public_path, uncompressed_filename)
          uncompressed_url      = filename_to_url(uncompressed_filename)

          FileUtils.mkdir_p File.dirname(uncompressed_path)
          File.open(uncompressed_path, 'w') { |f| f.write data }
          gzip_file(uncompressed_path) if gzip?

          sourcemap['sources'] = [uncompressed_url]
        end
        sourcemap['file'] = "#{name}.js"

        sourcemap_json     = sourcemap.to_json
      end

      sourcemap_filename = File.join(Rails.application.config.assets.prefix, Rails.application.config.assets.sourcemaps_prefix, "#{name}-#{digest(sourcemap_json)}.js.map")
      sourcemap_path     = File.join(Rails.public_path, sourcemap_filename)
      sourcemap_url      = filename_to_url(sourcemap_filename)

      FileUtils.mkdir_p File.dirname(sourcemap_path)
      File.open(sourcemap_path, 'w') { |f| f.write sourcemap_json }
      gzip_file(sourcemap_path) if gzip?

      compressed_data.concat "\n//# sourceMappingURL=#{sourcemap_url}\n"
    end

    private

    def gzip?
      config = Rails.application.config.assets
      config.sourcemaps_gzip || (config.sourcemaps_gzip.nil? && config.gzip)
    end

    def gzip_file(path)
      Zlib::GzipWriter.open("#{path}.gz") do |gz|
        gz.mtime     = File.mtime(path)
        gz.orig_name = path
        gz.write IO.binread(path)
      end
    end

    def filename_to_url(filename)
      url_root = Rails.application.config.assets.sourcemaps_url_root
      case url_root
      when FalseClass
        filename
      when Proc
        url_root.call filename
      else
        File.join url_root.to_s, filename
      end
    end

    def digest(io)
      Sprockets::DigestUtils.pack_hexdigest Sprockets::DigestUtils.digest(io)
    end
  end
end
