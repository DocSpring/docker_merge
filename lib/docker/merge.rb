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
      output_config = nil
      output_manifest = nil

      layers = []
      layer_digests = Set.new
      image_dirs.each_with_index do |(_image, dir), image_index|
        manifest = JSON.parse(File.read("#{dir}/manifest.json"))
        config_digest = manifest['config']['digest'].sub(/sha256:/, '')
        config = JSON.parse(File.read("#{dir}/#{config_digest}"))

        if image_index.zero?
          output_config = config
          output_manifest = manifest
          # Copy the version file, e.g. "Directory Transport Version: 1.1\n"
          FileUtils.mv("#{dir}/version", "#{output_dir}/version")
        end

        layer_history = config['history'].reject { |l| l['empty_layer'] }

        manifest['layers'].each_with_index do |layer, layer_index|
          layer_digest = layer['digest'].sub(/sha256:/, '')
          next if layer_digests.include?(layer_digest)

          layer_digests << layer_digest


          if layer_index > 0
            # We never need to upload a copy of the base layer (when using a forked skopeo)
            FileUtils.mv("#{dir}/#{layer_digest}", "#{output_dir}/#{layer_digest}")
          end

          puts "Including layer: #{layer_digest}"
          layers << {
            layer: layer,
            history: layer_history[layer_index]
          }
        end
      end

      output_config['history'] = layers.map { |l| l[:history] }#.reverse
      output_config['rootfs']['diff_ids'] = layers.map { |l| l[:layer]['digest'] }#.reverse
      output_manifest['layers'] = layers.map { |l| l[:layer] }#.reverse

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

      puts "Config\n------------------------"
      puts JSON.pretty_generate(output_config)
      puts "\n\nManifest\n------------------------"
      puts JSON.pretty_generate(output_manifest)


      # Finally, push the merged Docker image to the Docker daemon
      puts "Pushing merged Docker image to docker-daemon:#{output_tag}..."
      `skopeo --debug --insecure-policy copy dir:#{output_dir}/ "docker-daemon:#{output_tag}"`
      raise "skopeo command failed!" unless $?.success?

      # Remove temp dirs
      image_dirs.each do |_image, dir|
        FileUtils.rm_r(dir, force: true)
      end
      FileUtils.rm_r(output_dir, force: true)
    end
  end
end
