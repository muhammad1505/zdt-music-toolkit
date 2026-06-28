FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    git \
    make \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Add non-root user
RUN useradd -m -s /bin/bash zdtuser
USER zdtuser

# Setup working directory
WORKDIR /home/zdtuser/app

# Copy dependencies first for better caching
COPY --chown=zdtuser:zdtuser requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt
ENV PATH="/home/zdtuser/.local/bin:${PATH}"

# Copy source code
COPY --chown=zdtuser:zdtuser . .

# Run installation script to setup modules
RUN chmod +x install.sh && ./install.sh

# Expose Web Dashboard Port
EXPOSE 5000

# Healthcheck for Web Dashboard
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:5000/ || exit 1

# Set the default entrypoint
ENTRYPOINT ["/home/zdtuser/.local/bin/zdt"]
CMD ["--web-bind", "0.0.0.0"]
