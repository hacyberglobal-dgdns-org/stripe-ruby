FROM ruby:3.2-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock* ./
RUN bundle install --jobs 4 --retry 3

# Copy application
COPY . .

# Create log directory
RUN mkdir -p log

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/api/webhook || exit 1

# Run the application
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
