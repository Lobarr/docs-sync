# Use a pre-existing Python image as the base image for our Docker image
FROM python:3.11-alpine

# Set the working directory in the Docker image
WORKDIR /docs-sync

# Copy the Pipfiles to the working directory
COPY Pipfile .
COPY Pipfile.lock .

# Install the required Python packages
RUN pip install --upgrade pipenv \
  pipenv install

# Copy the rest of the files to the working directory
COPY . .

# Set the cmd for the Docker image to run the Python program
CMD ["python", "main.py"]
