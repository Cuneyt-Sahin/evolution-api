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

# --- DÜZELTME BURADA ---
# 1. Mevcut SQLite şemasını bulup ana şema dosyası olarak kopyalıyoruz
# (Evolution API'de dosya adı 'sqlite-schema.prisma' olabilir, onu kopyalıyoruz)
RUN cp ./prisma/sqlite-schema.prisma ./prisma/schema.prisma || echo "sqlite-schema.prisma bulunamadi, postgres'i donusturuyorum"

# 2. Eğer kopyalama başarısız olursa (dosya yoksa), postgres şemasını alıp sqlite'a çeviriyoruz
RUN if [ ! -f ./prisma/schema.prisma ]; then \
      cp ./prisma/postgresql-schema.prisma ./prisma/schema.prisma && \
      sed -i 's/provider = "postgresql"/provider = "sqlite"/g' ./prisma/schema.prisma; \
    fi

# 3. Artık 'schema.prisma' dosyamız kesin var, generate çalışır
RUN npx prisma generate

RUN npm run build

FROM node:24-alpine AS final

RUN apk update && \
    apk add tzdata ffmpeg bash openssl

ENV TZ=Europe/Istanbul
ENV DOCKER_ENV=true

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
