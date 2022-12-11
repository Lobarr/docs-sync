IMAGE_NAME="docs-sync"

build-image:
	docker build --compress -t $IMAGE_NAME:latest .

terraform:
	terraform init
	terraform validate
	terraform plan
