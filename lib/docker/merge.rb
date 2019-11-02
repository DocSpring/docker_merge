# frozen_string_literal: true

require 'tmpdir'
require 'json'
require 'digest'
require 'docker/base'

module Docker
  # Merge multiple Docker images into a single Docker image.
  class Merge < Base
    attr_accessor :output_tag, :images

    def initialize(output_tag, images)
      @output_tag = output_tag
      @images = images
    end

    def merge
      image_dirs = {}
      images.each do |image|
        image_id = resolve_image_id(image)
        next if image_dirs[image_id]

        image_dirs[image_id] = dump_image(image)
      end

      raise "Couldn't find any images to merge!" if image_dirs.empty?

      output_dir = Dir.mktmpdir

      # Copy layers from all images
      merged_config = nil
      merged_manifest = nil

      layers = []
      layer_digests = Set.new
      image_dirs.each_with_index do |(_image, dir), image_index|
        manifest = JSON.parse(File.read("#{dir}/manifest.json"))
        config_digest = manifest['config']['digest'].sub(/sha256:/, '')
        config = JSON.parse(File.read("#{dir}/#{config_digest}"))

        if image_index.zero?
          merged_config = config
          merged_manifest = manifest
          # Copy the version file, e.g. "Directory Transport Version: 1.1\n"
          FileUtils.cp("#{dir}/version", "#{output_dir}/version")
        end

        layer_history = config['history'].reject { |l| l['empty_layer'] }

        manifest['layers'].each_with_index do |layer, layer_index|
          layer_digest = layer['digest'].sub(/sha256:/, '')
          next if layer_digests.include?(layer_digest)

          layer_digests << layer_digest

          # We use a forked skopeo with layer copying disabled
          # FileUtils.cp("#{dir}/#{layer_digest}", "#{output_dir}/#{layer_digest}")

          layers << {
            layer: layer,
            history: layer_history[layer_index]
          }
        end
      end

      merged_config['history'] = layers.map { |l| l[:history] }
      merged_config['rootfs']['diff_ids'] = layers.map { |l| l[:layer]['digest'] }
      merged_manifest['layers'] = layers.map { |l| l[:layer] }

      merged_config_json = merged_config.to_json
      merged_config_digest = Digest::SHA256.hexdigest merged_config_json
      File.open("#{output_dir}/#{merged_config_digest}", 'w') do |f|
        f.write merged_config_json
      end

      merged_manifest['config'] = {
        'mediaType' => 'application/vnd.docker.container.image.v1+json',
        'size' => merged_config_json.bytesize,
        'digest' => "sha256:#{merged_config_digest}"
      }
      File.open("#{output_dir}/manifest.json", 'w') do |f|
        f.write merged_manifest.to_json
      end

      # Finally, push the merged Docker image to the Docker daemon
      puts "Pushing merged Docker image to docker-daemon:#{output_tag}..."
      `skopeo --debug --insecure-policy copy dir:#{output_dir}/ "docker-daemon:#{output_tag}"`

      # Remove temp dirs
      image_dirs.each do |_image, dir|
        FileUtils.rm_r(dir, force: true)
      end
      FileUtils.rm_r(output_dir, force: true)
    end
  end
end
