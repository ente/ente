# Publishing images

There are two different images we publish - internal and external.

## Internal

The internal images can be built and run by triggering the "Server (release)" workflow. You can trigger it either from GitHub's UI on the Actions tab, or use the following command:

```sh
gh workflow run server-release.yml
```

This will take the latest main, package it into a Docker image, and publish it to our Scaleway registry. From there, we can update our production instances to use this new image (see [deploy/README](../scripts/deploy/README.md)).

## External

Periodically, we republish a new image from an existing known-to-be-good commit to the GitHub Container Registry (GHCR) so that it can be used by folks without needing to clone our repository just for building an image. For more details about the use case, see [docker.md](docker.md).

These images are published automatically by the "Publish (server)" workflow on the 15th of every month. If needed, the workflow can also be manually triggered invoked to publish out of schedule. It can be triggered on the GitHub UI, or by

```sh
gh workflow run server-publish.yml
```

> It uses the commit that is deployed on production museum instances. We can publish from any arbitrary commit really, but by using the commit that's already seen production, we avoid externally publishing images with issues.

Once the workflow completes, the resultant image will be available at `ghcr.io/ente/server`. The image will be tagged by the commit SHA. The latest image will also be tagged, well, "latest".
