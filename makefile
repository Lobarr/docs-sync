IMAGE_NAME="docs-sync"

build-image:
	docker build --compress -t $IMAGE_NAME:latest .

requirments: 
	pipenv requirements > requirments.txt

terraform:
	terraform init
	terraform validate
	terraform plan -detailed-exitcode
