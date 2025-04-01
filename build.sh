#!/bin/bash

# Configuration
DOCKERHUB_USERNAME="yourusername"
IMAGE_NAME="nmo"
TAG="latest"

# Parse command line arguments
BUILD_DOCKER=false
BUILD_SINGULARITY=false
PUSH_DOCKER=false
USE_SUDO=true
BUILD_METHOD="default"

while [[ $# -gt 0 ]]; do
  case $1 in
    --docker)
      BUILD_DOCKER=true
      shift
      ;;
    --singularity)
      BUILD_SINGULARITY=true
      shift
      ;;
    --push)
      PUSH_DOCKER=true
      shift
      ;;
    --all)
      BUILD_DOCKER=true
      BUILD_SINGULARITY=true
      PUSH_DOCKER=true
      shift
      ;;
    --no-sudo)
      USE_SUDO=false
      shift
      ;;
    --method)
      BUILD_METHOD=$2
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--docker] [--singularity] [--push] [--all] [--no-sudo] [--method METHOD]"
      echo "  METHOD can be: remote, fakeroot, userns, or sandbox"
      exit 1
      ;;
  esac
done

# If no options specified, show help
if [[ "$BUILD_DOCKER" == "false" && "$BUILD_SINGULARITY" == "false" ]]; then
  echo "Usage: $0 [--docker] [--singularity] [--push] [--all] [--no-sudo] [--method METHOD]"
  echo "  --docker      Build Docker image"
  echo "  --singularity Build Singularity image"
  echo "  --push        Push Docker image to DockerHub"
  echo "  --all         Build both images and push Docker image"
  echo "  --no-sudo     Build Singularity image without sudo"
  echo "  --method      Specify build method for Singularity: remote, fakeroot, userns, or sandbox"
  exit 0
fi

# Check for nmo binary
if [ ! -f "nmo" ]; then
  echo "Error: nmo binary not found in current directory"
  exit 1
fi

# Build Docker image
if [[ "$BUILD_DOCKER" == "true" ]]; then
  echo "Building Docker image..."
  docker build -t $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG .
  
  if [[ "$PUSH_DOCKER" == "true" ]]; then
    echo "Logging in to DockerHub..."
    docker login --username $DOCKERHUB_USERNAME
    
    echo "Pushing image to DockerHub..."
    docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG
    echo "Image pushed successfully to $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG"
  fi
fi

# Build Singularity image
if [[ "$BUILD_SINGULARITY" == "true" ]]; then
  # Check if we have singularity command
  if ! command -v singularity &> /dev/null; then
    echo "Error: Singularity is not installed or not in the PATH"
    exit 1
  fi
  
  # Check if we have a definition file or create one
  if [ ! -f "singularity.def" ]; then
    echo "Creating Singularity definition file..."
    cat > singularity.def << 'EOL'
Bootstrap: docker
From: debian:bullseye-slim

%files
    nmo /app/nmo

%post
    apt-get update && apt-get install -y \
        openssl \
        libssl-dev \
        ca-certificates \
        --no-install-recommends && \
        rm -rf /var/lib/apt/lists/*
    
    chmod +x /app/nmo
    mkdir -p /app/results /app/data /app/rules

%environment
    export PATH="/app:$PATH"
    export LC_ALL=C

%runscript
    exec /app/nmo "$@"

%help
    Nemo (nmo) is a datalog-based rule engine for fast and scalable analytic data processing in memory.
EOL
  fi
  
  # Build based on method and sudo preference
  if [[ "$USE_SUDO" == "true" ]]; then
    echo "Building Singularity image with sudo..."
    sudo singularity build nmo.sif singularity.def
  else
    case $BUILD_METHOD in
      remote)
        echo "Building Singularity image with remote builder..."
        singularity build --remote nmo.sif singularity.def
        ;;
      fakeroot)
        echo "Building Singularity image with --fakeroot..."
        singularity build --fakeroot nmo.sif singularity.def
        ;;
      userns)
        echo "Building Singularity image with user namespaces..."
        singularity build --userns nmo.sif singularity.def
        ;;
      sandbox)
        echo "Building Singularity sandbox (unprivileged)..."
        singularity build --sandbox nmo-sandbox singularity.def
        echo "NOTE: The sandbox is a directory that can be used with 'singularity run nmo-sandbox'"
        ;;
      *)
        echo "Error: When using --no-sudo, you must specify a build method with --method"
        echo "Available methods: remote, fakeroot, userns, or sandbox"
        exit 1
        ;;
    esac
  fi
  
  echo "Singularity image built successfully!"
  
  # Alternatively, build from Docker image if Docker was also built
  if [[ "$BUILD_DOCKER" == "true" ]]; then
    if [[ "$USE_SUDO" == "true" ]]; then
      echo "Building Singularity image from Docker image..."
      sudo singularity build nmo-from-docker.sif docker://$DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG
    else
      echo "Building Singularity image from Docker image without sudo..."
      singularity build --$BUILD_METHOD nmo-from-docker.sif docker://$DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG
    fi
    echo "Singularity image built successfully from Docker!"
  fi
fi

echo "Build process complete!"
