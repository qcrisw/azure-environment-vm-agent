FROM ubuntu:16.04

# To make it easier for build and release pipelines to run apt-get,
# configure apt to not require confirmation (assume the -y argument by default)
ENV DEBIAN_FRONTEND=noninteractive
RUN echo "APT::Get::Assume-Yes \"true\";" > /etc/apt/apt.conf.d/90assumeyes

RUN apt-get update \
&& apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        git \
        iputils-ping \
        libcurl3 \
        libicu55 \
        libunwind8 \
        netcat \
        gettext-base zip unzip sudo

# install git lfs
RUN curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && \
    apt-get install -y --no-install-recommends git-lfs && \
    git lfs install && \
    rm -r /var/lib/apt/lists/*

WORKDIR /azvm

# Install docker binary:
ARG docker_url=https://download.docker.com/linux/static/stable/x86_64
ARG docker_version=18.03.1-ce
RUN curl -fsSL $docker_url/docker-$docker_version.tgz | \
        tar zxvf - --strip 1 -C /usr/bin docker/docker

# Install kubectl binary:
ARG kubectl_url=https://storage.googleapis.com/kubernetes-release/release
RUN curl -fsSL $kubectl_url/`curl -s $kubectl_url/stable.txt`/bin/linux/amd64/kubectl \
  -o /usr/bin/kubectl && \
  chmod +x /usr/bin/kubectl && \
  kubectl version --client

# Install the Azure CLI binary with the DevOps extension
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    az --version && \
    az extension add -n azure-devops && \
    az extension list

COPY ./start.sh .
RUN chmod +x start.sh

CMD ["./start.sh"]
