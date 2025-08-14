docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --use --name mybuilder
docker buildx inspect --bootstrap
