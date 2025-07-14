# set the base image to create the image for react app
FROM node:20-alpine

# set the working directory to /app
WORKDIR /app

# copy package.json and package-lock.json to the working directory
# This is done before copying the rest of the files to take advantage of Docker's cache
COPY package*.json ./

# install dependencies (as root, no permission issues)
RUN npm install

# copy the rest of the files to the working directory
COPY . .

# create a group and user with permissions to run the app
# This is done to avoid running the app as root
RUN addgroup app_group && adduser -S -G app_group app_user

# change the ownership of the /app directory to the app user and group
# This fixes all file permissions in one go
RUN chown -R app_user:app_group /app

# set the user to run the app (only for runtime)
USER app_user

# expose port 5173 to tell Docker that the container listens on the specified network ports at runtime
EXPOSE 5173

# command to run the app (runs as 'app_user')
CMD ["npm", "run", "dev"]