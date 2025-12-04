FROM node:24-alpine AS builder

# Gerekli araçları yüklüyoruz
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

# --- KRİTİK BÖLÜM: PostgreSQL şemasını SQLite'a çevirme ---
# 1. Postgres şemasını ana şema olarak kopyala
RUN cp ./prisma/postgresql-schema.prisma ./prisma/schema.prisma

# 2. Provider'ı sqlite yap
RUN sed -i 's/provider = "postgresql"/provider = "sqlite"/g' ./prisma/schema.prisma

# 3. PostgreSQL'e özel veri tiplerini (VarChar, JsonB, vb.) temizle
RUN sed -i 's/@db.VarChar([0-9]*)//g' ./prisma/schema.prisma && \
    sed -i 's/@db.Text//g' ./prisma/schema.prisma && \
    sed -i 's/@db.JsonB//g' ./prisma/schema.prisma && \
    sed -i 's/@db.Timestamp(6)//g' ./prisma/schema.prisma && \
    sed -i 's/@db.Timestamp//g' ./prisma/schema.prisma && \
    sed -i 's/@db.Boolean//g' ./prisma/schema.prisma && \
    sed -i 's/@db.Integer//g' ./prisma/schema.prisma

# 4. Artık temiz bir şemamız var, generate işlemi çalışacak
ENV DATABASE_PROVIDER=sqlite
RUN npx prisma generate

RUN npm run build

# --- FİNAL AŞAMASI ---
FROM node:24-alpine AS final

RUN apk update && \
    apk add tzdata ffmpeg bash openssl

ENV TZ=Europe/Istanbul
ENV DOCKER_ENV=true
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
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js
COPY --from=builder /evolution/tsup.config.ts ./tsup.config.ts

ENV DOCKER_ENV=true
EXPOSE 8080

# Uygulamayı başlat
CMD ["npm", "run", "start:prod"]
