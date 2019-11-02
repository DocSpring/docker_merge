# Docker Merge

A Ruby script that merges the unique layers from multiple Docker images into a single image.

## Why?

[Multi-stage builds](https://docs.docker.com/develop/develop-images/multistage-build/) can be really useful, but sometimes you need a bit more flexibility. Docker layers are "content-addressable", so the order doesn't really matter.

The `docker_merge` tool allows you to specify a re-usable cache directory, so you only need to update (and upload) any layers that have actually changed. This allows you to split up your Dockerfile into different components, and achieve much more powerful and flexible caching (while also using Docker's built-in caching.)

## Installation

```
gem install docker_merge
```

## Requirements

* Ruby
* [Skopeo](https://github.com/containers/skopeo)

## Usage

```
docker_merge -t <merged_tag> <input_tag_1> <input_tag_2> ...
```

## Gotchas

If you're building your Docker images locally, then image digests are not computed until the image is pushed. (See: https://github.com/docker/cli/issues/728)

The `skopeo` tool can only refer to images via tags or digests, so if the digests are missing, then you must refer to your images by tags.

## Additional Context

The config and manifest are taken from the first input image. The layers and history are modified to include all of the unique layers from the other images.

## References

* [A Peek into Docker Images](https://medium.com/tenable-techblog/a-peek-into-docker-images-b4d6b2362eb)
* [Accessing Docker Container File system from Mac OS host](http://www.vivekjuneja.in/tips/2016/12/02/docker-1.12.3-view-host-fs/)

## Related Projects

* [PowerShell-RegistryDocker](https://github.com/nicholasdille/PowerShell-RegistryDocker)
  * [How to Reduce the Build Time of a Monolithic #Docker Image](https://dille.name/blog/2018/08/19/how-to-reduce-the-build-time-of-a-monolithic-docker-image/)
  * [How to Automate the Merging of Layers from #Docker Images in #PowerShell](https://dille.name/blog/2018/09/07/how-to-automate-the-merging-of-layers-from-docker-images-in-powershell/)

## License

MIT
