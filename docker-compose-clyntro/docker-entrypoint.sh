#!/bin/bash
set -e

# Print environment for debugging (remove in production)
echo "Node Environment: $NODE_ENV"
echo "Database URL: ${DATABASE_URL:0:20}..." # Only print the beginning for security

# Wait for database to be available
if [ -n "$DATABASE_URL" ]; then
  echo "Checking database connection..."
  MAX_RETRIES=30
  RETRIES=0
  
  until npx prisma db execute --stdin < <(echo "SELECT 1;") &> /dev/null || [ $RETRIES -eq $MAX_RETRIES ]; do
    echo "Waiting for database to be ready... ($RETRIES/$MAX_RETRIES)"
    RETRIES=$((RETRIES+1))
    sleep 1
  done
  
  if [ $RETRIES -eq $MAX_RETRIES ]; then
    echo "Error: Could not connect to the database."
    exit 1
  fi
  
  echo "Database is available!"
fi

# Generate Prisma client
echo "Generating Prisma client..."
npx prisma generate 

# Run database migrations
if [ "$NODE_ENV" = "production" ]; then
  echo "Running Prisma migrations in production mode..."
  npx prisma migrate deploy
else
  echo "Running Prisma database push in development mode..."
  npx prisma db push --accept-data-loss
fi

# Start the application
echo "Starting the application..."
if [ "$NODE_ENV" = "development" ]; then
  echo "Starting in development mode with hot reloading..."
  exec npm run dev
else
  echo "Starting in production mode..."
  exec npm start
fi

# This line will only be reached if the exec commands above fail
echo "Application exited."
