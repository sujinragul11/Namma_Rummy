FROM node:22-slim

WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY src ./src

USER node
EXPOSE 3001

# Creating the tables is safe to repeat, so it runs on every start
CMD ["sh", "-c", "node src/database/migrate.js && node src/server.js"]
