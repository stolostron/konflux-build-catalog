
# Minimal Dockerfile to make repository buildable for Konflux
# This is a basic container that does nothing but allows build processes to complete

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Set metadata
LABEL \
      name="multicluster-engine/konflux-build-catalog-rhel9" \
      summary="konflux-build-catalog" \
      description="Konflux Build Catalog - Pipeline definitions" \
      io.k8s.description="konflux-build-catalog" \
      io.k8s.display-name="konflux-build-catalog" \
      com.redhat.component="multicluster-engine-konflux-build-catalog" \
      io.openshift.tags="data,images" \
      version="1.0.0"

ARG MCE_VERSION
ENV SOURCE_GIT_TAG=${MCE_VERSION}
RUN echo "SOURCE_GIT_TAG=${SOURCE_GIT_TAG}"

# Copy pipeline files to demonstrate this is a pipeline catalog
COPY pipelines/ /pipelines/
COPY .tekton/ /.tekton/

# Use existing user from base image (no network dependencies)
USER 1001

# Set working directory
WORKDIR /pipelines

# Default command that does nothing but keeps container running if needed
CMD ["sleep", "infinity"]
