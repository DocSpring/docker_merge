# frozen_string_literal: true

require 'tmpdir'
require 'json'
require 'digest'
require 'docker/base'

module Docker
  # Remove or include specific layers from a Docker image
  class Slice < Base
    attr_accessor :input_tag, :output_tag, :options

    def initialize(output_tag, input_tag, options = {})
      @input_tag = input_tag
      @output_tag = output_tag
      @options = options
    end

    def slice
      resolve_image_id(input_tag) # Ensures that the image exists
      image_dir = dump_image(input_tag)

      output_dir = Dir.mktmpdir

      layers = []

      manifest = JSON.parse(File.read("#{image_dir}/manifest.json"))
      config_digest = manifest['config']['digest'].sub(/sha256:/, '')
      config = JSON.parse(File.read("#{image_dir}/#{config_digest}"))

      output_config = config.dup
      output_manifest = manifest.dup

      # Copy the version file, e.g. "Directory Transport Version: 1.1\n"
      FileUtils.cp("#{image_dir}/version", "#{output_dir}/version")
      layer_histories = config['history'].reject { |l| l['empty_layer'] }

      manifest['layers'].each_with_index do |layer, layer_index|
        layer_history = layer_histories[layer_index]
        command = layer_history['created_by']

        # Always include the first layer
        if layer_index > 0
          # Check filters
          next unless options[:filters].any? do |filter|
            command.include?(filter)
          end
        end

        layer_digest = layer['digest'].sub(/sha256:/, '')

        FileUtils.cp("#{image_dir}/#{layer_digest}", "#{output_dir}/#{layer_digest}")

        layers << {
          layer: layer,
          history: layer_history
        }
      end

      output_config['history'] = layers.map { |l| l[:history] }
      output_config['rootfs']['diff_ids'] = layers.map { |l| l[:layer]['digest'] }
      output_manifest['layers'] = layers.map { |l| l[:layer] }

      output_config_json = output_config.to_json
      output_config_digest = Digest::SHA256.hexdigest output_config_json
      File.open("#{output_dir}/#{output_config_digest}", 'w') do |f|
        f.write output_config_json
      end

      output_manifest['config'] = {
        'mediaType' => 'application/vnd.docker.container.image.v1+json',
        'size' => output_config_json.bytesize,
        'digest' => "sha256:#{output_config_digest}"
      }
      File.open("#{output_dir}/manifest.json", 'w') do |f|
        f.write output_manifest.to_json
      end

      # Finally, push the merged Docker image to the Docker daemon
      puts "Pushing output Docker image to docker-daemon:#{output_tag}..."
      `skopeo --insecure-policy copy dir:#{output_dir}/ "docker-daemon:#{output_tag}"`

      # Remove temp dirs
      FileUtils.rm_r(image_dir, force: true)
      FileUtils.rm_r(output_dir, force: true)

      {
        layers: layers.count
      }
    end
  end
end
