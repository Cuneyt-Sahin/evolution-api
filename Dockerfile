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

# --- KESİN ÇÖZÜM: Mevcut şemayı silip, TEMİZ BİR SQLITE ŞEMASI OLUŞTURUYORUZ ---
RUN rm -f ./prisma/schema.prisma && \
    rm -f ./prisma/postgresql-schema.prisma && \
    echo 'generator client {' > ./prisma/schema.prisma && \
    echo '  provider = "prisma-client-js"' >> ./prisma/schema.prisma && \
    echo '}' >> ./prisma/schema.prisma && \
    echo '' >> ./prisma/schema.prisma && \
    echo 'datasource db {' >> ./prisma/schema.prisma && \
    echo '  provider = "sqlite"' >> ./prisma/schema.prisma && \
    echo '  url      = env("DATABASE_URL")' >> ./prisma/schema.prisma && \
    echo '}' >> ./prisma/schema.prisma && \
    # Postgres şemasının içeriğini alıyoruz ama @db... ile başlayan her şeyi siliyoruz
    cat ./prisma/postgresql-schema.prisma 2>/dev/null || true >> ./prisma/temp_schema && \
    sed 's/@db\.[a-zA-Z0-9]*\(\(.*\)\)\?//g' ./prisma/temp_schema >> ./prisma/schema.prisma && \
    rm ./prisma/temp_schema

# 2. Alternatif yöntem: Eğer yukarıdaki karışık gelirse, direkt çalışan şemayı indirtiyorum
# (Eğer üstteki çalışmazsa, Evolution API'nin eski sürümündeki temiz sqlite dosyasını çeker)
RUN wget -q -O ./prisma/schema.prisma https://raw.githubusercontent.com/EvolutionAPI/evolution-api/v1.8.2/prisma/schema.prisma || true

# 3. Ortamı SQLite olarak ayarla ve generate et
ENV DATABASE_PROVIDER=sqlite
RUN npx prisma generate

RUN npm run build

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

CMD ["npm", "run", "start:prod"]
