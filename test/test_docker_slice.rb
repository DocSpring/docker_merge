# frozen_string_literal: true

require 'minitest/autorun'
require 'docker/slice'
require 'securerandom'
require 'pry-byebug'

# docker rmi -f $(docker images --filter=reference="merge-test-*" -q)

class TestDockerSlice < Minitest::Test
  def setup
    # Build some test Docker images that we can merge
    @dir = Dir.mktmpdir

    @input_tag = "slice-test:latest"
    images =
      `docker images --filter=reference="#{@input_tag}" -q`
      .chomp.split(/\s+/)
    return if images.any?

    puts "Building #{@input_tag}..."
    dockerfile = File.join(@dir, "Dockerfile.slice")
    File.open(dockerfile, 'w') do |f|
      f.puts <<~DOCKERFILE
        FROM alpine:3.7
        RUN echo "foo" > /tmp/a
        RUN echo "bar" > /tmp/b
        RUN echo "baz" > /tmp/c
        RUN echo "qux" > /tmp/d
        RUN echo "hello world" > /tmp/e
      DOCKERFILE
    end

    # puts "Building #{dockerfile} => #{@input_tag}"
    `docker build -f #{dockerfile} -t #{@input_tag} .`

    output = `docker run --rm #{@input_tag} sh -c "ls /tmp/*"`.chomp
    expected = ('a'..'e').to_a.map {|c| "/tmp/#{c}" }.join("\n")
    assert_equal expected, output
  end

  def teardown
    FileUtils.remove_entry @dir if @dir
    # Only delete the merged image. Initial images can be re-used.
    return unless @output_tags
    @output_tags.each do |output_tag|
      `docker rmi -f #{output_tag} || true`
    end
  end

  def test_that_docker_slice_works
    @output_tags = []
    output_tag = "slice-test:bar-#{SecureRandom.hex(5)}"
    @output_tags << output_tag
    Docker::Slice.new(output_tag, @input_tag, filters: ["bar"]).slice

    output = `docker run --rm #{output_tag} sh -c "ls /tmp/*"`.chomp
    assert_equal '/tmp/b', output

    docker_history = `docker history #{output_tag}`.lines
    assert_equal docker_history.count, 3
    assert_includes docker_history[1], 'echo "bar"'
    assert_includes docker_history[1], ' 4B '
    assert_includes docker_history[2], 'ADD file:'
  end
end
