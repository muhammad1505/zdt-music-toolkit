FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    git \
    make \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Setup working directory
WORKDIR /app

# Copy source code
COPY . /app

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Run installation script to setup modules
RUN chmod +x install.sh && ./install.sh

# Set the default entrypoint
ENTRYPOINT ["/usr/local/bin/zdt"]
CMD ["--web-bind", "0.0.0.0"]
