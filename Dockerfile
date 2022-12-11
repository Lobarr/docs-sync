# Use a pre-existing Python image as the base image for our Docker image
FROM python:3.11

# Set the working directory in the Docker image
WORKDIR /docs-sync

# Copy the requirements.txt file to the working directory
COPY requirements.txt .

# Install the required Python packages
RUN pip install -r requirements.txt

# Copy the rest of the files to the working directory
COPY . .

# Set the cmd for the Docker image to run the Python program
CMD ["python", "main.py"]
