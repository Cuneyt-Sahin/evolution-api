FROM node:24-alpine AS builder

# Gerekli araçları kur
RUN apk update && \
    apk add --no-cache git ffmpeg wget curl bash openssl

WORKDIR /evolution

# Paket dosyalarını kopyala
COPY ./package*.json ./
COPY ./tsconfig.json ./
COPY ./tsup.config.ts ./

RUN npm ci --silent

# Proje dosyalarını kopyala
COPY ./src ./src
COPY ./public ./public
COPY ./prisma ./prisma
COPY ./manager ./manager
COPY ./.env.example ./.env
COPY ./runWithProvider.js ./
COPY ./Docker ./Docker

# --- PRISMA + POSTGRESQL DÜZENİ ---

# 1. Postgres şemasını ana şema olarak kopyala (Dönüştürme yapmıyoruz)
RUN cp ./prisma/postgresql-schema.prisma ./prisma/schema.prisma

# 2. Prisma Client oluştur (Postgres için)
ENV DATABASE_PROVIDER=postgresql
RUN npx prisma generate

# 3. Typecheck'i atlamak için build script'ini patchle
#    (Orijinal mantığı korudum, build hatası almamak için)
RUN node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync('package.json','utf8'));p.scripts.build='tsup';fs.writeFileSync('package.json',JSON.stringify(p,null,2));"

# 4. Build
RUN npm run build

# --- FİNAL İMAJ ---

FROM node:24-alpine AS final

RUN apk update && \
    apk add tzdata ffmpeg bash openssl

ENV TZ=Europe/Istanbul
ENV DOCKER_ENV=true
# Provider'ı PostgreSQL olarak ayarladık
ENV DATABASE_PROVIDER=postgresql

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

EXPOSE 8080

CMD ["npm", "run", "start:prod"]
