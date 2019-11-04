# frozen_string_literal: true

require 'minitest/autorun'
require 'docker/merge'
require 'securerandom'
require 'pry-byebug'

# docker rmi -f $(docker images --filter=reference="merge-test-*" -q)

class TestDockerMerge < Minitest::Test
  def setup
    # Build some test Docker images that we can merge
    @dir = Dir.mktmpdir

    @image_tags = []
    { a: 'foo', b: 'bar', c: 'baz' }.each do |file, text|
      image_tag = "merge-test:#{file}"
      @image_tags << image_tag

      images =
        `docker images --filter=reference="#{image_tag}" -q`
        .chomp.split(/\s+/)
      next if images.any?

      puts "Building #{image_tag}..."
      dockerfile = File.join(@dir, "Dockerfile.#{file}")
      File.open(dockerfile, 'w') do |f|
        f.puts <<~DOCKERFILE
          FROM alpine:3.7
          RUN echo "#{text}" > /tmp/#{file}
        DOCKERFILE
      end

      # puts "Building #{dockerfile} => #{image_tag}"
      `docker build -f #{dockerfile} -t #{image_tag} .`

      output = `docker run --rm \
        #{image_tag} sh -c "cat /tmp/#{file}"`.chomp
      assert_equal text, output
    end
  end

  def teardown
    FileUtils.remove_entry @dir if @dir
    # Only delete the merged image. Initial images can be re-used.
    `docker rmi -f #{@output_tag} || true` if @output_tag
  end

  def test_that_docker_merge_works
    @output_tag = "merge-test:merged-#{SecureRandom.hex(5)}"
    Docker::Merge.new(@output_tag, @image_tags).merge

    output = `docker run --rm \
      #{@output_tag} sh -c "cat /tmp/a /tmp/b /tmp/c"`.chomp
    assert_equal "foo\nbar\nbaz", output

    # Make sure we can read the history (and it's not corrupted or anything)
    docker_history = `docker history #{@output_tag}`.lines
    puts "Docker History\n------------------------"
    puts docker_history.join
    assert_equal docker_history.count, 5
    assert_includes docker_history[0], 'IMAGE'
    assert_includes docker_history[1], 'echo "baz"'
    assert_includes docker_history[1], ' 4B '
    assert_includes docker_history[2], 'echo "bar"'
    assert_includes docker_history[2], ' 4B '
    assert_includes docker_history[3], 'echo "foo"'
    assert_includes docker_history[3], ' 4B '
    assert_includes docker_history[4], 'ADD file:'
  end
end
