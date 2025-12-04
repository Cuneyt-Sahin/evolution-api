FROM node:24-alpine AS builder

# Gerekli araçları kuruyoruz
RUN apk update && \
    apk add --no-cache git ffmpeg wget curl bash openssl dos2unix

WORKDIR /evolution

# Bağımlılık dosyalarını kopyala
COPY ./package*.json ./
COPY ./tsconfig.json ./
COPY ./tsup.config.ts ./

# Bağımlılıkları yükle
RUN npm ci --silent

# Kaynak kodları kopyala
COPY ./src ./src
COPY ./public ./public
COPY ./prisma ./prisma
COPY ./manager ./manager
COPY ./.env.example ./.env
COPY ./runWithProvider.js ./
COPY ./Docker ./Docker

# --- KRİTİK DÜZELTME BURASI ---
# 1. Scriptlerin çalıştırılabilir olması için izin ver ve formatı düzelt
RUN chmod +x ./Docker/scripts/* && dos2unix ./Docker/scripts/*

# 2. Veritabanı türünü SQLite olarak ayarla
ENV DATABASE_PROVIDER=sqlite

# 3. Evolution API'nin kendi scriptini çalıştırarak schema.prisma dosyasını OLUŞTUR
# Bu komut çalışmadan 'schema.prisma' dosyası oluşmaz!
RUN ./Docker/scripts/generate_database.sh

# 4. Oluşan şemaya göre Prisma Client'ı yarat
RUN npx prisma generate

# 5. Uygulamayı derle
RUN npm run build

# --- FİNAL AŞAMASI ---
FROM node:24-alpine AS final

RUN apk update && \
    apk add tzdata ffmpeg bash openssl

ENV TZ=Europe/Istanbul
ENV DOCKER_ENV=true
# Çalışma anında da SQLite olduğunu bilsin
ENV DATABASE_PROVIDER=sqlite

WORKDIR /evolution

# Derlenen dosyaları builder aşamasından kopyala
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
