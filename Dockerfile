FROM ubuntu:18.04 as builder
ARG JOBS=2
RUN apt-get update

ENV ZULU_OPENJDK_VERSION="11.37.48-ca-jdk11.0.6"
ENV ZULU_OPENJDK_PLATFORM="linux_aarch64"

ENV BUILD_DEPS \
    ca-certificates \
    zip \
    python \
    python3 \
    git \
    bzip2 \
    build-essential \
    curl \
    phantomjs \
    unzip
RUN apt-get update && apt-get install -y ${BUILD_DEPS}

# Build-stage environment variables
ENV ONOS_ROOT /src/onos
RUN mkdir -p /src/onos
ENV BUILD_NUMBER docker
ENV JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF8

# Install Bazel
COPY ./bazel ${ONOS_ROOT}
RUN mkdir -p /usr/lib/jvm

# Copy in the sources
WORKDIR ${ONOS_ROOT}
COPY . ${ONOS_ROOT}
COPY ./zulu${ZULU_OPENJDK_VERSION}-${ZULU_OPENJDK_PLATFORM}.tar.gz /tmp/zulu.tar.gz
RUN tar -zxf /tmp/zulu.tar.gz -C /usr/lib/jvm

RUN for x in /usr/lib/jvm/zulu${ZULU_OPENJDK_VERSION}-${ZULU_OPENJDK_PLATFORM}/bin/*; do \
    update-alternatives --install /usr/bin/$(basename $x) $(basename $x) $x 100; \
done

ENV JAVA_HOME=/usr/lib/jvm/zulu${ZULU_OPENJDK_VERSION}-${ZULU_OPENJDK_PLATFORM}


# Build ONOS using the JDK pre-installed in the base image, instead of the
# Bazel-provided remote one. By doing wo we make sure to build with the most
# updated JDK, including bug and security fixes, independently of the Bazel
# version.
RUN ./bazel build onos \
    --jobs ${JOBS} \
    --verbose_failures \
    --javabase=@bazel_tools//tools/jdk:absolute_javabase \
    --host_javabase=@bazel_tools//tools/jdk:absolute_javabase \
    --define=ABSOLUTE_JAVABASE=/usr/lib/jvm/zulu${ZULU_OPENJDK_VERSION}-${ZULU_OPENJDK_PLATFORM}

# We extract the tar in the build environment to avoid having to put the tar in
# the runtime stage. This saves a lot of space.
RUN mkdir /output
RUN tar -xf bazel-bin/onos.tar.gz -C /output --strip-components=1

# Second and final stage is the runtime environment.
FROM ubuntu:18.04
ENV ZULU_OPENJDK_VERSION="11.37.48-ca-jdk11.0.6"
ENV ZULU_OPENJDK_PLATFORM="linux_aarch64"

LABEL org.label-schema.name="ONOS" \
      org.label-schema.description="SDN Controller" \
      org.label-schema.usage="http://wiki.onosproject.org" \
      org.label-schema.url="http://onosproject.org" \
      org.label-scheme.vendor="Open Networking Foundation" \
      org.label-schema.schema-version="1.0" \
      maintainer="onos-dev@onosproject.org"

RUN apt-get update && apt-get install -y curl && \
        rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/lib/jvm
COPY ./zulu${ZULU_OPENJDK_VERSION}-${ZULU_OPENJDK_PLATFORM}.tar.gz /tmp/zulu.tar.gz
RUN tar -zxf /tmp/zulu.tar.gz -C /usr/lib/jvm

RUN for x in /usr/lib/jvm/zulu${ZULU_OPENJDK_VERSION}-${ZULU_OPENJDK_PLATFORM}/bin/*; do \
    update-alternatives --install /usr/bin/$(basename $x) $(basename $x) $x 100; \
done

# Install ONOS in /root/onos
COPY --from=builder /output/ /root/onos
WORKDIR /root/onos

# Set JAVA_HOME (by default not exported by zulu images)
ARG JDK_VER
ENV JAVA_HOME=/usr/lib/jvm/zulu${ZULU_OPENJDK_VERSION}-${ZULU_OPENJDK_PLATFORM}

# Ports
# 6653 - OpenFlow
# 6640 - OVSDB
# 8181 - GUI
# 8101 - ONOS CLI
# 9876 - ONOS intra-cluster communication
EXPOSE 6653 6640 8181 8101 9876

# Run ONOS
ENTRYPOINT ["./bin/onos-service"]
CMD ["server"]

