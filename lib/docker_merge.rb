# frozen_string_literal: true

require 'tmpdir'
require 'json'
require 'digest'

# Merge multiple Docker images into a single Docker image.
class DockerMerge
  attr_accessor :tag, :images

  def initialize(tag, images)
    @tag = tag
    @images = images
  end

  def ensure_deps
    skopeo_output = `skopeo --version`.chomp
    return if skopeo_output&.include?('skopeo version')

    raise "Skopeo is required!\n" \
      "See: https://github.com/containers/skopeo\n" \
      "Install on Mac with: 'brew install skopeo'"
  end

  def dump_images
    image_dirs = {}
    images.each do |image|
      # Image digests are not computed until the image is pushed.
      # So we can only support tags for now.
      # See: https://github.com/docker/cli/issues/728
      # Also: https://github.com/containers/skopeo
      #      (docker-daemon:docker-reference in README)
      resolved_images = `docker images --filter=reference="#{image}" -q`
                        .chomp.split(/\s+/)
      if resolved_images.count.zero?
        raise "Could not find Docker image with the reference: #{image}!"
      end

      if resolved_images.count > 1
        raise 'Found one more than one Docker image ' \
          "with the reference: #{image}!"
      end

      image_id = resolved_images.first
      next if image_dirs[image_id]

      dir = Dir.mktmpdir
      image_dirs[image_id] = dir
      `skopeo --insecure-policy copy \
        "docker-daemon:#{image}" dir:#{dir}/`
    end

    image_dirs
  end

  def merge
    image_dirs = dump_images
    raise "Couldn't find any images to merge!" if image_dirs.empty?

    merged_dir = Dir.mktmpdir

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
        FileUtils.cp("#{dir}/version", "#{merged_dir}/version")
      end

      layer_history = config['history'].reject { |l| l['empty_layer'] }

      manifest['layers'].each_with_index do |layer, layer_index|
        layer_digest = layer['digest'].sub(/sha256:/, '')
        next if layer_digests.include?(layer_digest)

        layer_digests << layer_digest
        FileUtils.cp("#{dir}/#{layer_digest}", "#{merged_dir}/#{layer_digest}")
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
    File.open("#{merged_dir}/#{merged_config_digest}", 'w') do |f|
      f.write merged_config_json
    end

    merged_manifest['config'] = {
      'mediaType' => 'application/vnd.docker.container.image.v1+json',
      'size' => merged_config_json.bytesize,
      'digest' => "sha256:#{merged_config_digest}"
    }
    File.open("#{merged_dir}/manifest.json", 'w') do |f|
      f.write merged_manifest.to_json
    end

    # Finally, push the merged Docker image to the Docker daemon
    `skopeo --insecure-policy copy dir:#{merged_dir}/ "docker-daemon:#{tag}"`

    # Remove temp dirs
    image_dirs.each do |_image, dir|
      FileUtils.rm_r(dir, force: true)
    end
    FileUtils.rm_r(merged_dir, force: true)
  end
end
