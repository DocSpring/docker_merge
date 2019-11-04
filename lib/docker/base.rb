# frozen_string_literal: true

module Docker
  # Base class with shared methods
  class Base
    def ensure_deps
      skopeo_output = `skopeo --version`.chomp
      raise "skopeo command failed!" unless $?.success?
      return if skopeo_output&.include?('skopeo version')

      raise "Skopeo is required!\n" \
        "See: https://github.com/containers/skopeo\n" \
        "Install on Mac with: 'brew install skopeo'"
    end

    # Uses `docker images` to find a matching image ID
    def resolve_image_id(image)
      puts "Looking up image ID for #{image}..."
      resolved_images = `docker images --filter=reference="#{image}" -q`
                        .chomp.split(/\s+/)
      return resolved_images.first if resolved_images.count == 1

      if resolved_images.count.zero?
        raise "Could not find Docker image with the reference: #{image}!"
      end

      raise 'Found one more than one Docker image ' \
        "with the reference: #{image}!"
    end

    # Uses skopeo to dumps a docker image into a temporary directory
    # Returns: { dir: directory, id: image ID }
    #
    # Note: Image digests are not computed until the image is pushed.
    # So we can only support tags for now.
    # See: https://github.com/docker/cli/issues/728
    # Also: https://github.com/containers/skopeo
    #      (docker-daemon:docker-reference in README)
    #
    def dump_image(image)
      dir = Dir.mktmpdir
      puts "Dumping #{image} image to: #{dir}"
      `skopeo --debug --insecure-policy copy \
        "docker-daemon:#{image}" dir:#{dir}/`
      raise "skopeo command failed!" unless $?.success?
      dir
    end
  end
end
