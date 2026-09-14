FROM node:20.20.2-alpine3.23

ENV NODE_ENV=production

WORKDIR /app

RUN apk upgrade --no-cache

COPY package.json .

RUN npm install --omit=dev \
    && npm cache clean --force

COPY --chown=node:node app.js .

USER node

EXPOSE 4000

CMD ["npm", "start"]
