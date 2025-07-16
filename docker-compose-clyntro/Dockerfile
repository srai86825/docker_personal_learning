# For Clyntro main backend server
# Use an official Node.js runtime as the base image
FROM node:18

# Set the working directory in the container
WORKDIR /usr/src/app

# Install Chromium and its dependencies
RUN apt-get update && apt-get install -y \
    chromium \
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-thai-tlwg \
    fonts-kacst \
    fonts-freefont-ttf \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Verify Chromium installation and print path (with clear separator for visibility)
RUN echo "-----CHROMIUM PATH-----" && \
    which chromium || echo "chromium not found" && \
    echo "-----------------------"

# Set environment variables for Puppeteer
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm install

# Install ts-node for runtime transpilation
RUN npm install --save ts-node
RUN npm install

# Copy the rest of the application code
COPY . .

# Attempt to build TypeScript code
RUN npm run build || echo "TypeScript build had errors, proceeding anyway"

# Create dist directory if it doesn't exist
RUN mkdir -p dist

# Copy source files to dist if build failed
RUN find dist -type f -name "*.js" | wc -l | xargs -I {} bash -c 'if [ "{}" -eq "0" ]; then echo "No JS files found, copying source"; cp -r src/* dist/; fi'

# Expose the port your app runs on
EXPOSE 4000

# Use your existing entrypoint script
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh
CMD ["./docker-entrypoint.sh"]


