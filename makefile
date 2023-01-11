IMAGE_NAME="docs-sync"

build-image:
	docker build --compress -t $IMAGE_NAME:latest .

requirements: 
	pipenv requirements > requirements.txt

terraform:
	terraform init
	terraform validate
	terraform plan -detailed-exitcode
