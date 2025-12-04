FROM node:24-alpine AS builder

RUN apk update && \
    apk add --no-cache git ffmpeg wget curl bash openssl

WORKDIR /evolution

COPY ./package*.json ./
COPY ./tsconfig.json ./
COPY ./tsup.config.ts ./

RUN npm ci --silent

COPY ./src ./src
COPY ./public ./public
COPY ./prisma ./prisma
COPY ./manager ./manager
COPY ./.env.example ./.env
COPY ./runWithProvider.js ./
COPY ./Docker ./Docker

# --- KESİN ÇÖZÜM: Environment Variable ile Şemayı Belirle ---
# Evolution API'nin build sistemi, DATABASE_PROVIDER değişkenine bakar.
# Eğer bu değişken 'sqlite' ise, otomatik olarak 'sqlite-schema.prisma' dosyasını kullanır.
ENV DATABASE_PROVIDER=sqlite

# Şimdi Prisma'yı çalıştırıyoruz. Environment variable sayesinde doğru dosyayı seçecek.
RUN npx prisma generate

RUN npm run build

FROM node:24-alpine AS final

RUN apk update && \
    apk add tzdata ffmpeg bash openssl

ENV TZ=Europe/Istanbul
ENV DOCKER_ENV=true
# Final aşamasında da SQLite olduğunu belirtiyoruz
ENV DATABASE_PROVIDER=sqlite

WORKDIR /evolution

COPY --from=builder /evolution/package.json ./package.json
COPY --from=builder /evolution/package-lock.json ./package-lock.json
COPY --from=builder /evolution/node_modules ./node_modules
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/.env ./.env
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js
COPY --from=builder /evolution/tsup.config.ts ./tsup.config.ts

ENV DOCKER_ENV=true
EXPOSE 8080

CMD ["npm", "run", "start:prod"]
