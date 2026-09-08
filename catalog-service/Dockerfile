FROM node:20-alpine

ENV NODE_ENV=production

WORKDIR /app

COPY package.json .

RUN npm install --omit=dev \
    && npm cache clean --force

COPY --chown=node:node app.js .

USER node

EXPOSE 4000

CMD ["npm", "start"]
