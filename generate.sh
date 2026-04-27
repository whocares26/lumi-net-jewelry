#!/bin/bash
# ================================================================
# lumi-net — Генератор проекта ИС для сети ювелирных магазинов
# Стек: C++17/Drogon · PostgreSQL 15 · Nginx · Docker Compose
# Использование: chmod +x generate.sh && ./generate.sh
# ================================================================
set -e

PROJ="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${BLUE}▶${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
hdr()  { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

echo -e "${BOLD}
██╗     ██╗   ██╗███╗   ███╗██╗    ███╗   ██╗███████╗████████╗
██║     ██║   ██║████╗ ████║██║    ████╗  ██║██╔════╝╚══██╔══╝
██║     ██║   ██║██╔████╔██║██║    ██╔██╗ ██║█████╗     ██║
██║     ██║   ██║██║╚██╔╝██║██║    ██║╚██╗██║██╔══╝     ██║
███████╗╚██████╔╝██║ ╚═╝ ██║██║    ██║ ╚████║███████╗   ██║
╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝    ╚═╝  ╚═══╝╚══════╝   ╚═╝
${NC}${BLUE}  Информационная система сети ювелирных магазинов${NC}\n"

# ─── Предвычисление хэшей паролей ────────────────────────────────────────────
if ! command -v openssl &>/dev/null; then
  warn "openssl не найден — используем захардкоженные хэши"
  ADMIN_HASH="240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9"
  PASS_HASH="9b8769a4a742959a2d0298c36fb70623f2a2d0d78f90c0e6bde3f19bfd4afde"
else
  ADMIN_HASH=$(echo -n "admin123" | openssl dgst -sha256 | sed 's/.* //')
  PASS_HASH=$(echo -n "pass123"  | openssl dgst -sha256 | sed 's/.* //')
fi

hdr "1. Структура директорий"
mkdir -p "$PROJ"/{backend/src/{controllers,utils,filters},frontend/{css,js},nginx}
ok "Директории созданы"

# ═══════════════════════════════════════════════════════════════
# DOCKER COMPOSE
# ═══════════════════════════════════════════════════════════════
hdr "2. Docker Compose"
cat > "$PROJ/docker-compose.yml" << 'YAML_EOF'
version: '3.9'

services:
  db:
    image: postgres:15-alpine
    container_name: lumidb
    restart: unless-stopped
    environment:
      POSTGRES_DB: lumidb
      POSTGRES_USER: lumi
      POSTGRES_PASSWORD: lumipass
    volumes:
      - ./database/create_tables.sql:/docker-entrypoint-initdb.d/01_tables.sql:ro
      - ./database/create_triggers_and_procedure.sql:/docker-entrypoint-initdb.d/02_triggers.sql:ro
      - ./database/seed.sql:/docker-entrypoint-initdb.d/03_seed.sql:ro
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U lumi -d lumidb"]
      interval: 5s
      timeout: 5s
      retries: 15

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: lumi-backend
    restart: unless-stopped
    environment:
      DB_HOST: db
      DB_PORT: 5432
      DB_NAME: lumidb
      DB_USER: lumi
      DB_PASS: lumipass
      JWT_SECRET: lumi_net_jewelry_2025_secret_key
    ports:
      - "8080:8080"
    depends_on:
      db:
        condition: service_healthy

  frontend:
    image: nginx:alpine
    container_name: lumi-frontend
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./frontend:/usr/share/nginx/html:ro
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - backend

volumes:
  pgdata:
YAML_EOF
ok "docker-compose.yml"

# ═══════════════════════════════════════════════════════════════
# NGINX CONFIG
# ═══════════════════════════════════════════════════════════════
hdr "3. Nginx"
cat > "$PROJ/nginx/nginx.conf" << 'NGINX_EOF'
server {
    listen 80;
    server_name localhost;
    charset utf-8;

    root /usr/share/nginx/html;
    index index.html;

    location /api/ {
        proxy_pass         http://backend:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   Connection        "";
        proxy_read_timeout 60s;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
}
NGINX_EOF
ok "nginx/nginx.conf"

# ═══════════════════════════════════════════════════════════════
# DATABASE SEED (uses computed password hashes)
# ═══════════════════════════════════════════════════════════════
hdr "4. Database seed"
cat > "$PROJ/database/seed.sql" << SQL_EOF
-- ================================================================
-- lumi-net seed data
-- ================================================================

-- Таблица пользователей для аутентификации
CREATE TABLE IF NOT EXISTS app_users (
    user_id       SERIAL PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash CHAR(64)     NOT NULL,
    role          VARCHAR(20)  NOT NULL CHECK(role IN ('CLIENT','CASHIER','MANAGER','ADMIN')),
    ref_snils     CHAR(14),
    ref_client_id INT
);

CREATE INDEX IF NOT EXISTS idx_app_users_username ON app_users(username);

-- ─── Managers ────────────────────────────────────────────────
INSERT INTO MANAGER (manager_snils, manager_fio) VALUES
  ('12345678901234', 'Иванов Сергей Петрович'),
  ('23456789012345', 'Петрова Анна Михайловна'),
  ('34567890123456', 'Волков Дмитрий Алексеевич'),
  ('45678901234567', 'Смирнова Екатерина Игоревна');

-- ─── Stores ──────────────────────────────────────────────────
INSERT INTO STORE (manager_snils, store_address, store_phone) VALUES
  ('12345678901234', 'г. Москва, ул. Тверская, д. 1',          '+7 (495) 100-00-01'),
  ('23456789012345', 'г. Москва, ул. Арбат, д. 2',             '+7 (495) 100-00-02'),
  ('34567890123456', 'г. Москва, ул. Кузнецкий мост, д. 4',    '+7 (495) 100-00-03'),
  ('45678901234567', 'г. Москва, ул. Новинский бульвар, д. 18','+7 (495) 100-00-04');

-- ─── Cashiers ────────────────────────────────────────────────
INSERT INTO CASHIER (cashier_snils, manager_snils, cashier_fio) VALUES
  ('11111111111111', '12345678901234', 'Сидоров Алексей Иванович'),
  ('22222222222222', '12345678901234', 'Козлова Мария Сергеевна'),
  ('33333333333333', '23456789012345', 'Новиков Павел Дмитриевич'),
  ('44444444444444', '23456789012345', 'Федорова Ольга Вячеславовна'),
  ('55555555555555', '34567890123456', 'Кузнецов Андрей Борисович'),
  ('66666666666666', '45678901234567', 'Попова Ирина Николаевна');

-- ─── Suppliers ───────────────────────────────────────────────
INSERT INTO SUPPLIER (supplier_name, supplier_email, supplier_phone) VALUES
  ('ООО "Золотая Лавка"',   'contact@zolotaya-lavka.ru', '+7 (495) 200-00-01'),
  ('АО "Серебряный Берег"', 'info@silver-shore.ru',      '+7 (495) 200-00-02'),
  ('ИП "Бриллиант Удачи"',  'order@brillant.ru',         '+7 (495) 200-00-03');

-- ─── Products ────────────────────────────────────────────────
INSERT INTO PRODUCT (product_article, product_category, product_price, product_name) VALUES
  (100001, 'Кольца',    25000, 'Кольцо "Романтика" (золото 585)'),
  (100002, 'Кольца',    38000, 'Кольцо с бриллиантом "Вечность"'),
  (100003, 'Кольца',    15000, 'Кольцо обручальное (белое золото)'),
  (100004, 'Серьги',    18000, 'Серьги "Капля" с изумрудом'),
  (100005, 'Серьги',    22000, 'Серьги-гвоздики с бриллиантами'),
  (100006, 'Серьги',    12000, 'Серьги "Луна" (серебро 925)'),
  (100007, 'Браслеты',  45000, 'Браслет теннисный с бриллиантами'),
  (100008, 'Браслеты',  28000, 'Браслет "Плетение" (золото 585)'),
  (100009, 'Браслеты',  19000, 'Браслет с сапфирами'),
  (100010, 'Подвески',  32000, 'Подвеска "Сердце" с рубином'),
  (100011, 'Подвески',  16000, 'Подвеска "Крест" (золото 585)'),
  (100012, 'Подвески',   9000, 'Подвеска с жемчугом'),
  (100013, 'Цепочки',   14000, 'Цепочка "Фигаро" (золото 585)'),
  (100014, 'Цепочки',   11000, 'Цепочка плетение "Якорь"'),
  (100015, 'Часы',     125000, 'Часы "Grand Classic" (золото)'),
  (100016, 'Часы',      85000, 'Часы женские с бриллиантами'),
  (100017, 'Броши',     21000, 'Брошь "Бабочка" с аметистом'),
  (100018, 'Броши',     17000, 'Брошь "Цветок" (серебро+эмаль)'),
  (100019, 'Кольца',    55000, 'Кольцо с крупным бриллиантом'),
  (100020, 'Серьги',    41000, 'Серьги с рубинами (золото 750)');

-- ─── Clients ─────────────────────────────────────────────────
INSERT INTO CLIENT (client_phone, client_email, client_fio) VALUES
  ('+7 (495) 123-45-60', 'kuznetcov@mail.ru',    'Кузнецов Дмитрий Петрович'),
  ('+7 (495) 123-45-61', 'petrov.a@gmail.com',   'Петров Александр Сергеевич'),
  ('+7 (495) 123-45-62', 'sidorova@yandex.ru',   'Сидорова Мария Ивановна'),
  ('+7 (495) 123-45-63', 'volkov@mail.ru',        'Волков Андрей Николаевич'),
  ('+7 (495) 123-45-64', 'smirnova@gmail.com',   'Смирнова Ольга Александровна'),
  ('+7 (495) 123-45-65', 'morozov@yandex.ru',    'Морозов Михаил Владимирович'),
  ('+7 (495) 123-45-66', 'nikolaeva@mail.ru',    'Николаева Ева Сергеевна'),
  ('+7 (495) 123-45-67', 'ivanov.al@gmail.com',  'Иванов Алексей Борисович'),
  ('+7 (495) 123-45-68', 'fedorova@yandex.ru',   'Федорова Анна Алексеевна'),
  ('+7 (495) 123-45-69', 'popova.k@mail.ru',     'Попова Ксения Дмитриевна');

-- ─── Stock ───────────────────────────────────────────────────
-- Магазин 1
INSERT INTO STOCK (store_id, stock_id, product_article, stock_quantity) VALUES
  (1,1,100001,3),(1,2,100002,2),(1,3,100003,5),(1,4,100004,4),(1,5,100005,3),
  (1,6,100007,2),(1,7,100008,4),(1,8,100010,3),(1,9,100013,6),(1,10,100015,1),
  (1,11,100019,1),(1,12,100020,2);
-- Магазин 2
INSERT INTO STOCK (store_id, stock_id, product_article, stock_quantity) VALUES
  (2,1,100001,2),(2,2,100003,3),(2,3,100004,5),(2,4,100006,4),(2,5,100007,1),
  (2,6,100009,3),(2,7,100011,4),(2,8,100012,6),(2,9,100014,5),(2,10,100016,1),
  (2,11,100017,2),(2,12,100018,3);
-- Магазин 3
INSERT INTO STOCK (store_id, stock_id, product_article, stock_quantity) VALUES
  (3,1,100002,1),(3,2,100005,3),(3,3,100008,2),(3,4,100010,4),(3,5,100013,3),
  (3,6,100015,1),(3,7,100019,1),(3,8,100001,4),(3,9,100004,2),(3,10,100007,3);
-- Магазин 4
INSERT INTO STOCK (store_id, stock_id, product_article, stock_quantity) VALUES
  (4,1,100003,6),(4,2,100006,3),(4,3,100009,2),(4,4,100012,5),(4,5,100014,4),
  (4,6,100016,2),(4,7,100018,3),(4,8,100020,1),(4,9,100001,2),(4,10,100011,4);

-- ─── Sales ───────────────────────────────────────────────────
INSERT INTO SALE (client_id,cashier_snils,store_id,sale_total,sale_payment_method,sale_date) VALUES
  (1,'11111111111111',1, 45000,'Карта',      '2024-11-01'),
  (2,'11111111111111',1, 38000,'Наличные',   '2024-11-03'),
  (3,'22222222222222',1, 22000,'Карта',      '2024-11-05'),
  (4,'33333333333333',2, 45000,'Карта',      '2024-11-07'),
  (5,'33333333333333',2, 18000,'Наличные',   '2024-11-09'),
  (1,'44444444444444',2, 28000,'Карта',      '2024-11-11'),
  (6,'55555555555555',3, 32000,'Безнал',     '2024-11-12'),
  (7,'55555555555555',3, 25000,'Карта',      '2024-11-14'),
  (8,'66666666666666',4, 85000,'Карта',      '2024-11-15'),
  (9,'66666666666666',4, 14000,'Наличные',   '2024-11-16'),
  (10,'11111111111111',1,145000,'Карта',     '2024-11-18'),
  (2,'22222222222222',1, 19000,'Наличные',   '2024-11-19'),
  (3,'33333333333333',2, 41000,'Карта',      '2024-11-20'),
  (1,'11111111111111',1,185000,'Карта',      '2024-11-21'),
  (4,'44444444444444',2, 21000,'Наличные',   '2024-11-22'),
  (5,'55555555555555',3, 38000,'Карта',      '2024-11-23'),
  (6,'66666666666666',4, 55000,'Безнал',     '2024-11-25'),
  (7,'11111111111111',1, 16000,'Наличные',   '2024-11-26'),
  (8,'33333333333333',2, 22000,'Карта',      '2024-11-27'),
  (9,'55555555555555',3,125000,'Карта',      '2024-11-28'),
  (10,'66666666666666',4,45000,'Наличные',   '2024-11-29'),
  (1,'11111111111111',1, 28000,'Карта',      '2024-12-01'),
  (2,'22222222222222',1, 32000,'Карта',      '2024-12-03'),
  (3,'33333333333333',2, 18000,'Наличные',   '2024-12-05');

-- ─── Sale Items ───────────────────────────────────────────────
INSERT INTO SALE_ITEM (sale_id,sale_item_id,product_article,sale_item_quantity) VALUES
  (1,1,100010,1),(2,1,100002,1),(3,1,100005,1),(4,1,100004,1),(4,2,100006,1),
  (5,1,100004,1),(6,1,100008,1),(7,1,100010,1),(8,1,100016,1),(9,1,100013,1),
  (10,1,100005,1),(10,2,100007,2),(11,1,100019,1),(11,2,100004,2),(12,1,100006,1),
  (12,2,100012,1),(13,1,100020,1),(14,1,100015,1),(14,2,100013,1),(15,1,100017,1),
  (16,1,100002,1),(17,1,100019,1),(18,1,100011,2),(19,1,100005,1),(20,1,100015,1),
  (21,1,100001,1),(21,2,100003,1),(22,1,100008,1),(23,1,100010,1),(24,1,100004,1),(24,2,100006,1);

-- ─── Orders ──────────────────────────────────────────────────
INSERT INTO "ORDER" (store_id,supplier_id,manager_snils,order_date,order_status,order_total) VALUES
  (1,1,'12345678901234','2024-11-10','Доставлен',   150000),
  (2,2,'23456789012345','2024-11-15','Доставлен',    85000),
  (3,3,'34567890123456','2024-12-01','В пути',       210000),
  (4,1,'45678901234567','2024-12-05','В пути',       95000),
  (1,2,'12345678901234','2024-12-10','В обработке', 175000),
  (2,3,'23456789012345','2024-12-12','В обработке',  65000),
  (3,1,'34567890123456','2024-12-15','Ожидается',   320000),
  (1,3,'12345678901234','2024-11-01','Доставлен',    45000);

INSERT INTO ORDER_ITEM (order_id,order_item_id,product_article,order_item_quantity) VALUES
  (1,1,100001,3),(1,2,100002,2),(1,3,100007,2),
  (2,1,100004,5),(2,2,100006,3),
  (3,1,100015,1),(3,2,100016,1),(3,3,100019,2),
  (4,1,100003,5),(4,2,100011,4),
  (5,1,100005,3),(5,2,100010,4),(5,3,100013,5),
  (6,1,100017,2),(6,2,100018,3),
  (7,1,100002,3),(7,2,100007,4),(7,3,100008,2),(7,4,100020,3),
  (8,1,100012,5);

-- ─── Reviews ─────────────────────────────────────────────────
INSERT INTO REVIEW (client_id,review_rating,review_comment,review_date) VALUES
  (1,5,'Великолепное кольцо! Жена в восторге. Упаковка роскошная.',         '2024-11-05'),
  (2,4,'Красивые серьги, немного долго ждал заказ, но результат отличный.',  '2024-11-08'),
  (3,5,'Браслет просто невероятный. Качество изготовления на высшем уровне.','2024-11-13'),
  (4,5,'Покупал кольцо для помолвки — невеста счастлива! Спасибо.',          '2024-11-16'),
  (5,4,'Хорошее качество, цена соответствует. Буду заказывать ещё.',         '2024-11-22'),
  (6,5,'Подвеска с рубином — настоящее произведение искусства!',             '2024-11-26'),
  (7,3,'Серьги чуть отличаются от фото, но в целом понравились.',            '2024-11-29'),
  (8,5,'Часы превзошли все ожидания. Механизм точный, внешний вид шикарный.','2024-12-02');

-- ─── App Users ────────────────────────────────────────────────
INSERT INTO app_users (username, password_hash, role, ref_snils, ref_client_id) VALUES
  ('admin',    '${ADMIN_HASH}', 'ADMIN',   NULL,             NULL),
  ('manager1', '${PASS_HASH}',  'MANAGER', '12345678901234', NULL),
  ('manager2', '${PASS_HASH}',  'MANAGER', '23456789012345', NULL),
  ('manager3', '${PASS_HASH}',  'MANAGER', '34567890123456', NULL),
  ('manager4', '${PASS_HASH}',  'MANAGER', '45678901234567', NULL),
  ('cashier1', '${PASS_HASH}',  'CASHIER', '11111111111111', NULL),
  ('cashier2', '${PASS_HASH}',  'CASHIER', '22222222222222', NULL),
  ('cashier3', '${PASS_HASH}',  'CASHIER', '33333333333333', NULL),
  ('cashier4', '${PASS_HASH}',  'CASHIER', '44444444444444', NULL),
  ('client1',  '${PASS_HASH}',  'CLIENT',  NULL,             1),
  ('client2',  '${PASS_HASH}',  'CLIENT',  NULL,             2),
  ('client3',  '${PASS_HASH}',  'CLIENT',  NULL,             3);

-- idx_sale_date (per отчёт)
CREATE INDEX IF NOT EXISTS idx_sale_date ON SALE (sale_date);
SQL_EOF
ok "database/seed.sql"

# ═══════════════════════════════════════════════════════════════
# BACKEND — Dockerfile + CMakeLists + entrypoint
# ═══════════════════════════════════════════════════════════════
hdr "5. Backend: Dockerfile + CMake"

cat > "$PROJ/backend/Dockerfile" << 'DOCKER_EOF'
# Stage 1: Build
FROM drogonframework/drogon:latest AS builder
WORKDIR /build
COPY CMakeLists.txt .
COPY src/ src/
RUN cmake -B cmake-build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build cmake-build --target lumi_backend -j$(nproc)

# Stage 2: Runtime (same image — all libs present)
FROM drogonframework/drogon:latest
WORKDIR /app
COPY --from=builder /build/cmake-build/lumi_backend .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
DOCKER_EOF

cat > "$PROJ/backend/entrypoint.sh" << 'ENTRY_EOF'
#!/bin/sh
# Generate Drogon config from environment variables
cat > /app/config.json << CFG
{
  "listeners": [{ "address": "0.0.0.0", "port": 8080 }],
  "db_clients": [{
    "rdbms":             "postgresql",
    "host":              "${DB_HOST:-db}",
    "port":              ${DB_PORT:-5432},
    "dbname":            "${DB_NAME:-lumidb}",
    "user":              "${DB_USER:-lumi}",
    "passwd":            "${DB_PASS:-lumipass}",
    "connection_number": 10
  }],
  "app": {
    "number_of_threads": 4,
    "run_as_daemon": false,
    "log_level": "DEBUG"
  }
}
CFG
exec /app/lumi_backend
ENTRY_EOF
chmod +x "$PROJ/backend/entrypoint.sh"

cat > "$PROJ/backend/CMakeLists.txt" << 'CMAKE_EOF'
cmake_minimum_required(VERSION 3.15)
project(lumi_backend CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Drogon CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)

set(SOURCES
    src/main.cc
    src/utils/JwtUtils.cc
    src/filters/CorsFilter.cc
    src/controllers/AuthController.cc
    src/controllers/ProductController.cc
    src/controllers/StoreController.cc
    src/controllers/SaleController.cc
    src/controllers/OrderController.cc
    src/controllers/StockController.cc
    src/controllers/ReportController.cc
    src/controllers/ClientController.cc
    src/controllers/SupplierController.cc
    src/controllers/ReviewController.cc
)

add_executable(lumi_backend ${SOURCES})
target_link_libraries(lumi_backend PRIVATE Drogon::Drogon OpenSSL::Crypto)
target_include_directories(lumi_backend PRIVATE src)
CMAKE_EOF
ok "backend/CMakeLists.txt + Dockerfile"

# ─── main.cc ─────────────────────────────────────────────────
cat > "$PROJ/backend/src/main.cc" << 'MAIN_EOF'
#include <drogon/drogon.h>
#include <iostream>

int main() {
    std::cout << "[lumi-net] Starting backend..." << std::endl;
    try {
        drogon::app()
            .loadConfigFile("/app/config.json")
            .run();
    } catch (const std::exception& e) {
        std::cerr << "[lumi-net] Fatal: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
MAIN_EOF
ok "backend/src/main.cc"


# ─── JwtUtils.h ──────────────────────────────────────────────
hdr "6. JWT Utils"
cat > "$PROJ/backend/src/utils/JwtUtils.h" << 'JWT_H_EOF'
#pragma once
#include <string>

namespace JwtUtils {
    // Creates a JWT token with user info payload
    std::string createToken(
        int userId,
        const std::string& role,
        const std::string& refId   // snils or client_id as string
    );

    // Verifies token and extracts payload; returns false if invalid/expired
    bool verifyToken(
        const std::string& token,
        int&         outUserId,
        std::string& outRole,
        std::string& outRefId
    );
}
JWT_H_EOF

# ─── JwtUtils.cc ─────────────────────────────────────────────
cat > "$PROJ/backend/src/utils/JwtUtils.cc" << 'JWT_CC_EOF'
#include "JwtUtils.h"
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <cstring>
#include <cstdlib>
#include <ctime>
#include <sstream>
#include <vector>

static const long TOKEN_TTL = 86400 * 7; // 7 days

// ── Base64URL helpers ──────────────────────────────────────────
static const char B64_CHARS[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string b64url_encode(const unsigned char* buf, size_t len) {
    std::string out;
    out.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        unsigned int v = (unsigned int)buf[i] << 16;
        if (i + 1 < len) v |= (unsigned int)buf[i+1] << 8;
        if (i + 2 < len) v |= (unsigned int)buf[i+2];
        out += B64_CHARS[(v >> 18) & 0x3F];
        out += B64_CHARS[(v >> 12) & 0x3F];
        out += (i + 1 < len) ? B64_CHARS[(v >> 6) & 0x3F] : '=';
        out += (i + 2 < len) ? B64_CHARS[(v)      & 0x3F] : '=';
    }
    for (auto& c : out) {
        if (c == '+') c = '-';
        else if (c == '/') c = '_';
    }
    // Remove padding
    while (!out.empty() && out.back() == '=') out.pop_back();
    return out;
}

static std::string b64url_decode(const std::string& in) {
    std::string s = in;
    for (auto& c : s) {
        if (c == '-') c = '+';
        else if (c == '_') c = '/';
    }
    while (s.size() % 4) s += '=';
    std::vector<unsigned char> out;
    int val = 0, bits = -8;
    for (unsigned char c : s) {
        if (c == '=') break;
        const char* p = strchr(B64_CHARS, c);
        if (!p) return {};
        val = (val << 6) + (int)(p - B64_CHARS);
        bits += 6;
        if (bits >= 0) {
            out.push_back((val >> bits) & 0xFF);
            bits -= 8;
        }
    }
    return std::string(out.begin(), out.end());
}

// ── HMAC-SHA256 ───────────────────────────────────────────────
static std::string hmac_sha256_b64(const std::string& key, const std::string& data) {
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int  len = 0;
    HMAC(EVP_sha256(),
         key.data(), (int)key.size(),
         (const unsigned char*)data.data(), data.size(),
         hash, &len);
    return b64url_encode(hash, len);
}

// ── Simple JSON helpers ───────────────────────────────────────
static std::string jsonStr(const std::string& k, const std::string& v) {
    return "\"" + k + "\":\"" + v + "\"";
}
static std::string jsonNum(const std::string& k, long v) {
    return "\"" + k + "\":" + std::to_string(v);
}

static std::string getJsonField(const std::string& json, const std::string& key) {
    // Find "key":"value"
    std::string pat = "\"" + key + "\":\"";
    auto pos = json.find(pat);
    if (pos == std::string::npos) {
        // Try numeric
        pat = "\"" + key + "\":";
        pos = json.find(pat);
        if (pos == std::string::npos) return {};
        pos += pat.size();
        auto end = json.find_first_of(",}", pos);
        return json.substr(pos, end - pos);
    }
    pos += pat.size();
    auto end = json.find('"', pos);
    return json.substr(pos, end - pos);
}

// ── Public API ────────────────────────────────────────────────
namespace JwtUtils {

std::string createToken(int userId, const std::string& role, const std::string& refId) {
    const char* secret = getenv("JWT_SECRET");
    std::string key = secret ? secret : "lumi_default_secret";

    // Header
    std::string headerJson = R"({"alg":"HS256","typ":"JWT"})";
    std::string header = b64url_encode(
        (const unsigned char*)headerJson.data(), headerJson.size());

    // Payload
    long now = (long)time(nullptr);
    std::string payloadJson = "{" +
        jsonNum("uid", userId) + "," +
        jsonStr("role", role) + "," +
        jsonStr("ref", refId) + "," +
        jsonNum("iat", now) + "," +
        jsonNum("exp", now + TOKEN_TTL) +
    "}";
    std::string payload = b64url_encode(
        (const unsigned char*)payloadJson.data(), payloadJson.size());

    std::string sig = hmac_sha256_b64(key, header + "." + payload);
    return header + "." + payload + "." + sig;
}

bool verifyToken(const std::string& token, int& uid, std::string& role, std::string& ref) {
    const char* secret = getenv("JWT_SECRET");
    std::string key = secret ? secret : "lumi_default_secret";

    auto dot1 = token.find('.');
    auto dot2 = token.rfind('.');
    if (dot1 == std::string::npos || dot2 == dot1) return false;

    std::string header  = token.substr(0, dot1);
    std::string payload = token.substr(dot1 + 1, dot2 - dot1 - 1);
    std::string sig     = token.substr(dot2 + 1);

    // Verify signature
    std::string expected = hmac_sha256_b64(key, header + "." + payload);
    if (expected != sig) return false;

    // Decode payload
    std::string json = b64url_decode(payload);
    if (json.empty()) return false;

    // Check expiry
    std::string expStr = getJsonField(json, "exp");
    if (expStr.empty()) return false;
    long exp = std::stol(expStr);
    if ((long)time(nullptr) > exp) return false;

    // Extract fields
    std::string uidStr = getJsonField(json, "uid");
    if (uidStr.empty()) return false;
    uid  = std::stoi(uidStr);
    role = getJsonField(json, "role");
    ref  = getJsonField(json, "ref");
    return true;
}

} // namespace JwtUtils
JWT_CC_EOF
ok "utils/JwtUtils.h + .cc"


# ─── CORS Filter ─────────────────────────────────────────────
hdr "7. Filters"
cat > "$PROJ/backend/src/filters/CorsFilter.h" << 'CORS_H_EOF'
#pragma once
#include <drogon/HttpFilter.h>

class CorsFilter : public drogon::HttpFilter<CorsFilter> {
public:
    void doFilter(const drogon::HttpRequestPtr& req,
                  drogon::FilterCallback&&      stop,
                  drogon::FilterChainCallback&& next) override;
};
CORS_H_EOF

cat > "$PROJ/backend/src/filters/CorsFilter.cc" << 'CORS_CC_EOF'
#include "CorsFilter.h"

void CorsFilter::doFilter(const drogon::HttpRequestPtr& req,
                           drogon::FilterCallback&&      stop,
                           drogon::FilterChainCallback&& next) {
    if (req->method() == drogon::Options) {
        auto resp = drogon::HttpResponse::newHttpResponse();
        resp->addHeader("Access-Control-Allow-Origin",  "*");
        resp->addHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
        resp->addHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
        resp->setStatusCode(drogon::k204NoContent);
        stop(resp);
        return;
    }
    next();
}
CORS_CC_EOF
ok "filters/CorsFilter"

# ─── Helper macro for CORS headers ───────────────────────────
# (added to every controller response)

# ═══════════════════════════════════════════════════════════════
# AUTH CONTROLLER
# ═══════════════════════════════════════════════════════════════
hdr "8. Controllers"
cat > "$PROJ/backend/src/controllers/AuthController.h" << 'AUTH_H_EOF'
#pragma once
#include <drogon/HttpController.h>

class AuthController : public drogon::HttpController<AuthController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(AuthController::login,    "/api/auth/login",    drogon::Post);
    ADD_METHOD_TO(AuthController::regist,   "/api/auth/register", drogon::Post);
    ADD_METHOD_TO(AuthController::me,       "/api/auth/me",       drogon::Get);
    METHOD_LIST_END

    void login (const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&);
    void regist(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&);
    void me    (const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&);
};
AUTH_H_EOF

cat > "$PROJ/backend/src/controllers/AuthController.cc" << 'AUTH_CC_EOF'
#include "AuthController.h"
#include "utils/JwtUtils.h"
#include <drogon/drogon.h>
#include <openssl/evp.h>
#include <sstream>
#include <iomanip>

using namespace drogon;

// SHA256 hex helper
static std::string sha256hex(const std::string& s) {
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int len = 0;
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr);
    EVP_DigestUpdate(ctx, s.data(), s.size());
    EVP_DigestFinal_ex(ctx, hash, &len);
    EVP_MD_CTX_free(ctx);
    std::ostringstream oss;
    for (unsigned int i = 0; i < len; i++)
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];
    return oss.str();
}

static HttpResponsePtr cors(HttpResponsePtr r) {
    r->addHeader("Access-Control-Allow-Origin","*");
    return r;
}
static HttpResponsePtr jsonErr(const std::string& msg, HttpStatusCode code = k400BadRequest) {
    Json::Value j; j["error"] = msg;
    auto r = HttpResponse::newHttpJsonResponse(j); r->setStatusCode(code);
    return cors(r);
}

void AuthController::login(const HttpRequestPtr& req,
                            std::function<void(const HttpResponsePtr&)>&& cb) {
    auto body = req->getJsonObject();
    if (!body || !(*body)["username"] || !(*body)["password"])
        return cb(jsonErr("username и password обязательны"));

    std::string username = (*body)["username"].asString();
    std::string passHash = sha256hex((*body)["password"].asString());

    auto db = app().getDbClient();
    db->execSqlAsync(
        "SELECT user_id, role, ref_snils, ref_client_id FROM app_users "
        "WHERE username=$1 AND password_hash=$2",
        [cb, username](const orm::Result& r) {
            if (r.empty()) return cb(jsonErr("Неверный логин или пароль", k401Unauthorized));
            int uid = r[0]["user_id"].as<int>();
            std::string role = r[0]["role"].as<std::string>();
            std::string ref;
            if (!r[0]["ref_snils"].isNull())
                ref = r[0]["ref_snils"].as<std::string>();
            else if (!r[0]["ref_client_id"].isNull())
                ref = std::to_string(r[0]["ref_client_id"].as<int>());
            std::string token = JwtUtils::createToken(uid, role, ref);
            Json::Value resp;
            resp["token"] = token;
            resp["role"]  = role;
            resp["ref"]   = ref;
            resp["user_id"] = uid;
            auto hr = HttpResponse::newHttpJsonResponse(resp);
            hr->addHeader("Access-Control-Allow-Origin","*");
            cb(hr);
        },
        [cb](const orm::DrogonDbException& e) {
            cb(jsonErr(e.base().what(), k500InternalServerError));
        },
        username, passHash
    );
}

void AuthController::regist(const HttpRequestPtr& req,
                              std::function<void(const HttpResponsePtr&)>&& cb) {
    auto body = req->getJsonObject();
    if (!body) return cb(jsonErr("Требуется JSON тело"));
    std::string username = (*body).get("username","").asString();
    std::string password = (*body).get("password","").asString();
    std::string fio      = (*body).get("fio","").asString();
    std::string phone    = (*body).get("phone","").asString();
    std::string email    = (*body).get("email","").asString();
    if (username.empty() || password.empty() || fio.empty() || phone.empty())
        return cb(jsonErr("Обязательные поля: username, password, fio, phone"));

    std::string passHash = sha256hex(password);
    auto db = app().getDbClient();

    // Insert client first, then app_user
    db->execSqlAsync(
        "INSERT INTO CLIENT (client_phone,client_email,client_fio) VALUES($1,$2,$3) RETURNING client_id",
        [cb, username, passHash, email](const orm::Result& r) {
            int clientId = r[0]["client_id"].as<int>();
            auto db2 = app().getDbClient();
            db2->execSqlAsync(
                "INSERT INTO app_users (username,password_hash,role,ref_client_id) "
                "VALUES($1,$2,'CLIENT',$3) RETURNING user_id",
                [cb, clientId](const orm::Result& r2) {
                    int uid = r2[0]["user_id"].as<int>();
                    std::string token = JwtUtils::createToken(uid, "CLIENT", std::to_string(clientId));
                    Json::Value resp;
                    resp["token"]     = token;
                    resp["role"]      = "CLIENT";
                    resp["user_id"]   = uid;
                    resp["client_id"] = clientId;
                    auto hr = HttpResponse::newHttpJsonResponse(resp);
                    hr->setStatusCode(k201Created);
                    hr->addHeader("Access-Control-Allow-Origin","*");
                    cb(hr);
                },
                [cb](const orm::DrogonDbException& e) { cb(jsonErr(e.base().what(),k500InternalServerError)); },
                username, passHash, clientId
            );
        },
        [cb](const orm::DrogonDbException& e) { cb(jsonErr(e.base().what(),k500InternalServerError)); },
        phone, email.empty() ? "NULL" : email, fio
    );
}

void AuthController::me(const HttpRequestPtr& req,
                         std::function<void(const HttpResponsePtr&)>&& cb) {
    std::string authHeader = req->getHeader("Authorization");
    if (authHeader.size() < 8) return cb(jsonErr("Нет токена", k401Unauthorized));
    std::string token = authHeader.substr(7); // "Bearer "
    int uid; std::string role, ref;
    if (!JwtUtils::verifyToken(token, uid, role, ref))
        return cb(jsonErr("Недействительный токен", k401Unauthorized));

    Json::Value resp;
    resp["user_id"] = uid;
    resp["role"]    = role;
    resp["ref"]     = ref;
    auto r = HttpResponse::newHttpJsonResponse(resp);
    r->addHeader("Access-Control-Allow-Origin","*");
    cb(r);
}
AUTH_CC_EOF
ok "AuthController"


# ═══════════════════════════════════════════════════════════════
# PRODUCT CONTROLLER
# ═══════════════════════════════════════════════════════════════
cat > "$PROJ/backend/src/controllers/ProductController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class ProductController : public drogon::HttpController<ProductController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ProductController::getAll,    "/api/products",      drogon::Get);
    ADD_METHOD_TO(ProductController::getOne,    "/api/products/{1}",  drogon::Get);
    ADD_METHOD_TO(ProductController::create,    "/api/products",      drogon::Post);
    ADD_METHOD_TO(ProductController::update,    "/api/products/{1}",  drogon::Put);
    ADD_METHOD_TO(ProductController::remove,    "/api/products/{1}",  drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&, int);
    void create(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&);
    void update(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&, int);
    void remove(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&, int);
};
EOF

cat > "$PROJ/backend/src/controllers/ProductController.cc" << 'EOF'
#include "ProductController.h"
#include <drogon/drogon.h>
using namespace drogon;

static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ProductController::getAll(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string cat  = req->getParameter("category");
    std::string srch = req->getParameter("search");
    std::string storeId = req->getParameter("store_id");
    std::string sql;
    std::vector<std::string> params;
    if(!storeId.empty()){
        sql="SELECT p.product_article,p.product_name,p.product_category,p.product_price,"
            "COALESCE(s.stock_quantity,0) AS stock_quantity "
            "FROM PRODUCT p LEFT JOIN STOCK s ON p.product_article=s.product_article AND s.store_id=$1 "
            "WHERE ($2='' OR p.product_category=$2) AND ($3='' OR lower(p.product_name) LIKE lower('%'||$3||'%')) "
            "ORDER BY p.product_category,p.product_name";
        params={storeId, cat, srch};
    } else {
        sql="SELECT product_article,product_name,product_category,product_price FROM PRODUCT "
            "WHERE ($1='' OR product_category=$1) AND ($2='' OR lower(product_name) LIKE lower('%'||$2||'%')) "
            "ORDER BY product_category,product_name";
        params={cat, srch};
    }
    auto db=app().getDbClient();
    auto exec=[cb,sql,params,db](){
        if(params.size()==3)
            db->execSqlAsync(sql,[cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(auto& row:r){Json::Value o;
                    o["article"]=row["product_article"].as<int>();
                    o["name"]=row["product_name"].as<std::string>();
                    o["category"]=row["product_category"].as<std::string>();
                    o["price"]=row["product_price"].as<int>();
                    if(row.columnIndex("stock_quantity")>=0 && !row["stock_quantity"].isNull())
                        o["stock_quantity"]=row["stock_quantity"].as<int>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);
            },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            params[0],params[1],params[2]);
        else
            db->execSqlAsync(sql,[cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(auto& row:r){Json::Value o;
                    o["article"]=row["product_article"].as<int>();
                    o["name"]=row["product_name"].as<std::string>();
                    o["category"]=row["product_category"].as<std::string>();
                    o["price"]=row["product_price"].as<int>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);
            },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            params[0],params[1]);
    };
    exec();
}

void ProductController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    app().getDbClient()->execSqlAsync(
        "SELECT * FROM PRODUCT WHERE product_article=$1",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Товар не найден",k404NotFound));
            Json::Value o;auto& row=r[0];
            o["article"]=row["product_article"].as<int>();
            o["name"]=row["product_name"].as<std::string>();
            o["category"]=row["product_category"].as<std::string>();
            o["price"]=row["product_price"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);
        },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},art);
}

void ProductController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();
    if(!b)return cb(jsonErr("Требуется JSON"));
    int art=(*b)["article"].asInt();
    std::string name=(*b)["name"].asString();
    std::string cat=(*b)["category"].asString();
    int price=(*b)["price"].asInt();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO PRODUCT(product_article,product_name,product_category,product_price) VALUES($1,$2,$3,$4)",
        [cb](const orm::Result&){
            Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->setStatusCode(k201Created);
            r->addHeader("Access-Control-Allow-Origin","*");cb(r);
        },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        art,name,cat,price);
}

void ProductController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("Требуется JSON"));
    std::string name=(*b)["name"].asString();
    std::string cat=(*b)["category"].asString();
    int price=(*b)["price"].asInt();
    app().getDbClient()->execSqlAsync(
        "UPDATE PRODUCT SET product_name=$1,product_category=$2,product_price=$3 WHERE product_article=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        name,cat,price,art);
}

void ProductController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    app().getDbClient()->execSqlAsync(
        "DELETE FROM PRODUCT WHERE product_article=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},art);
}
EOF
ok "ProductController"


# ═══════════════════════════════════════════════════════════════
# STORE, CLIENT, SUPPLIER CONTROLLERS
# ═══════════════════════════════════════════════════════════════
cat > "$PROJ/backend/src/controllers/StoreController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class StoreController : public drogon::HttpController<StoreController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(StoreController::getAll, "/api/stores",     drogon::Get);
    ADD_METHOD_TO(StoreController::getOne, "/api/stores/{1}", drogon::Get);
    ADD_METHOD_TO(StoreController::create, "/api/stores",     drogon::Post);
    ADD_METHOD_TO(StoreController::update, "/api/stores/{1}", drogon::Put);
    ADD_METHOD_TO(StoreController::remove, "/api/stores/{1}", drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void create(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void update(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void remove(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF

cat > "$PROJ/backend/src/controllers/StoreController.cc" << 'EOF'
#include "StoreController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void StoreController::getAll(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone,m.manager_fio "
        "FROM STORE s LEFT JOIN MANAGER m ON s.manager_snils=m.manager_snils ORDER BY s.store_id",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["store_id"].as<int>();
                o["address"]=row["store_address"].as<std::string>();
                o["phone"]=row["store_phone"].as<std::string>();
                o["manager"]=row["manager_fio"].isNull()?"":row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}
void StoreController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone,s.manager_snils,m.manager_fio "
        "FROM STORE s LEFT JOIN MANAGER m ON s.manager_snils=m.manager_snils WHERE s.store_id=$1",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Магазин не найден",k404NotFound));
            auto& row=r[0];Json::Value o;
            o["id"]=row["store_id"].as<int>();
            o["address"]=row["store_address"].as<std::string>();
            o["phone"]=row["store_phone"].as<std::string>();
            o["manager"]=row["manager_fio"].isNull()?"":row["manager_fio"].as<std::string>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
void StoreController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string addr=(*b)["address"].asString(),phone=(*b)["phone"].asString();
    std::string msnils=(*b).get("manager_snils","").asString();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO STORE(store_address,store_phone,manager_snils) VALUES($1,$2,NULLIF($3,'')) RETURNING store_id",
        [cb](const orm::Result& r){Json::Value o;o["id"]=r[0]["store_id"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},addr,phone,msnils);
}
void StoreController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string addr=(*b)["address"].asString(),phone=(*b)["phone"].asString();
    std::string msnils=(*b).get("manager_snils","").asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE STORE SET store_address=$1,store_phone=$2,manager_snils=NULLIF($3,'') WHERE store_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},addr,phone,msnils,id);
}
void StoreController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM STORE WHERE store_id=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
EOF
ok "StoreController"

cat > "$PROJ/backend/src/controllers/ClientController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class ClientController : public drogon::HttpController<ClientController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ClientController::getAll, "/api/clients",     drogon::Get);
    ADD_METHOD_TO(ClientController::getOne, "/api/clients/{1}", drogon::Get);
    ADD_METHOD_TO(ClientController::update, "/api/clients/{1}", drogon::Put);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void update(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF
cat > "$PROJ/backend/src/controllers/ClientController.cc" << 'EOF'
#include "ClientController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ClientController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string srch=req->getParameter("search");
    app().getDbClient()->execSqlAsync(
        "SELECT client_id,client_fio,client_phone,client_email FROM CLIENT "
        "WHERE $1='' OR lower(client_fio) LIKE lower('%'||$1||'%') OR client_phone LIKE '%'||$1||'%' "
        "ORDER BY client_fio",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["client_id"].as<int>();
                o["fio"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["phone"]=row["client_phone"].as<std::string>();
                o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},srch);
}
void ClientController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT c.*,COUNT(s.sale_id) AS purchase_count,COALESCE(SUM(s.sale_total),0) AS total_spent "
        "FROM CLIENT c LEFT JOIN SALE s ON c.client_id=s.client_id WHERE c.client_id=$1 GROUP BY c.client_id",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Клиент не найден",k404NotFound));
            auto& row=r[0];Json::Value o;
            o["id"]=row["client_id"].as<int>();
            o["fio"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
            o["phone"]=row["client_phone"].as<std::string>();
            o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
            o["purchase_count"]=row["purchase_count"].as<int>();
            o["total_spent"]=row["total_spent"].as<double>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
void ClientController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string fio=(*b)["fio"].asString(),phone=(*b)["phone"].asString(),email=(*b).get("email","").asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE CLIENT SET client_fio=$1,client_phone=$2,client_email=NULLIF($3,'') WHERE client_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},fio,phone,email,id);
}
EOF
ok "ClientController"

cat > "$PROJ/backend/src/controllers/SupplierController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class SupplierController : public drogon::HttpController<SupplierController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(SupplierController::getAll, "/api/suppliers",     drogon::Get);
    ADD_METHOD_TO(SupplierController::create, "/api/suppliers",     drogon::Post);
    ADD_METHOD_TO(SupplierController::update, "/api/suppliers/{1}", drogon::Put);
    ADD_METHOD_TO(SupplierController::remove, "/api/suppliers/{1}", drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void create(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void update(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void remove(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF
cat > "$PROJ/backend/src/controllers/SupplierController.cc" << 'EOF'
#include "SupplierController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}
void SupplierController::getAll(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        "SELECT s.*,COUNT(o.order_id) AS order_count FROM SUPPLIER s LEFT JOIN \"ORDER\" o ON s.supplier_id=o.supplier_id GROUP BY s.supplier_id ORDER BY s.supplier_name",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["supplier_id"].as<int>();
                o["name"]=row["supplier_name"].as<std::string>();
                o["email"]=row["supplier_email"].as<std::string>();
                o["phone"]=row["supplier_phone"].as<std::string>();
                o["order_count"]=row["order_count"].as<int>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}
void SupplierController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string name=(*b)["name"].asString(),email=(*b)["email"].asString(),phone=(*b)["phone"].asString();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO SUPPLIER(supplier_name,supplier_email,supplier_phone) VALUES($1,$2,$3) RETURNING supplier_id",
        [cb](const orm::Result& r){Json::Value o;o["id"]=r[0]["supplier_id"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},name,email,phone);
}
void SupplierController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string name=(*b)["name"].asString(),email=(*b)["email"].asString(),phone=(*b)["phone"].asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE SUPPLIER SET supplier_name=$1,supplier_email=$2,supplier_phone=$3 WHERE supplier_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},name,email,phone,id);
}
void SupplierController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM SUPPLIER WHERE supplier_id=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
EOF
ok "SupplierController"


# ═══════════════════════════════════════════════════════════════
# SALE, STOCK, REVIEW, ORDER CONTROLLERS
# ═══════════════════════════════════════════════════════════════
cat > "$PROJ/backend/src/controllers/SaleController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class SaleController : public drogon::HttpController<SaleController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(SaleController::getAll,      "/api/sales",              drogon::Get);
    ADD_METHOD_TO(SaleController::getOne,      "/api/sales/{1}",          drogon::Get);
    ADD_METHOD_TO(SaleController::create,      "/api/sales",              drogon::Post);
    ADD_METHOD_TO(SaleController::clientSales, "/api/clients/{1}/sales",  drogon::Get);
    METHOD_LIST_END
    void getAll     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void create     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void clientSales(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF

cat > "$PROJ/backend/src/controllers/SaleController.cc" << 'EOF'
#include "SaleController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void SaleController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id");
    std::string from=req->getParameter("from");
    std::string to=req->getParameter("to");
    app().getDbClient()->execSqlAsync(
        "SELECT s.sale_id,s.sale_date,s.sale_total,s.sale_payment_method,"
        "c.client_fio,c.client_phone,st.store_address,ca.cashier_fio "
        "FROM SALE s "
        "JOIN CLIENT c ON s.client_id=c.client_id "
        "JOIN STORE st ON s.store_id=st.store_id "
        "JOIN CASHIER ca ON s.cashier_snils=ca.cashier_snils "
        "WHERE ($1='' OR s.store_id=$1::int) "
        "AND ($2='' OR s.sale_date>=$2::date) "
        "AND ($3='' OR s.sale_date<=$3::date) "
        "ORDER BY s.sale_date DESC LIMIT 200",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["sale_id"].as<int>();
                o["date"]=row["sale_date"].as<std::string>();
                o["total"]=row["sale_total"].as<double>();
                o["payment"]=row["sale_payment_method"].as<std::string>();
                o["client"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["client_phone"]=row["client_phone"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["cashier"]=row["cashier_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,from,to);
}

void SaleController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT s.*,c.client_fio,c.client_phone,st.store_address,ca.cashier_fio "
        "FROM SALE s JOIN CLIENT c ON s.client_id=c.client_id "
        "JOIN STORE st ON s.store_id=st.store_id "
        "JOIN CASHIER ca ON s.cashier_snils=ca.cashier_snils WHERE s.sale_id=$1",
        [cb,id](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Продажа не найдена",k404NotFound));
            auto& row=r[0];Json::Value o;
            o["id"]=row["sale_id"].as<int>();
            o["date"]=row["sale_date"].as<std::string>();
            o["total"]=row["sale_total"].as<double>();
            o["payment"]=row["sale_payment_method"].as<std::string>();
            o["client"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
            o["store"]=row["store_address"].as<std::string>();
            o["cashier"]=row["cashier_fio"].as<std::string>();
            // Load items
            app().getDbClient()->execSqlAsync(
                "SELECT si.sale_item_quantity,p.product_name,p.product_article,p.product_price "
                "FROM SALE_ITEM si JOIN PRODUCT p ON si.product_article=p.product_article WHERE si.sale_id=$1",
                [cb,o](const orm::Result& ri) mutable {
                    Json::Value items(Json::arrayValue);
                    for(auto& row2:ri){Json::Value itm;
                        itm["name"]=row2["product_name"].as<std::string>();
                        itm["article"]=row2["product_article"].as<int>();
                        itm["price"]=row2["product_price"].as<int>();
                        itm["qty"]=row2["sale_item_quantity"].as<int>();
                        items.append(itm);}
                    o["items"]=items;
                    auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
                [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void SaleController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int clientId=(*b)["client_id"].asInt();
    std::string cashierSnils=(*b)["cashier_snils"].asString();
    int storeId=(*b)["store_id"].asInt();
    std::string payment=(*b)["payment_method"].asString();
    Json::Value items=(*b)["items"];
    if(!items.isArray()||items.empty())return cb(jsonErr("items обязателен и не должен быть пустым"));
    double total=0;
    for(auto& itm:items) total+=itm["price"].asDouble()*itm["qty"].asInt();

    auto db=app().getDbClient();
    db->execSqlAsync(
        "INSERT INTO SALE(client_id,cashier_snils,store_id,sale_total,sale_payment_method,sale_date) "
        "VALUES($1,$2,$3,$4,$5,CURRENT_DATE) RETURNING sale_id",
        [cb,items,db](const orm::Result& r){
            int saleId=r[0]["sale_id"].as<int>();
            int itemIdx=1;
            for(auto& itm:items){
                int art=itm["article"].asInt();int qty=itm["qty"].asInt();
                db->execSqlAsync(
                    "INSERT INTO SALE_ITEM(sale_id,sale_item_id,product_article,sale_item_quantity) VALUES($1,$2,$3,$4)",
                    [](const orm::Result&){},[](const orm::DrogonDbException&){},saleId,itemIdx++,art,qty);}
            Json::Value o;o["id"]=saleId;o["ok"]=true;
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        clientId,cashierSnils,storeId,total,payment);
}

void SaleController::clientSales(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int clientId){
    std::string from=req->getParameter("from");
    std::string to=req->getParameter("to");
    app().getDbClient()->execSqlAsync(
        "SELECT s.sale_id,s.sale_date,s.sale_total,s.sale_payment_method,st.store_address,"
        "array_agg(p.product_name) AS products "
        "FROM SALE s JOIN STORE st ON s.store_id=st.store_id "
        "JOIN SALE_ITEM si ON s.sale_id=si.sale_id "
        "JOIN PRODUCT p ON si.product_article=p.product_article "
        "WHERE s.client_id=$1 AND ($2='' OR s.sale_date>=$2::date) AND ($3='' OR s.sale_date<=$3::date) "
        "GROUP BY s.sale_id,st.store_address ORDER BY s.sale_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["sale_id"].as<int>();
                o["date"]=row["sale_date"].as<std::string>();
                o["total"]=row["sale_total"].as<double>();
                o["payment"]=row["sale_payment_method"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["products"]=row["products"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        clientId,from,to);
}
EOF
ok "SaleController"


cat > "$PROJ/backend/src/controllers/StockController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class StockController : public drogon::HttpController<StockController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(StockController::getByStore, "/api/stores/{1}/stock",  drogon::Get);
    ADD_METHOD_TO(StockController::updateQty,  "/api/stock/{1}",         drogon::Put);
    METHOD_LIST_END
    void getByStore(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void updateQty (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF
cat > "$PROJ/backend/src/controllers/StockController.cc" << 'EOF'
#include "StockController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}
void StockController::getByStore(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int storeId){
    std::string thresh=req->getParameter("threshold");
    app().getDbClient()->execSqlAsync(
        "SELECT st.stock_id,st.stock_quantity,p.product_article,p.product_name,p.product_category,p.product_price "
        "FROM STOCK st JOIN PRODUCT p ON st.product_article=p.product_article "
        "WHERE st.store_id=$1 AND ($2='' OR st.stock_quantity<=$2::int) "
        "ORDER BY st.stock_quantity ASC, p.product_name",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["stock_id"]=row["stock_id"].as<int>();
                o["qty"]=row["stock_quantity"].as<int>();
                o["article"]=row["product_article"].as<int>();
                o["name"]=row["product_name"].as<std::string>();
                o["category"]=row["product_category"].as<std::string>();
                o["price"]=row["product_price"].as<int>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,thresh);
}
void StockController::updateQty(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int stockId){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int qty=(*b)["qty"].asInt();int storeId=(*b)["store_id"].asInt();
    app().getDbClient()->execSqlAsync(
        "UPDATE STOCK SET stock_quantity=$1 WHERE stock_id=$2 AND store_id=$3",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},qty,stockId,storeId);
}
EOF
ok "StockController"

cat > "$PROJ/backend/src/controllers/ReviewController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class ReviewController : public drogon::HttpController<ReviewController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ReviewController::getAll, "/api/reviews",     drogon::Get);
    ADD_METHOD_TO(ReviewController::create, "/api/reviews",     drogon::Post);
    ADD_METHOD_TO(ReviewController::remove, "/api/reviews/{1}", drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void create(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void remove(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF
cat > "$PROJ/backend/src/controllers/ReviewController.cc" << 'EOF'
#include "ReviewController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}
void ReviewController::getAll(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        "SELECT r.review_id,r.review_rating,r.review_comment,r.review_date,c.client_fio "
        "FROM REVIEW r JOIN CLIENT c ON r.client_id=c.client_id ORDER BY r.review_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["review_id"].as<int>();
                o["rating"]=row["review_rating"].as<int>();
                o["comment"]=row["review_comment"].isNull()?"":row["review_comment"].as<std::string>();
                o["date"]=row["review_date"].isNull()?"":row["review_date"].as<std::string>();
                o["client"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}
void ReviewController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int clientId=(*b)["client_id"].asInt();
    int rating=(*b)["rating"].asInt();
    std::string comment=(*b).get("comment","").asString();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO REVIEW(client_id,review_rating,review_comment,review_date) VALUES($1,$2,$3,CURRENT_DATE) RETURNING review_id",
        [cb](const orm::Result& r){Json::Value o;o["id"]=r[0]["review_id"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},clientId,rating,comment);
}
void ReviewController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM REVIEW WHERE review_id=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
EOF
ok "ReviewController"


cat > "$PROJ/backend/src/controllers/OrderController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class OrderController : public drogon::HttpController<OrderController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(OrderController::getAll,      "/api/orders",              drogon::Get);
    ADD_METHOD_TO(OrderController::getOne,      "/api/orders/{1}",          drogon::Get);
    ADD_METHOD_TO(OrderController::create,      "/api/orders",              drogon::Post);
    ADD_METHOD_TO(OrderController::updateStatus,"/api/orders/{1}/status",   drogon::Put);
    METHOD_LIST_END
    void getAll      (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne      (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void create      (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void updateStatus(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF
cat > "$PROJ/backend/src/controllers/OrderController.cc" << 'EOF'
#include "OrderController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void OrderController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id");
    std::string status=req->getParameter("status");
    std::string suppId=req->getParameter("supplier_id");
    app().getDbClient()->execSqlAsync(
        "SELECT o.order_id,o.order_date,o.order_status,o.order_total,"
        "s.store_address,sp.supplier_name,m.manager_fio "
        "FROM \"ORDER\" o "
        "JOIN STORE s ON o.store_id=s.store_id "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils "
        "WHERE ($1='' OR o.store_id=$1::int) "
        "AND ($2='' OR o.order_status=$2) "
        "AND ($3='' OR o.supplier_id=$3::int) "
        "ORDER BY o.order_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["order_id"].as<int>();
                o["date"]=row["order_date"].as<std::string>();
                o["status"]=row["order_status"].as<std::string>();
                o["total"]=row["order_total"].as<long long>();
                o["store"]=row["store_address"].as<std::string>();
                o["supplier"]=row["supplier_name"].as<std::string>();
                o["manager"]=row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,status,suppId);
}

void OrderController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT o.*,s.store_address,sp.supplier_name,m.manager_fio "
        "FROM \"ORDER\" o JOIN STORE s ON o.store_id=s.store_id "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils WHERE o.order_id=$1",
        [cb,id](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Заказ не найден",k404NotFound));
            auto& row=r[0];Json::Value o;
            o["id"]=row["order_id"].as<int>();
            o["date"]=row["order_date"].as<std::string>();
            o["status"]=row["order_status"].as<std::string>();
            o["total"]=row["order_total"].as<long long>();
            o["store"]=row["store_address"].as<std::string>();
            o["supplier"]=row["supplier_name"].as<std::string>();
            o["manager"]=row["manager_fio"].as<std::string>();
            app().getDbClient()->execSqlAsync(
                "SELECT oi.order_item_quantity,p.product_name,p.product_article,p.product_price "
                "FROM ORDER_ITEM oi JOIN PRODUCT p ON oi.product_article=p.product_article WHERE oi.order_id=$1",
                [cb,o](const orm::Result& ri) mutable {
                    Json::Value items(Json::arrayValue);
                    for(auto& row2:ri){Json::Value itm;
                        itm["name"]=row2["product_name"].as<std::string>();
                        itm["article"]=row2["product_article"].as<int>();
                        itm["price"]=row2["product_price"].as<int>();
                        itm["qty"]=row2["order_item_quantity"].as<int>();
                        items.append(itm);}
                    o["items"]=items;
                    auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
                [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void OrderController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int storeId=(*b)["store_id"].asInt();
    int suppId=(*b)["supplier_id"].asInt();
    Json::Value items=(*b)["items"];
    if(!items.isArray()||items.empty())return cb(jsonErr("items required"));

    // Build arrays for stored procedure
    std::string arts="ARRAY[",qtys="ARRAY[";
    for(unsigned i=0;i<items.size();i++){
        if(i)arts+=",",qtys+=",";
        arts+=std::to_string(items[i]["article"].asInt());
        qtys+=std::to_string(items[i]["qty"].asInt());}
    arts+="]::INT[]";qtys+="]::INT[]";

    std::string sql="CALL create_supplier_order("+std::to_string(storeId)+","+
                    std::to_string(suppId)+","+arts+","+qtys+",NULL)";
    app().getDbClient()->execSqlAsync(sql,
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->setStatusCode(k201Created);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}

void OrderController::updateStatus(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string status=(*b)["status"].asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE \"ORDER\" SET order_status=$1 WHERE order_id=$2",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},status,id);
}
EOF
ok "OrderController"


# ═══════════════════════════════════════════════════════════════
# REPORT CONTROLLER — 4 отчёта из ТЗ
# ═══════════════════════════════════════════════════════════════
cat > "$PROJ/backend/src/controllers/ReportController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class ReportController : public drogon::HttpController<ReportController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ReportController::salesByCategory, "/api/reports/sales-by-category", drogon::Get);
    ADD_METHOD_TO(ReportController::stockStatus,     "/api/reports/stock-status",      drogon::Get);
    ADD_METHOD_TO(ReportController::ordersBySupplier,"/api/reports/orders",            drogon::Get);
    ADD_METHOD_TO(ReportController::revenueByStore,  "/api/reports/revenue-by-store",  drogon::Get);
    ADD_METHOD_TO(ReportController::topCustomers,    "/api/reports/top-customers",     drogon::Get);
    METHOD_LIST_END
    void salesByCategory (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void stockStatus     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void ordersBySupplier(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void revenueByStore  (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void topCustomers    (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
};
EOF

cat > "$PROJ/backend/src/controllers/ReportController.cc" << 'EOF'
#include "ReportController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

// ── Отчёт 1: Продажи по категориям (запрос №5 из отчёта — WITH CTE)
void ReportController::salesByCategory(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from=req->getParameter("from"); if(from.empty())from="2024-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    std::string cat =req->getParameter("category");
    std::string storeId=req->getParameter("store_id");
    app().getDbClient()->execSqlAsync(
        "WITH cat_sales AS ("
        "  SELECT p.product_category,"
        "         SUM(si.sale_item_quantity) AS total_qty,"
        "         SUM(p.product_price * si.sale_item_quantity) AS cat_revenue "
        "  FROM SALE s "
        "  JOIN SALE_ITEM si ON s.sale_id=si.sale_id "
        "  JOIN PRODUCT p ON si.product_article=p.product_article "
        "  WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "  AND ($3='' OR p.product_category=$3) "
        "  AND ($4='' OR s.store_id=$4::int) "
        "  GROUP BY p.product_category"
        "), total AS (SELECT SUM(cat_revenue) AS grand FROM cat_sales) "
        "SELECT cs.product_category, cs.total_qty, cs.cat_revenue,"
        "       ROUND((cs.cat_revenue::numeric/NULLIF(t.grand,0))*100,2) AS pct "
        "FROM cat_sales cs CROSS JOIN total t ORDER BY cs.cat_revenue DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["category"]=row["product_category"].as<std::string>();
                o["qty"]=row["total_qty"].as<long long>();
                o["revenue"]=row["cat_revenue"].as<double>();
                o["pct"]=row["pct"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,cat,storeId);
}

// ── Отчёт 2: Остатки товаров в магазине
void ReportController::stockStatus(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id"); if(storeId.empty())return cb(jsonErr("store_id required"));
    std::string thresh=req->getParameter("threshold"); if(thresh.empty())thresh="9999";
    app().getDbClient()->execSqlAsync(
        "SELECT p.product_article,p.product_name,p.product_category,p.product_price,st.stock_quantity "
        "FROM STOCK st JOIN PRODUCT p ON st.product_article=p.product_article "
        "WHERE st.store_id=$1::int AND st.stock_quantity<=$2::int "
        "ORDER BY st.stock_quantity ASC,p.product_name",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["article"]=row["product_article"].as<int>();
                o["name"]=row["product_name"].as<std::string>();
                o["category"]=row["product_category"].as<std::string>();
                o["price"]=row["product_price"].as<int>();
                o["qty"]=row["stock_quantity"].as<int>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,thresh);
}

// ── Отчёт 3: Заказы поставщикам
void ReportController::ordersBySupplier(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string suppId=req->getParameter("supplier_id");
    std::string status=req->getParameter("status");
    std::string from=req->getParameter("from"); if(from.empty())from="2000-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    app().getDbClient()->execSqlAsync(
        "SELECT o.order_id,o.order_date,o.order_status,o.order_total,"
        "sp.supplier_name,s.store_address,m.manager_fio "
        "FROM \"ORDER\" o "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN STORE s ON o.store_id=s.store_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils "
        "WHERE ($1='' OR o.supplier_id=$1::int) "
        "AND ($2='' OR o.order_status=$2) "
        "AND o.order_date BETWEEN $3::date AND $4::date "
        "ORDER BY o.order_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["order_id"].as<int>();
                o["date"]=row["order_date"].as<std::string>();
                o["status"]=row["order_status"].as<std::string>();
                o["total"]=row["order_total"].as<long long>();
                o["supplier"]=row["supplier_name"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["manager"]=row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        suppId,status,from,to);
}

// ── Отчёт 4: Выручка по магазинам (запрос №3 из отчёта)
void ReportController::revenueByStore(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from=req->getParameter("from"); if(from.empty())from="2024-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    std::string payment=req->getParameter("payment");
    app().getDbClient()->execSqlAsync(
        "SELECT st.store_id,st.store_address,"
        "SUM(s.sale_total) AS total_revenue,"
        "COUNT(*) AS tx_count,"
        "ROUND(AVG(s.sale_total)::numeric,2) AS avg_check "
        "FROM SALE s JOIN STORE st ON s.store_id=st.store_id "
        "WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "AND ($3='' OR s.sale_payment_method=$3) "
        "GROUP BY st.store_id,st.store_address ORDER BY total_revenue DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["store_id"]=row["store_id"].as<int>();
                o["store"]=row["store_address"].as<std::string>();
                o["revenue"]=row["total_revenue"].as<double>();
                o["tx_count"]=row["tx_count"].as<long long>();
                o["avg_check"]=row["avg_check"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,payment);
}

// ── Отчёт 5: Топ клиентов (представление №2 из отчёта)
void ReportController::topCustomers(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from=req->getParameter("from"); if(from.empty())from="2024-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    std::string lim =req->getParameter("limit"); if(lim.empty())lim="10";
    app().getDbClient()->execSqlAsync(
        "SELECT c.client_fio,c.client_phone,"
        "COUNT(s.sale_id) AS purchase_count,"
        "SUM(s.sale_total) AS total_amount,"
        "ROUND(AVG(s.sale_total)::numeric,2) AS avg_check "
        "FROM CLIENT c JOIN SALE s ON c.client_id=s.client_id "
        "WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "GROUP BY c.client_id,c.client_fio,c.client_phone "
        "ORDER BY total_amount DESC LIMIT $3::int",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["fio"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["phone"]=row["client_phone"].as<std::string>();
                o["count"]=row["purchase_count"].as<long long>();
                o["total"]=row["total_amount"].as<double>();
                o["avg"]=row["avg_check"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,lim);
}
EOF
ok "ReportController (5 отчётов)"


# ═══════════════════════════════════════════════════════════════
# FRONTEND — index.html (SPA, ~1800 lines)
# ═══════════════════════════════════════════════════════════════
hdr "11. Frontend SPA"
cat > "$PROJ/frontend/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>LUMI·NET — Ювелирная сеть</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,600;1,300;1,400&family=DM+Sans:wght@300;400;500&display=swap" rel="stylesheet">
<style>
:root{
  --gold:#c9a84c;--gold-light:#e8d5a3;--gold-dark:#8a6f2e;
  --obsidian:#0d0d0d;--ink:#1a1a1a;--charcoal:#2c2c2c;--ash:#4a4a4a;
  --smoke:#7a7a7a;--silver:#b0b0b0;--pearl:#e8e4dc;--cream:#f5f0e8;--white:#fafafa;
  --success:#4a7c59;--danger:#8b2e2e;--warning:#8a6f2e;--info:#2e5f8a;
  --radius:2px;--radius-lg:4px;--shadow:0 2px 16px rgba(0,0,0,.15);
  --transition:.18s ease;
}
*{margin:0;padding:0;box-sizing:border-box}
html,body{height:100%;font-family:'DM Sans',sans-serif;background:var(--cream);color:var(--ink);font-size:14px;line-height:1.5}
/* ── LAYOUT ── */
#app{display:flex;height:100vh;overflow:hidden}
#sidebar{width:230px;background:var(--obsidian);display:flex;flex-direction:column;flex-shrink:0;transition:width .2s}
#sidebar.collapsed{width:56px}
.sidebar-logo{padding:20px 16px 16px;border-bottom:1px solid #222;flex-shrink:0}
.logo-full{display:flex;align-items:baseline;gap:6px}
.logo-full span:first-child{font-family:'Cormorant Garamond',serif;font-size:22px;font-weight:300;color:var(--gold);letter-spacing:.1em}
.logo-full span:last-child{font-size:10px;color:var(--smoke);letter-spacing:.15em;text-transform:uppercase}
.sidebar-collapsed #sidebar .logo-full{display:none}
nav{flex:1;overflow-y:auto;padding:8px 0}
.nav-section{padding:8px 14px 4px;font-size:9px;text-transform:uppercase;letter-spacing:.12em;color:var(--ash);font-weight:500}
#sidebar.collapsed .nav-section{display:none}
.nav-item{display:flex;align-items:center;gap:10px;padding:9px 14px;color:var(--silver);cursor:pointer;transition:all var(--transition);border-left:2px solid transparent;text-decoration:none;font-size:13px;white-space:nowrap;overflow:hidden}
.nav-item:hover{background:rgba(255,255,255,.05);color:var(--gold-light)}
.nav-item.active{color:var(--gold);border-left-color:var(--gold);background:rgba(201,168,76,.08)}
.nav-icon{font-size:16px;flex-shrink:0;width:18px;text-align:center}
#sidebar.collapsed .nav-item span:last-child{display:none}
.sidebar-footer{padding:12px;border-top:1px solid #222}
.user-card{display:flex;align-items:center;gap:8px;padding:8px;background:#1a1a1a;border-radius:var(--radius)}
.user-avatar{width:30px;height:30px;border-radius:50%;background:var(--gold-dark);display:flex;align-items:center;justify-content:center;font-size:12px;color:var(--cream);font-weight:600;flex-shrink:0}
.user-info{overflow:hidden}
.user-name{font-size:12px;color:var(--pearl);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.user-role{font-size:10px;color:var(--smoke)}
#sidebar.collapsed .user-info{display:none}
/* ── MAIN ── */
#main{flex:1;display:flex;flex-direction:column;overflow:hidden}
#topbar{height:52px;background:var(--white);border-bottom:1px solid #e0d8cc;display:flex;align-items:center;padding:0 20px;gap:12px;flex-shrink:0;box-shadow:0 1px 4px rgba(0,0,0,.06)}
#toggle-sidebar{background:none;border:none;cursor:pointer;font-size:18px;color:var(--ash);padding:6px;border-radius:var(--radius)}
#topbar-title{font-family:'Cormorant Garamond',serif;font-size:18px;font-weight:400;color:var(--ink);flex:1}
.topbar-actions{display:flex;gap:8px;align-items:center}
#page{flex:1;overflow-y:auto;padding:24px}
/* ── AUTH ── */
#auth-screen{position:fixed;inset:0;background:var(--obsidian);display:flex;align-items:center;justify-content:center;z-index:1000}
.auth-box{background:var(--ink);border:1px solid #333;border-radius:var(--radius-lg);padding:40px;width:360px}
.auth-title{font-family:'Cormorant Garamond',serif;font-size:28px;color:var(--gold);text-align:center;margin-bottom:6px}
.auth-sub{text-align:center;color:var(--smoke);font-size:12px;margin-bottom:28px;letter-spacing:.05em}
/* ── COMPONENTS ── */
.card{background:var(--white);border:1px solid #e0d8cc;border-radius:var(--radius-lg);padding:20px;margin-bottom:16px}
.card-title{font-family:'Cormorant Garamond',serif;font-size:18px;font-weight:400;color:var(--ink);margin-bottom:14px;display:flex;align-items:center;gap:8px}
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-bottom:20px}
.stat-card{background:var(--white);border:1px solid #e0d8cc;border-radius:var(--radius-lg);padding:16px 18px;position:relative;overflow:hidden}
.stat-card::before{content:'';position:absolute;top:0;left:0;width:3px;height:100%;background:var(--gold)}
.stat-value{font-family:'Cormorant Garamond',serif;font-size:28px;font-weight:300;color:var(--ink);line-height:1}
.stat-label{font-size:11px;color:var(--smoke);text-transform:uppercase;letter-spacing:.08em;margin-top:4px}
.stat-icon{position:absolute;right:14px;top:50%;transform:translateY(-50%);font-size:26px;opacity:.15}
/* ── TABLE ── */
.tbl-wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:13px}
thead{background:var(--cream)}
th{padding:9px 12px;text-align:left;font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.07em;color:var(--ash);border-bottom:2px solid #e0d8cc;white-space:nowrap}
td{padding:10px 12px;border-bottom:1px solid #f0ebe0;color:var(--charcoal);vertical-align:middle}
tr:hover td{background:rgba(201,168,76,.04)}
tr:last-child td{border-bottom:none}
.td-actions{display:flex;gap:6px;align-items:center}
/* ── FORMS ── */
.form-group{margin-bottom:14px}
label{display:block;font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--ash);margin-bottom:5px;font-weight:500}
input,select,textarea{width:100%;padding:9px 12px;border:1px solid #d0c8ba;border-radius:var(--radius);background:var(--white);font-family:'DM Sans',sans-serif;font-size:13px;color:var(--ink);transition:border var(--transition);outline:none}
input:focus,select:focus,textarea:focus{border-color:var(--gold)}
textarea{resize:vertical;min-height:80px}
.form-row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
/* ── BUTTONS ── */
.btn{display:inline-flex;align-items:center;gap:6px;padding:8px 16px;border-radius:var(--radius);font-family:'DM Sans',sans-serif;font-size:13px;font-weight:500;cursor:pointer;border:none;transition:all var(--transition);text-decoration:none;white-space:nowrap}
.btn-primary{background:var(--gold);color:var(--obsidian)}
.btn-primary:hover{background:var(--gold-dark);color:var(--cream)}
.btn-outline{background:transparent;border:1px solid var(--gold);color:var(--gold)}
.btn-outline:hover{background:var(--gold);color:var(--obsidian)}
.btn-ghost{background:transparent;border:1px solid #d0c8ba;color:var(--ash)}
.btn-ghost:hover{border-color:var(--ash);color:var(--ink)}
.btn-danger{background:transparent;border:1px solid var(--danger);color:var(--danger)}
.btn-danger:hover{background:var(--danger);color:var(--white)}
.btn-sm{padding:5px 10px;font-size:12px}
.btn-xs{padding:3px 8px;font-size:11px}
/* ── BADGES ── */
.badge{display:inline-block;padding:2px 8px;border-radius:20px;font-size:11px;font-weight:500}
.badge-success{background:#e8f4ec;color:var(--success)}
.badge-warning{background:#faf3e0;color:var(--warning)}
.badge-danger{background:#fae8e8;color:var(--danger)}
.badge-info{background:#e8f0fa;color:var(--info)}
.badge-gold{background:rgba(201,168,76,.15);color:var(--gold-dark)}
/* ── MODAL ── */
.modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:500;display:flex;align-items:center;justify-content:center;opacity:0;pointer-events:none;transition:opacity .2s}
.modal-overlay.open{opacity:1;pointer-events:all}
.modal{background:var(--white);border-radius:var(--radius-lg);padding:28px;width:520px;max-width:95vw;max-height:90vh;overflow-y:auto;transform:translateY(12px);transition:transform .2s;box-shadow:var(--shadow)}
.modal-overlay.open .modal{transform:translateY(0)}
.modal-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px}
.modal-title{font-family:'Cormorant Garamond',serif;font-size:20px;font-weight:400}
.modal-close{background:none;border:none;font-size:20px;cursor:pointer;color:var(--smoke);padding:4px;line-height:1}
.modal-footer{display:flex;gap:10px;justify-content:flex-end;margin-top:20px;padding-top:16px;border-top:1px solid #e0d8cc}
/* ── STARS ── */
.stars{color:var(--gold);font-size:14px;letter-spacing:1px}
/* ── FILTERS BAR ── */
.filters{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:16px;align-items:flex-end}
.filter-group{display:flex;flex-direction:column;gap:4px}
.filter-group label{font-size:10px;text-transform:uppercase;letter-spacing:.07em;color:var(--smoke)}
.filter-group input,.filter-group select{width:auto;min-width:140px;padding:7px 10px}
/* ── ALERTS ── */
.alert{padding:10px 14px;border-radius:var(--radius);font-size:13px;margin-bottom:12px}
.alert-err{background:#fae8e8;color:var(--danger);border-left:3px solid var(--danger)}
.alert-ok {background:#e8f4ec;color:var(--success);border-left:3px solid var(--success)}
/* ── PAGINATION ── */
.pagination{display:flex;gap:4px;align-items:center;margin-top:12px;justify-content:flex-end}
.page-btn{padding:5px 10px;border:1px solid #d0c8ba;background:var(--white);border-radius:var(--radius);cursor:pointer;font-size:12px;color:var(--ash)}
.page-btn.active{background:var(--gold);border-color:var(--gold);color:var(--obsidian);font-weight:600}
.page-btn:hover:not(.active){border-color:var(--gold);color:var(--gold)}
/* ── CHART ── */
.chart-bar-wrap{display:flex;flex-direction:column;gap:6px;margin-top:12px}
.chart-bar-row{display:flex;align-items:center;gap:10px;font-size:12px}
.chart-bar-label{width:120px;text-align:right;color:var(--ash);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.chart-bar-track{flex:1;background:#f0ebe0;border-radius:2px;height:18px;overflow:hidden}
.chart-bar-fill{height:100%;background:linear-gradient(90deg,var(--gold-dark),var(--gold));border-radius:2px;transition:width .5s ease;display:flex;align-items:center;padding-left:6px;font-size:11px;color:var(--obsidian);font-weight:500}
.chart-bar-val{width:90px;color:var(--ink);font-weight:500;font-size:12px}
/* ── MISC ── */
.empty-state{text-align:center;padding:40px 20px;color:var(--smoke)}
.empty-state .esi{font-size:36px;margin-bottom:10px}
.empty-state p{font-size:14px}
.section-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px}
.section-title{font-family:'Cormorant Garamond',serif;font-size:22px;font-weight:400}
.separator{border:none;border-top:1px solid #e0d8cc;margin:20px 0}
.tag{display:inline-block;padding:2px 8px;background:var(--cream);border:1px solid #d0c8ba;border-radius:var(--radius);font-size:11px;color:var(--ash)}
.items-list{display:flex;flex-direction:column;gap:6px}
.item-row{display:flex;justify-content:space-between;align-items:center;padding:8px 10px;background:var(--cream);border-radius:var(--radius);font-size:13px}
.item-row-del{cursor:pointer;color:var(--smoke);padding:2px 6px;font-size:16px;line-height:1}
.item-row-del:hover{color:var(--danger)}
/* ── RESPONSIVE ── */
@media(max-width:700px){
  #sidebar{width:56px}
  #sidebar .nav-item span:last-child{display:none}
  #sidebar .nav-section,.sidebar-footer .user-info,.logo-full span:last-child{display:none}
  #page{padding:14px}
}
</style>
</head>
<body>
<!-- AUTH SCREEN -->
<div id="auth-screen">
  <div class="auth-box">
    <div class="auth-title">LUMI·NET</div>
    <div class="auth-sub">Управление ювелирной сетью</div>
    <div id="auth-err"></div>
    <div id="auth-login-form">
      <div class="form-group"><label>Логин</label><input id="au-user" type="text" placeholder="username" autocomplete="username"></div>
      <div class="form-group"><label>Пароль</label><input id="au-pass" type="password" placeholder="••••••" autocomplete="current-password"></div>
      <button class="btn btn-primary" style="width:100%;justify-content:center;margin-top:4px" onclick="doLogin()">Войти</button>
      <div style="margin-top:14px;text-align:center;font-size:12px;color:#555">
        Нет аккаунта? <a href="#" onclick="showRegForm()" style="color:var(--gold)">Зарегистрироваться</a>
      </div>
    </div>
    <div id="auth-reg-form" style="display:none">
      <div class="form-row">
        <div class="form-group"><label>ФИО</label><input id="ru-fio" type="text" placeholder="Фамилия Имя Отчество"></div>
        <div class="form-group"><label>Телефон</label><input id="ru-phone" type="text" placeholder="+7 (XXX) XXX-XX-XX"></div>
      </div>
      <div class="form-row">
        <div class="form-group"><label>Логин</label><input id="ru-user" type="text" placeholder="username"></div>
        <div class="form-group"><label>Пароль</label><input id="ru-pass" type="password" placeholder="••••••"></div>
      </div>
      <div class="form-group"><label>Email (необязательно)</label><input id="ru-email" type="email" placeholder="email@example.com"></div>
      <button class="btn btn-primary" style="width:100%;justify-content:center" onclick="doRegister()">Зарегистрироваться</button>
      <div style="margin-top:12px;text-align:center;font-size:12px;color:#555">
        <a href="#" onclick="showLoginForm()" style="color:var(--gold)">← Войти в систему</a>
      </div>
    </div>
    <div style="margin-top:20px;padding:10px;background:#111;border-radius:2px;font-size:11px;color:#555;line-height:1.6">
      <b style="color:#777">Тестовые аккаунты:</b><br>
      admin / admin123 &nbsp;|&nbsp; manager1 / pass123<br>
      cashier1 / pass123 &nbsp;|&nbsp; client1 / pass123
    </div>
  </div>
</div>

<!-- MAIN APP -->
<div id="app" style="display:none">
  <!-- SIDEBAR -->
  <aside id="sidebar">
    <div class="sidebar-logo">
      <div class="logo-full">
        <span>LUMI·NET</span>
        <span>Ювелирная сеть</span>
      </div>
    </div>
    <nav id="nav"></nav>
    <div class="sidebar-footer">
      <div class="user-card">
        <div class="user-avatar" id="ua-initials">?</div>
        <div class="user-info">
          <div class="user-name" id="ua-name">—</div>
          <div class="user-role" id="ua-role">—</div>
        </div>
      </div>
    </div>
  </aside>

  <!-- MAIN CONTENT -->
  <div id="main">
    <div id="topbar">
      <button id="toggle-sidebar" onclick="toggleSidebar()">☰</button>
      <div id="topbar-title">Добро пожаловать</div>
      <div class="topbar-actions">
        <button class="btn btn-ghost btn-sm" onclick="logout()">Выйти</button>
      </div>
    </div>
    <div id="page"><div class="empty-state"><div class="esi">💎</div><p>Выберите раздел в меню</p></div></div>
  </div>
</div>

<!-- MODAL -->
<div class="modal-overlay" id="modal-overlay" onclick="closeModalIfBg(event)">
  <div class="modal" id="modal-box">
    <div class="modal-header">
      <div class="modal-title" id="modal-title">Окно</div>
      <button class="modal-close" onclick="closeModal()">✕</button>
    </div>
    <div id="modal-body"></div>
    <div class="modal-footer" id="modal-footer"></div>
  </div>
</div>

<script src="js/app.js"></script>
</body>
</html>
HTML_EOF
ok "frontend/index.html"


# ═══════════════════════════════════════════════════════════════
# app.js — полный SPA (auth, routing, все страницы)
# ═══════════════════════════════════════════════════════════════
cat > "$PROJ/frontend/js/app.js" << 'JS_EOF'
'use strict';
// ── State ─────────────────────────────────────────────────────
let TOKEN=null,ROLE=null,REF=null,USER_ID=null;
const API='/api';
const PAGE_SIZE=20;

// ── API helper ────────────────────────────────────────────────
async function api(path,opts={}){
  const headers={'Content-Type':'application/json',...(TOKEN?{Authorization:'Bearer '+TOKEN}:{})};
  const r=await fetch(API+path,{headers,...opts});
  if(r.status===204)return{};
  const txt=await r.text();
  let data;try{data=JSON.parse(txt);}catch{data={raw:txt};}
  if(!r.ok)throw new Error(data.error||'Ошибка '+r.status);
  return data;
}
const get=(p,q={})=>api(p+(Object.keys(q).length?'?'+new URLSearchParams(q):''));
const post=(p,b)=>api(p,{method:'POST',body:JSON.stringify(b)});
const put=(p,b)=>api(p,{method:'PUT',body:JSON.stringify(b)});
const del=p=>api(p,{method:'DELETE'});

// ── Auth ──────────────────────────────────────────────────────
async function doLogin(){
  const u=document.getElementById('au-user').value.trim();
  const p=document.getElementById('au-pass').value;
  if(!u||!p)return showAuthErr('Заполните все поля');
  try{
    const d=await post('/auth/login',{username:u,password:p});
    TOKEN=d.token;ROLE=d.role;REF=d.ref;USER_ID=d.user_id;
    localStorage.setItem('lumi_token',TOKEN);
    localStorage.setItem('lumi_role',ROLE);
    localStorage.setItem('lumi_ref',REF||'');
    localStorage.setItem('lumi_uid',USER_ID);
    bootApp();
  }catch(e){showAuthErr(e.message);}
}
async function doRegister(){
  const fio=document.getElementById('ru-fio').value.trim();
  const phone=document.getElementById('ru-phone').value.trim();
  const uname=document.getElementById('ru-user').value.trim();
  const pass=document.getElementById('ru-pass').value;
  const email=document.getElementById('ru-email').value.trim();
  if(!fio||!phone||!uname||!pass)return showAuthErr('Заполните обязательные поля');
  try{
    const d=await post('/auth/register',{fio,phone,username:uname,password:pass,email});
    TOKEN=d.token;ROLE=d.role;REF=String(d.client_id);USER_ID=d.user_id;
    localStorage.setItem('lumi_token',TOKEN);
    localStorage.setItem('lumi_role',ROLE);
    localStorage.setItem('lumi_ref',REF);
    localStorage.setItem('lumi_uid',USER_ID);
    bootApp();
  }catch(e){showAuthErr(e.message);}
}
function showAuthErr(m){const el=document.getElementById('auth-err');el.innerHTML=`<div class="alert alert-err">${esc(m)}</div>`;}
function showRegForm(){document.getElementById('auth-login-form').style.display='none';document.getElementById('auth-reg-form').style.display='';}
function showLoginForm(){document.getElementById('auth-reg-form').style.display='none';document.getElementById('auth-login-form').style.display='';}
function logout(){TOKEN=ROLE=REF=USER_ID=null;localStorage.clear();location.reload();}

// ── Boot ──────────────────────────────────────────────────────
function bootApp(){
  document.getElementById('auth-screen').style.display='none';
  document.getElementById('app').style.display='flex';
  // Set user info
  const roleLabels={ADMIN:'Администратор',MANAGER:'Менеджер',CASHIER:'Кассир',CLIENT:'Клиент'};
  document.getElementById('ua-role').textContent=roleLabels[ROLE]||ROLE;
  document.getElementById('ua-name').textContent=
    ROLE==='CLIENT'?'Клиент #'+REF: ROLE==='CASHIER'?'Кассир':
    ROLE==='MANAGER'?'Менеджер':'Администратор';
  document.getElementById('ua-initials').textContent=(roleLabels[ROLE]||'?')[0];
  buildNav();
  navigate('dashboard');
}
function tryAutoLogin(){
  TOKEN=localStorage.getItem('lumi_token');
  ROLE=localStorage.getItem('lumi_role');
  REF=localStorage.getItem('lumi_ref');
  USER_ID=+localStorage.getItem('lumi_uid');
  if(TOKEN&&ROLE) bootApp();
}

// ── Navigation ────────────────────────────────────────────────
const PAGES={
  ADMIN:  [{id:'dashboard',icon:'◆',label:'Дашборд'},
            {sec:'Продажи'},
            {id:'sales',icon:'🛒',label:'Продажи'},
            {id:'clients',icon:'👤',label:'Клиенты'},
            {sec:'Каталог'},
            {id:'products',icon:'💎',label:'Товары'},
            {id:'stock',icon:'📦',label:'Остатки'},
            {sec:'Снабжение'},
            {id:'orders',icon:'📋',label:'Заказы'},
            {id:'suppliers',icon:'🏭',label:'Поставщики'},
            {sec:'Управление'},
            {id:'stores',icon:'🏪',label:'Магазины'},
            {id:'reviews',icon:'⭐',label:'Отзывы'},
            {sec:'Аналитика'},
            {id:'reports',icon:'📊',label:'Отчёты'}],
  MANAGER:[{id:'dashboard',icon:'◆',label:'Дашборд'},
            {sec:'Продажи'},
            {id:'sales',icon:'🛒',label:'Продажи'},
            {sec:'Каталог'},
            {id:'products',icon:'💎',label:'Товары'},
            {id:'stock',icon:'📦',label:'Остатки'},
            {sec:'Снабжение'},
            {id:'orders',icon:'📋',label:'Заказы'},
            {sec:'Аналитика'},
            {id:'reports',icon:'📊',label:'Отчёты'}],
  CASHIER:[{id:'dashboard',icon:'◆',label:'Дашборд'},
            {id:'sale_new',icon:'🛒',label:'Оформить продажу'},
            {id:'sales',icon:'📑',label:'История продаж'},
            {id:'products',icon:'💎',label:'Каталог товаров'},
            {id:'stock',icon:'📦',label:'Остатки'}],
  CLIENT: [{id:'dashboard',icon:'◆',label:'Главная'},
            {id:'catalog',icon:'💎',label:'Каталог'},
            {id:'my_purchases',icon:'🛍️',label:'Мои покупки'},
            {id:'reviews',icon:'⭐',label:'Отзывы'}],
};
function buildNav(){
  const items=PAGES[ROLE]||[];
  let html='';
  items.forEach(it=>{
    if(it.sec){html+=`<div class="nav-section">${it.sec}</div>`;return;}
    html+=`<a class="nav-item" data-page="${it.id}" onclick="navigate('${it.id}')" href="#">
      <span class="nav-icon">${it.icon}</span><span>${it.label}</span></a>`;
  });
  document.getElementById('nav').innerHTML=html;
}
function navigate(page){
  document.querySelectorAll('.nav-item').forEach(el=>{
    el.classList.toggle('active',el.dataset.page===page);});
  const titles={dashboard:'Дашборд',sales:'Продажи',clients:'Клиенты',products:'Товары',
    stock:'Остатки на складе',orders:'Заказы поставщикам',suppliers:'Поставщики',
    stores:'Магазины',reviews:'Отзывы',reports:'Отчёты',sale_new:'Оформить продажу',
    catalog:'Каталог товаров',my_purchases:'Мои покупки'};
  document.getElementById('topbar-title').textContent=titles[page]||page;
  const fn={dashboard:pgDashboard,sales:pgSales,clients:pgClients,products:pgProducts,
    stock:pgStock,orders:pgOrders,suppliers:pgSuppliers,stores:pgStores,
    reviews:pgReviews,reports:pgReports,sale_new:pgSaleNew,
    catalog:pgCatalog,my_purchases:pgMyPurchases}[page];
  if(fn) fn(); else setPage('<div class="empty-state"><div class="esi">🔧</div><p>Страница в разработке</p></div>');
}
function setPage(html){document.getElementById('page').innerHTML=html;}
function toggleSidebar(){document.getElementById('sidebar').classList.toggle('collapsed');}

// ── Helpers ───────────────────────────────────────────────────
const esc=s=>String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const fmt=n=>new Intl.NumberFormat('ru-RU').format(n||0);
const fmtMoney=n=>(n||0).toLocaleString('ru-RU',{style:'currency',currency:'RUB',maximumFractionDigits:0});
const fmtDate=s=>s?new Date(s).toLocaleDateString('ru-RU'):'—';
function statusBadge(s){
  const m={Доставлен:'success',Принят:'success','В пути':'info','В обработке':'warning',
    Ожидается:'warning',ожидается:'warning',Отменен:'danger',Отменён:'danger'};
  return`<span class="badge badge-${m[s]||'gold'}">${esc(s)}</span>`;
}
function stars(n){return'★'.repeat(n)+'☆'.repeat(5-n);}
function paginate(arr,page,size){
  const total=Math.ceil(arr.length/size);
  return{items:arr.slice((page-1)*size,page*size),total,page};
}
function paginationHtml(p,total,cb){
  if(total<=1)return'';
  let h='<div class="pagination">';
  if(p>1) h+=`<button class="page-btn" onclick="${cb}(${p-1})">‹</button>`;
  for(let i=1;i<=total;i++) h+=`<button class="page-btn${i===p?' active':''}" onclick="${cb}(${i})">${i}</button>`;
  if(p<total) h+=`<button class="page-btn" onclick="${cb}(${p+1})">›</button>`;
  return h+'</div>';
}

// ── Modal ─────────────────────────────────────────────────────
function openModal(title,body,footer=''){
  document.getElementById('modal-title').textContent=title;
  document.getElementById('modal-body').innerHTML=body;
  document.getElementById('modal-footer').innerHTML=footer;
  document.getElementById('modal-overlay').classList.add('open');
}
function closeModal(){document.getElementById('modal-overlay').classList.remove('open');}
function closeModalIfBg(e){if(e.target===document.getElementById('modal-overlay'))closeModal();}
function showAlert(msg,type='ok',containerId='page-alert'){
  const el=document.getElementById(containerId);
  if(el){el.innerHTML=`<div class="alert alert-${type}">${esc(msg)}</div>`;
    setTimeout(()=>{el.innerHTML='';},4000);}
}
JS_EOF
ok "frontend/js/app.js (part 1)"


cat >> "$PROJ/frontend/js/app.js" << 'JS2_EOF'

// ═══════════════════════════════════════════════════════════════
// PAGE: DASHBOARD
// ═══════════════════════════════════════════════════════════════
async function pgDashboard(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const [sales,products,stores,orders]=await Promise.all([
      get('/sales'),get('/products'),get('/stores'),get('/orders')]);
    const totalRev=sales.reduce((s,x)=>s+(x.total||0),0);
    const activeOrders=orders.filter(o=>['ожидается','В пути','В обработке'].includes(o.status)).length;
    setPage(`
    <div id="page-alert"></div>
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-value">${fmt(sales.length)}</div><div class="stat-label">Всего продаж</div><div class="stat-icon">🛒</div></div>
      <div class="stat-card"><div class="stat-value">${fmtMoney(totalRev)}</div><div class="stat-label">Общая выручка</div><div class="stat-icon">💰</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(products.length)}</div><div class="stat-label">Товаров в каталоге</div><div class="stat-icon">💎</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(stores.length)}</div><div class="stat-label">Магазинов</div><div class="stat-icon">🏪</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(activeOrders)}</div><div class="stat-label">Активных заказов</div><div class="stat-icon">📋</div></div>
    </div>
    <div class="card">
      <div class="card-title">💡 Последние продажи</div>
      <div class="tbl-wrap"><table>
        <thead><tr><th>Дата</th><th>Клиент</th><th>Магазин</th><th>Сумма</th><th>Оплата</th></tr></thead>
        <tbody>${sales.slice(0,8).map(s=>`<tr>
          <td>${fmtDate(s.date)}</td><td>${esc(s.client)}</td>
          <td><span class="tag">${esc(s.store.split(',')[1]||s.store)}</span></td>
          <td><b>${fmtMoney(s.total)}</b></td>
          <td>${esc(s.payment)}</td></tr>`).join('')}
        </tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: SALES
// ═══════════════════════════════════════════════════════════════
let salesData=[],salesPage=1;
async function pgSales(fromVal='',toVal='',storeId=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const [data,stores]=await Promise.all([
      get('/sales',{from:fromVal,to:toVal,store_id:storeId}),
      get('/stores')]);
    salesData=data;salesPage=1;
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${storeId==s.id?'selected':''}>${esc(s.address)}</option>`).join('');
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="f-from" value="${fromVal}"></div>
        <div class="filter-group"><label>По</label><input type="date" id="f-to" value="${toVal}"></div>
        <div class="filter-group"><label>Магазин</label>
          <select id="f-store"><option value="">Все магазины</option>${storeOpts}</select></div>
        <button class="btn btn-primary btn-sm" onclick="pgSales(document.getElementById('f-from').value,document.getElementById('f-to').value,document.getElementById('f-store').value)">Применить</button>
        ${ROLE!=='CLIENT'?'<button class="btn btn-outline btn-sm" onclick="modalNewSale()">+ Новая продажа</button>':''}
      </div>
    </div>
    <div class="card">
      <div id="sales-table"></div>
    </div>`);
    renderSalesTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderSalesTable(){
  const {items,total,page}=paginate(salesData,salesPage,PAGE_SIZE);
  document.getElementById('sales-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Дата</th><th>Клиент</th><th>Магазин</th><th>Кассир</th><th>Сумма</th><th>Оплата</th><th></th></tr></thead>
      <tbody>${items.map(s=>`<tr>
        <td>${s.id}</td><td>${fmtDate(s.date)}</td>
        <td>${esc(s.client||'—')}</td>
        <td><small>${esc(s.store)}</small></td>
        <td><small>${esc(s.cashier)}</small></td>
        <td><b>${fmtMoney(s.total)}</b></td>
        <td>${esc(s.payment)}</td>
        <td><button class="btn btn-ghost btn-xs" onclick="viewSale(${s.id})">Детали</button></td>
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setSalesPage')}`;
}
function setSalesPage(p){salesPage=p;renderSalesTable();}
async function viewSale(id){
  try{
    const s=await get('/sales/'+id);
    openModal('Продажа #'+id,`
      <div class="form-row" style="margin-bottom:12px">
        <div><label>Клиент</label><p>${esc(s.client)}</p></div>
        <div><label>Дата</label><p>${fmtDate(s.date)}</p></div>
        <div><label>Магазин</label><p>${esc(s.store)}</p></div>
        <div><label>Кассир</label><p>${esc(s.cashier)}</p></div>
        <div><label>Оплата</label><p>${esc(s.payment)}</p></div>
        <div><label>Итого</label><p><b>${fmtMoney(s.total)}</b></p></div>
      </div>
      <hr class="separator">
      <div class="card-title" style="font-size:15px">Позиции</div>
      <div class="items-list">${(s.items||[]).map(i=>`
        <div class="item-row"><span>${esc(i.name)}</span>
        <span>${i.qty} шт × ${fmtMoney(i.price)}</span></div>`).join('')}
      </div>`,'<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}
JS2_EOF
ok "app.js pages: dashboard, sales"


cat >> "$PROJ/frontend/js/app.js" << 'JS3_EOF'

// ═══════════════════════════════════════════════════════════════
// PAGE: SALE NEW (Кассир — оформление продажи)
// ═══════════════════════════════════════════════════════════════
let saleCartItems=[];
async function pgSaleNew(){
  try{
    const [clients,stores,products]=await Promise.all([
      get('/clients'),get('/stores'),get('/products')]);
    const clientOpts=clients.map(c=>`<option value="${c.id}">${esc(c.fio||c.phone)} (${esc(c.phone)})</option>`).join('');
    const storeOpts=stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('');
    const prodOpts=products.map(p=>`<option value="${p.article}" data-price="${p.price}">${esc(p.name)} — ${fmtMoney(p.price)}</option>`).join('');
    saleCartItems=[];
    setPage(`
    <div id="page-alert"></div>
    <div style="display:grid;grid-template-columns:1fr 380px;gap:16px">
      <div>
        <div class="card">
          <div class="card-title">👤 Клиент и магазин</div>
          <div class="form-row">
            <div class="form-group"><label>Клиент</label><select id="sn-client">${clientOpts}</select></div>
            <div class="form-group"><label>Магазин</label><select id="sn-store">${storeOpts}</select></div>
          </div>
          <div class="form-group"><label>Способ оплаты</label>
            <select id="sn-pay">
              <option>Карта</option><option>Наличные</option><option>Безнал</option>
            </select>
          </div>
        </div>
        <div class="card">
          <div class="card-title">💎 Добавить товар</div>
          <div class="form-row">
            <div class="form-group"><label>Товар</label><select id="sn-prod">${prodOpts}</select></div>
            <div class="form-group"><label>Количество</label><input type="number" id="sn-qty" value="1" min="1"></div>
          </div>
          <button class="btn btn-outline btn-sm" onclick="saleAddItem()">+ Добавить в корзину</button>
        </div>
      </div>
      <div class="card" style="position:sticky;top:0;align-self:start">
        <div class="card-title">🛒 Корзина</div>
        <div id="sn-cart"><div class="empty-state" style="padding:20px"><p>Корзина пуста</p></div></div>
        <hr class="separator">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
          <b>Итого:</b><b id="sn-total" style="font-size:18px;color:var(--gold-dark)">0 ₽</b>
        </div>
        <button class="btn btn-primary" style="width:100%;justify-content:center" onclick="submitSale()">Оформить продажу</button>
      </div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function saleAddItem(){
  const sel=document.getElementById('sn-prod');
  const opt=sel.options[sel.selectedIndex];
  const article=+sel.value,price=+(opt.dataset.price||0),name=opt.text.split('—')[0].trim();
  const qty=+document.getElementById('sn-qty').value||1;
  const existing=saleCartItems.find(i=>i.article===article);
  if(existing) existing.qty+=qty;
  else saleCartItems.push({article,name,price,qty});
  renderSaleCart();
}
function saleRemoveItem(article){
  saleCartItems=saleCartItems.filter(i=>i.article!==article);
  renderSaleCart();
}
function renderSaleCart(){
  const total=saleCartItems.reduce((s,i)=>s+i.price*i.qty,0);
  document.getElementById('sn-total').textContent=fmtMoney(total);
  if(!saleCartItems.length){
    document.getElementById('sn-cart').innerHTML='<div class="empty-state" style="padding:20px"><p>Корзина пуста</p></div>';return;}
  document.getElementById('sn-cart').innerHTML=`<div class="items-list">${
    saleCartItems.map(i=>`<div class="item-row">
      <span>${esc(i.name)}</span>
      <span>${i.qty} × ${fmtMoney(i.price)}</span>
      <span class="item-row-del" onclick="saleRemoveItem(${i.article})">✕</span>
    </div>`).join('')}</div>`;
}
async function submitSale(){
  if(!saleCartItems.length)return alert('Добавьте товары в корзину');
  const clientId=+document.getElementById('sn-client').value;
  const storeId=+document.getElementById('sn-store').value;
  const payment=document.getElementById('sn-pay').value;
  // cashier_snils from REF
  try{
    await post('/sales',{client_id:clientId,cashier_snils:REF,store_id:storeId,
      payment_method:payment,items:saleCartItems.map(i=>({article:i.article,price:i.price,qty:i.qty}))});
    saleCartItems=[];
    showAlert('Продажа успешно оформлена!','ok','page-alert');
    pgSaleNew();
  }catch(e){showAlert(e.message,'err','page-alert');}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: PRODUCTS
// ═══════════════════════════════════════════════════════════════
let prodsData=[],prodsPage=1;
async function pgProducts(cat='',srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/products',{category:cat,search:srch});
    prodsData=data;prodsPage=1;
    const cats=[...new Set(data.map(p=>p.category))].sort();
    const catOpts=cats.map(c=>`<option value="${c}" ${cat===c?'selected':''}>${c}</option>`).join('');
    const canEdit=ROLE==='ADMIN'||ROLE==='MANAGER';
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Категория</label>
          <select id="p-cat"><option value="">Все категории</option>${catOpts}</select></div>
        <div class="filter-group"><label>Поиск</label>
          <input type="text" id="p-srch" value="${esc(srch)}" placeholder="Название товара..."></div>
        <button class="btn btn-primary btn-sm" onclick="pgProducts(document.getElementById('p-cat').value,document.getElementById('p-srch').value)">Найти</button>
        ${canEdit?'<button class="btn btn-outline btn-sm" onclick="modalProduct()">+ Добавить товар</button>':''}
      </div>
    </div>
    <div class="card"><div id="prods-table"></div></div>`);
    renderProdsTable(canEdit);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderProdsTable(canEdit){
  const {items,total,page}=paginate(prodsData,prodsPage,PAGE_SIZE);
  document.getElementById('prods-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th>${canEdit?'<th></th>':''}</tr></thead>
      <tbody>${items.map(p=>`<tr>
        <td><code>${p.article}</code></td>
        <td>${esc(p.name)}</td>
        <td><span class="badge badge-gold">${esc(p.category)}</span></td>
        <td><b>${fmtMoney(p.price)}</b></td>
        ${canEdit?`<td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick='modalProduct(${JSON.stringify(p)})'>Изм.</button>
          <button class="btn btn-danger btn-xs" onclick="deleteProduct(${p.article})">Удал.</button>
        </td>`:''}
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setProdsPage')}`;
}
function setProdsPage(p){prodsPage=p;renderProdsTable(ROLE==='ADMIN'||ROLE==='MANAGER');}
function modalProduct(p=null){
  openModal(p?'Редактировать товар':'Новый товар',`
    <div class="form-group"><label>Артикул</label><input id="mp-art" type="number" value="${p?p.article:''}" ${p?'readonly':''}></div>
    <div class="form-group"><label>Название</label><input id="mp-name" value="${esc(p?p.name:'')}"></div>
    <div class="form-group"><label>Категория</label>
      <select id="mp-cat">
        ${['Кольца','Серьги','Браслеты','Подвески','Цепочки','Часы','Броши'].map(c=>`<option ${(p&&p.category===c)?'selected':''}>${c}</option>`).join('')}
      </select></div>
    <div class="form-group"><label>Цена (руб.)</label><input id="mp-price" type="number" value="${p?p.price:''}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveProduct(${p?p.article:0})">Сохранить</button>`);
}
async function saveProduct(art){
  const data={article:+document.getElementById('mp-art').value,
    name:document.getElementById('mp-name').value,
    category:document.getElementById('mp-cat').value,
    price:+document.getElementById('mp-price').value};
  try{
    if(art) await put('/products/'+art,data);
    else await post('/products',data);
    closeModal();pgProducts();
  }catch(e){alert(e.message);}
}
async function deleteProduct(art){
  if(!confirm('Удалить товар '+art+'?'))return;
  try{await del('/products/'+art);pgProducts();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: STOCK
// ═══════════════════════════════════════════════════════════════
async function pgStock(storeId='',thresh=''){
  try{
    const stores=await get('/stores');
    if(!storeId&&stores.length) storeId=stores[0].id;
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${storeId==s.id?'selected':''}>${esc(s.address)}</option>`).join('');
    const data=storeId?await get('/stores/'+storeId+'/stock',{threshold:thresh}):[];
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Магазин</label><select id="st-store">${storeOpts}</select></div>
        <div class="filter-group"><label>Остаток ≤</label><input type="number" id="st-thresh" value="${thresh}" placeholder="Порог (напр. 3)"></div>
        <button class="btn btn-primary btn-sm" onclick="pgStock(document.getElementById('st-store').value,document.getElementById('st-thresh').value)">Применить</button>
      </div>
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th><th>Остаток</th><th>Статус</th>${ROLE!=='CLIENT'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(r=>{
          const low=r.qty<=2,mid=r.qty<=5;
          const badge=r.qty===0?'badge-danger':low?'badge-warning':'badge-success';
          const label=r.qty===0?'Нет в наличии':low?'Критично':mid?'Мало':'В наличии';
          return`<tr>
            <td><code>${r.article}</code></td>
            <td>${esc(r.name)}</td>
            <td><span class="badge badge-gold">${esc(r.category)}</span></td>
            <td>${fmtMoney(r.price)}</td>
            <td><b>${r.qty}</b></td>
            <td><span class="badge ${badge}">${label}</span></td>
            ${ROLE!=='CLIENT'?`<td><button class="btn btn-ghost btn-xs" onclick="modalEditStock(${r.stock_id},${r.qty},${storeId})">Изм.</button></td>`:''}
          </tr>`;}).join('')}
        </tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalEditStock(stockId,qty,storeId){
  openModal('Изменить остаток',`
    <div class="form-group"><label>Новое количество</label>
    <input id="es-qty" type="number" value="${qty}" min="0"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveStock(${stockId},${storeId})">Сохранить</button>`);
}
async function saveStock(stockId,storeId){
  const qty=+document.getElementById('es-qty').value;
  try{await put('/stock/'+stockId,{qty,store_id:storeId});closeModal();pgStock(storeId);}
  catch(e){alert(e.message);}
}
JS3_EOF
ok "app.js: SaleNew, Products, Stock"


cat >> "$PROJ/frontend/js/app.js" << 'JS4_EOF'

// ═══════════════════════════════════════════════════════════════
// PAGE: ORDERS
// ═══════════════════════════════════════════════════════════════
let ordersData=[],ordersPage=1;
async function pgOrders(storeId='',status='',suppId=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const [data,stores,suppliers]=await Promise.all([
      get('/orders',{store_id:storeId,status,supplier_id:suppId}),
      get('/stores'),get('/suppliers')]);
    ordersData=data;ordersPage=1;
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${storeId==s.id?'selected':''}>${esc(s.address)}</option>`).join('');
    const suppOpts=suppliers.map(s=>`<option value="${s.id}" ${suppId==s.id?'selected':''}>${esc(s.name)}</option>`).join('');
    const statuses=['ожидается','В обработке','В пути','Доставлен','Отменен'];
    const statOpts=statuses.map(s=>`<option value="${s}" ${status===s?'selected':''}>${s}</option>`).join('');
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Магазин</label>
          <select id="or-store"><option value="">Все</option>${storeOpts}</select></div>
        <div class="filter-group"><label>Статус</label>
          <select id="or-stat"><option value="">Все статусы</option>${statOpts}</select></div>
        <div class="filter-group"><label>Поставщик</label>
          <select id="or-supp"><option value="">Все</option>${suppOpts}</select></div>
        <button class="btn btn-primary btn-sm" onclick="pgOrders(document.getElementById('or-store').value,document.getElementById('or-stat').value,document.getElementById('or-supp').value)">Применить</button>
        ${ROLE!=='CLIENT'?`<button class="btn btn-outline btn-sm" onclick="modalNewOrder(${JSON.stringify(stores).replace(/"/g,'&quot;')},${JSON.stringify(suppliers).replace(/"/g,'&quot;')},${JSON.stringify(data.map(()=>({}))).replace(/"/g,'&quot;')})">+ Новый заказ</button>`:''}
      </div>
    </div>
    <div class="card"><div id="orders-table"></div></div>`);
    renderOrdersTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderOrdersTable(){
  const {items,total,page}=paginate(ordersData,ordersPage,PAGE_SIZE);
  document.getElementById('orders-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Дата</th><th>Магазин</th><th>Поставщик</th><th>Менеджер</th><th>Статус</th><th>Сумма</th><th></th></tr></thead>
      <tbody>${items.map(o=>`<tr>
        <td>${o.id}</td><td>${fmtDate(o.date)}</td>
        <td><small>${esc(o.store)}</small></td>
        <td><small>${esc(o.supplier)}</small></td>
        <td><small>${esc(o.manager)}</small></td>
        <td>${statusBadge(o.status)}</td>
        <td><b>${fmtMoney(o.total)}</b></td>
        <td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick="viewOrder(${o.id})">Детали</button>
          ${ROLE!=='CLIENT'?`<button class="btn btn-outline btn-xs" onclick="modalChangeOrderStatus(${o.id},'${o.status}')">Статус</button>`:''}
        </td>
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setOrdersPage')}`;
}
function setOrdersPage(p){ordersPage=p;renderOrdersTable();}
async function viewOrder(id){
  try{
    const o=await get('/orders/'+id);
    openModal('Заказ #'+id,`
      <div class="form-row" style="margin-bottom:12px">
        <div><label>Магазин</label><p>${esc(o.store)}</p></div>
        <div><label>Поставщик</label><p>${esc(o.supplier)}</p></div>
        <div><label>Менеджер</label><p>${esc(o.manager)}</p></div>
        <div><label>Дата</label><p>${fmtDate(o.date)}</p></div>
        <div><label>Статус</label><p>${statusBadge(o.status)}</p></div>
        <div><label>Итого</label><p><b>${fmtMoney(o.total)}</b></p></div>
      </div><hr class="separator">
      <div class="card-title" style="font-size:15px">Позиции</div>
      <div class="items-list">${(o.items||[]).map(i=>`
        <div class="item-row"><span>${esc(i.name)}</span>
        <span>${i.qty} шт × ${fmtMoney(i.price)}</span></div>`).join('')}
      </div>`,'<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}
function modalChangeOrderStatus(id,current){
  const statuses=['ожидается','В обработке','В пути','Доставлен','Отменен'];
  openModal('Изменить статус заказа #'+id,`
    <div class="form-group"><label>Новый статус</label>
      <select id="os-stat">${statuses.map(s=>`<option value="${s}" ${s===current?'selected':''}>${s}</option>`).join('')}</select>
    </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveOrderStatus(${id})">Сохранить</button>`);
}
async function saveOrderStatus(id){
  const status=document.getElementById('os-stat').value;
  try{await put('/orders/'+id+'/status',{status});closeModal();pgOrders();}catch(e){alert(e.message);}
}

// Modal: New Order with product list builder
let orderCartItems=[];
async function modalNewOrder_open(){
  const [stores,suppliers,products]=await Promise.all([get('/stores'),get('/suppliers'),get('/products')]);
  orderCartItems=[];
  const storeOpts=stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('');
  const suppOpts=suppliers.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('');
  const prodOpts=products.map(p=>`<option value="${p.article}" data-price="${p.price}">${esc(p.name)}</option>`).join('');
  openModal('Новый заказ поставщику',`
    <div class="form-row">
      <div class="form-group"><label>Магазин</label><select id="no-store">${storeOpts}</select></div>
      <div class="form-group"><label>Поставщик</label><select id="no-supp">${suppOpts}</select></div>
    </div>
    <hr class="separator">
    <div class="form-row">
      <div class="form-group"><label>Товар</label><select id="no-prod">${prodOpts}</select></div>
      <div class="form-group"><label>Кол-во</label><input type="number" id="no-qty" value="1" min="1"></div>
    </div>
    <button class="btn btn-outline btn-sm" onclick="orderAddItem()">+ Добавить</button>
    <div id="no-cart" style="margin-top:12px"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="submitNewOrder()">Создать заказ</button>`);
}
function orderAddItem(){
  const sel=document.getElementById('no-prod');
  const opt=sel.options[sel.selectedIndex];
  const article=+sel.value,name=opt.text,price=+(opt.dataset.price||0);
  const qty=+document.getElementById('no-qty').value||1;
  const ex=orderCartItems.find(i=>i.article===article);
  if(ex) ex.qty+=qty; else orderCartItems.push({article,name,price,qty});
  renderOrderCart();
}
function renderOrderCart(){
  if(!orderCartItems.length){document.getElementById('no-cart').innerHTML='';return;}
  document.getElementById('no-cart').innerHTML=`<div class="items-list">${
    orderCartItems.map(i=>`<div class="item-row">
      <span>${esc(i.name)}</span><span>${i.qty} шт</span>
      <span class="item-row-del" onclick="orderRemoveItem(${i.article})">✕</span>
    </div>`).join('')}</div>`;
}
function orderRemoveItem(a){orderCartItems=orderCartItems.filter(i=>i.article!==a);renderOrderCart();}
async function submitNewOrder(){
  if(!orderCartItems.length)return alert('Добавьте товары');
  const storeId=+document.getElementById('no-store').value;
  const suppId=+document.getElementById('no-supp').value;
  try{
    await post('/orders',{store_id:storeId,supplier_id:suppId,
      items:orderCartItems.map(i=>({article:i.article,qty:i.qty}))});
    closeModal();pgOrders();
  }catch(e){alert(e.message);}
}

JS4_EOF
ok "app.js: Orders page"


cat >> "$PROJ/frontend/js/app.js" << 'JS5_EOF'

// ═══════════════════════════════════════════════════════════════
// PAGE: CLIENTS
// ═══════════════════════════════════════════════════════════════
let clientsData=[],clientsPage=1;
async function pgClients(srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/clients',{search:srch});
    clientsData=data;clientsPage=1;
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Поиск</label>
          <input type="text" id="cl-srch" value="${esc(srch)}" placeholder="ФИО или телефон..."></div>
        <button class="btn btn-primary btn-sm" onclick="pgClients(document.getElementById('cl-srch').value)">Найти</button>
      </div>
    </div>
    <div class="card"><div id="clients-table"></div></div>`);
    renderClientsTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderClientsTable(){
  const {items,total,page}=paginate(clientsData,clientsPage,PAGE_SIZE);
  document.getElementById('clients-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>ФИО</th><th>Телефон</th><th>Email</th><th></th></tr></thead>
      <tbody>${items.map(c=>`<tr>
        <td>${esc(c.fio||'—')}</td>
        <td>${esc(c.phone)}</td>
        <td>${esc(c.email||'—')}</td>
        <td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick="viewClient(${c.id})">Профиль</button>
          <button class="btn btn-ghost btn-xs" onclick='modalEditClient(${JSON.stringify(c).replace(/'/g,"&#39;")})'>Изм.</button>
        </td>
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setClientsPage')}`;
}
function setClientsPage(p){clientsPage=p;renderClientsTable();}
async function viewClient(id){
  try{
    const [c,sales]=await Promise.all([get('/clients/'+id),get('/clients/'+id+'/sales')]);
    openModal('Клиент: '+esc(c.fio||c.phone),`
      <div class="form-row" style="margin-bottom:12px">
        <div><label>ФИО</label><p>${esc(c.fio||'—')}</p></div>
        <div><label>Телефон</label><p>${esc(c.phone)}</p></div>
        <div><label>Email</label><p>${esc(c.email||'—')}</p></div>
        <div><label>Покупок</label><p><b>${c.purchase_count}</b></p></div>
        <div><label>Потрачено</label><p><b>${fmtMoney(c.total_spent)}</b></p></div>
      </div><hr class="separator">
      <div class="card-title" style="font-size:15px">История покупок</div>
      <div class="tbl-wrap"><table>
        <thead><tr><th>Дата</th><th>Магазин</th><th>Сумма</th><th>Оплата</th></tr></thead>
        <tbody>${sales.slice(0,10).map(s=>`<tr>
          <td>${fmtDate(s.date)}</td><td><small>${esc(s.store)}</small></td>
          <td><b>${fmtMoney(s.total)}</b></td><td>${esc(s.payment)}</td></tr>`).join('')}
        </tbody></table></div>`,
      '<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}
function modalEditClient(c){
  openModal('Редактировать клиента',`
    <div class="form-group"><label>ФИО</label><input id="ec-fio" value="${esc(c.fio||'')}"></div>
    <div class="form-row">
      <div class="form-group"><label>Телефон</label><input id="ec-phone" value="${esc(c.phone)}"></div>
      <div class="form-group"><label>Email</label><input id="ec-email" value="${esc(c.email||'')}"></div>
    </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveClient(${c.id})">Сохранить</button>`);
}
async function saveClient(id){
  const data={fio:document.getElementById('ec-fio').value,
    phone:document.getElementById('ec-phone').value,
    email:document.getElementById('ec-email').value};
  try{await put('/clients/'+id,data);closeModal();pgClients();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: SUPPLIERS
// ═══════════════════════════════════════════════════════════════
async function pgSuppliers(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/suppliers');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Поставщики</div>
      ${ROLE==='ADMIN'?'<button class="btn btn-outline" onclick="modalSupplier()">+ Добавить</button>':''}
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Название</th><th>Email</th><th>Телефон</th><th>Заказов</th>${ROLE==='ADMIN'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(s=>`<tr>
          <td><b>${esc(s.name)}</b></td>
          <td>${esc(s.email)}</td>
          <td>${esc(s.phone)}</td>
          <td><span class="badge badge-info">${s.order_count}</span></td>
          ${ROLE==='ADMIN'?`<td class="td-actions">
            <button class="btn btn-ghost btn-xs" onclick='modalSupplier(${JSON.stringify(s).replace(/'/g,"&#39;")})'>Изм.</button>
            <button class="btn btn-danger btn-xs" onclick="deleteSupplier(${s.id})">Удал.</button>
          </td>`:''}
        </tr>`).join('')}</tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalSupplier(s=null){
  openModal(s?'Редактировать поставщика':'Новый поставщик',`
    <div class="form-group"><label>Название</label><input id="sp-name" value="${esc(s?s.name:'')}"></div>
    <div class="form-group"><label>Email</label><input id="sp-email" type="email" value="${esc(s?s.email:'')}"></div>
    <div class="form-group"><label>Телефон</label><input id="sp-phone" value="${esc(s?s.phone:'')}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveSupplier(${s?s.id:0})">Сохранить</button>`);
}
async function saveSupplier(id){
  const data={name:document.getElementById('sp-name').value,
    email:document.getElementById('sp-email').value,
    phone:document.getElementById('sp-phone').value};
  try{
    if(id) await put('/suppliers/'+id,data);
    else await post('/suppliers',data);
    closeModal();pgSuppliers();
  }catch(e){alert(e.message);}
}
async function deleteSupplier(id){
  if(!confirm('Удалить поставщика?'))return;
  try{await del('/suppliers/'+id);pgSuppliers();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: STORES
// ═══════════════════════════════════════════════════════════════
async function pgStores(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/stores');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Магазины сети</div>
      ${ROLE==='ADMIN'?'<button class="btn btn-outline" onclick="modalStore()">+ Добавить</button>':''}
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>#</th><th>Адрес</th><th>Телефон</th><th>Менеджер</th>${ROLE==='ADMIN'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(s=>`<tr>
          <td>${s.id}</td>
          <td>${esc(s.address)}</td>
          <td>${esc(s.phone)}</td>
          <td>${esc(s.manager||'—')}</td>
          ${ROLE==='ADMIN'?`<td class="td-actions">
            <button class="btn btn-ghost btn-xs" onclick='modalStore(${JSON.stringify(s).replace(/'/g,"&#39;")})'>Изм.</button>
            <button class="btn btn-danger btn-xs" onclick="deleteStore(${s.id})">Удал.</button>
          </td>`:''}
        </tr>`).join('')}</tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalStore(s=null){
  openModal(s?'Редактировать магазин':'Новый магазин',`
    <div class="form-group"><label>Адрес</label><input id="ms-addr" value="${esc(s?s.address:'')}"></div>
    <div class="form-group"><label>Телефон</label><input id="ms-phone" value="${esc(s?s.phone:'')}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveStore(${s?s.id:0})">Сохранить</button>`);
}
async function saveStore(id){
  const data={address:document.getElementById('ms-addr').value,phone:document.getElementById('ms-phone').value};
  try{
    if(id) await put('/stores/'+id,data);
    else await post('/stores',data);
    closeModal();pgStores();
  }catch(e){alert(e.message);}
}
async function deleteStore(id){
  if(!confirm('Удалить магазин #'+id+'?'))return;
  try{await del('/stores/'+id);pgStores();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: REVIEWS
// ═══════════════════════════════════════════════════════════════
async function pgReviews(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/reviews');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Отзывы клиентов</div>
      ${ROLE==='CLIENT'?'<button class="btn btn-outline" onclick="modalNewReview()">+ Оставить отзыв</button>':''}
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Клиент</th><th>Рейтинг</th><th>Комментарий</th><th>Дата</th>${ROLE==='ADMIN'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(r=>`<tr>
          <td><b>${esc(r.client||'—')}</b></td>
          <td><span class="stars">${stars(r.rating)}</span></td>
          <td>${esc(r.comment||'—')}</td>
          <td>${fmtDate(r.date)}</td>
          ${ROLE==='ADMIN'?`<td><button class="btn btn-danger btn-xs" onclick="deleteReview(${r.id})">Удал.</button></td>`:''}
        </tr>`).join('')}</tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalNewReview(){
  openModal('Оставить отзыв',`
    <div class="form-group"><label>Рейтинг</label>
      <select id="rv-rating">
        <option value="5">★★★★★ — Отлично</option>
        <option value="4">★★★★☆ — Хорошо</option>
        <option value="3">★★★☆☆ — Нормально</option>
        <option value="2">★★☆☆☆ — Плохо</option>
        <option value="1">★☆☆☆☆ — Ужасно</option>
      </select></div>
    <div class="form-group"><label>Комментарий</label>
      <textarea id="rv-comment" placeholder="Расскажите о вашем опыте..."></textarea></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="submitReview()">Отправить</button>`);
}
async function submitReview(){
  const rating=+document.getElementById('rv-rating').value;
  const comment=document.getElementById('rv-comment').value;
  try{
    await post('/reviews',{client_id:+REF,rating,comment});
    closeModal();pgReviews();
  }catch(e){alert(e.message);}
}
async function deleteReview(id){
  if(!confirm('Удалить отзыв?'))return;
  try{await del('/reviews/'+id);pgReviews();}catch(e){alert(e.message);}
}
JS5_EOF
ok "app.js: Clients, Suppliers, Stores, Reviews"


cat >> "$PROJ/frontend/js/app.js" << 'JS6_EOF'

// ═══════════════════════════════════════════════════════════════
// PAGE: REPORTS — 4 отчёта из ТЗ + топ клиентов
// ═══════════════════════════════════════════════════════════════
async function pgReports(){
  setPage(`
  <div id="page-alert"></div>
  <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;margin-bottom:16px">
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('sales_by_cat')">
      <div class="card-title">📊 Продажи по категориям</div>
      <p style="font-size:12px;color:var(--smoke)">Выручка, количество и доля по каждой категории товаров за период</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('stock_status')">
      <div class="card-title">📦 Остатки в магазине</div>
      <p style="font-size:12px;color:var(--smoke)">Товары с критическим остатком, требующие пополнения</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('orders_rep')">
      <div class="card-title">📋 Заказы поставщикам</div>
      <p style="font-size:12px;color:var(--smoke)">Все заказы по поставщикам, периодам и статусам</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('revenue')">
      <div class="card-title">💰 Выручка по магазинам</div>
      <p style="font-size:12px;color:var(--smoke)">Сравнительный анализ выручки, транзакций и среднего чека</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('top_clients')">
      <div class="card-title">👑 Топ клиентов</div>
      <p style="font-size:12px;color:var(--smoke)">Лучшие клиенты по объёму покупок за период</p>
    </div>
  </div>
  <div id="report-result"></div>`);
}

async function loadReport(type){
  const el=document.getElementById('report-result');
  if(!el)return;
  el.innerHTML='<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>';
  try{
    if(type==='sales_by_cat') await reportSalesByCat();
    else if(type==='stock_status') await reportStock();
    else if(type==='orders_rep') await reportOrders();
    else if(type==='revenue') await reportRevenue();
    else if(type==='top_clients') await reportTopClients();
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}

async function reportSalesByCat(){
  const today=new Date().toISOString().slice(0,10);
  const from='2024-01-01';
  const data=await get('/reports/sales-by-category',{from,to:today});
  const max=Math.max(...data.map(r=>r.revenue),1);
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">📊 Продажи по категориям
      <span style="font-size:12px;color:var(--smoke);font-family:'DM Sans',sans-serif">${fmtDate(from)} — ${fmtDate(today)}</span>
    </div>
    <div class="chart-bar-wrap">${data.map(r=>`
      <div class="chart-bar-row">
        <div class="chart-bar-label">${esc(r.category)}</div>
        <div class="chart-bar-track">
          <div class="chart-bar-fill" style="width:${(r.revenue/max*100).toFixed(1)}%">
            ${r.pct}%
          </div>
        </div>
        <div class="chart-bar-val">${fmtMoney(r.revenue)}</div>
      </div>`).join('')}
    </div>
    <hr class="separator">
    <div class="tbl-wrap"><table>
      <thead><tr><th>Категория</th><th>Кол-во ед.</th><th>Выручка</th><th>Доля %</th></tr></thead>
      <tbody>${data.map(r=>`<tr>
        <td><span class="badge badge-gold">${esc(r.category)}</span></td>
        <td>${fmt(r.qty)}</td>
        <td><b>${fmtMoney(r.revenue)}</b></td>
        <td>${r.pct}%</td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

async function reportStock(){
  const stores=await get('/stores');
  if(!stores.length)return;
  const storeId=stores[0].id;
  const data=await get('/reports/stock-status',{store_id:storeId,threshold:5});
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">📦 Остатки в магазине: <span style="font-size:14px;font-family:'DM Sans'">${esc(stores[0].address)}</span></div>
    <div style="margin-bottom:12px">
      <span class="badge badge-danger" style="margin-right:8px">Нет в наличии: ${data.filter(r=>r.qty===0).length}</span>
      <span class="badge badge-warning" style="margin-right:8px">Критично (≤2): ${data.filter(r=>r.qty>0&&r.qty<=2).length}</span>
      <span class="badge badge-info">Мало (≤5): ${data.filter(r=>r.qty>2&&r.qty<=5).length}</span>
    </div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th><th>Остаток</th><th>Статус</th></tr></thead>
      <tbody>${data.map(r=>{
        const badge=r.qty===0?'badge-danger':r.qty<=2?'badge-warning':'badge-info';
        const label=r.qty===0?'Нет':r.qty<=2?'Критично':'Мало';
        return`<tr>
          <td><code>${r.article}</code></td><td>${esc(r.name)}</td>
          <td><span class="badge badge-gold">${esc(r.category)}</span></td>
          <td>${fmtMoney(r.price)}</td><td><b>${r.qty}</b></td>
          <td><span class="badge ${badge}">${label}</span></td></tr>`}).join('')}
      </tbody></table></div>
  </div>`;
}

async function reportOrders(){
  const data=await get('/reports/orders',{});
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">📋 Заказы поставщикам</div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Дата</th><th>Поставщик</th><th>Магазин</th><th>Менеджер</th><th>Статус</th><th>Сумма</th></tr></thead>
      <tbody>${data.map(r=>`<tr>
        <td>${r.id}</td><td>${fmtDate(r.date)}</td>
        <td>${esc(r.supplier)}</td><td><small>${esc(r.store)}</small></td>
        <td><small>${esc(r.manager)}</small></td>
        <td>${statusBadge(r.status)}</td>
        <td><b>${fmtMoney(r.total)}</b></td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

async function reportRevenue(){
  const from='2024-01-01',to=new Date().toISOString().slice(0,10);
  const data=await get('/reports/revenue-by-store',{from,to});
  const max=Math.max(...data.map(r=>r.revenue),1);
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">💰 Выручка по магазинам
      <span style="font-size:12px;color:var(--smoke);font-family:'DM Sans'">${fmtDate(from)} — ${fmtDate(to)}</span>
    </div>
    <div class="chart-bar-wrap" style="margin-bottom:16px">${data.map(r=>`
      <div class="chart-bar-row">
        <div class="chart-bar-label">${esc(r.store.split(',')[1]?.trim()||r.store)}</div>
        <div class="chart-bar-track">
          <div class="chart-bar-fill" style="width:${(r.revenue/max*100).toFixed(1)}%">
            ${fmtMoney(r.revenue)}
          </div>
        </div>
        <div class="chart-bar-val">${r.tx_count} прод.</div>
      </div>`).join('')}
    </div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Магазин</th><th>Выручка</th><th>Транзакций</th><th>Средний чек</th></tr></thead>
      <tbody>${data.map(r=>`<tr>
        <td>${esc(r.store)}</td>
        <td><b>${fmtMoney(r.revenue)}</b></td>
        <td>${fmt(r.tx_count)}</td>
        <td>${fmtMoney(r.avg_check)}</td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

async function reportTopClients(){
  const from='2024-01-01',to=new Date().toISOString().slice(0,10);
  const data=await get('/reports/top-customers',{from,to,limit:10});
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">👑 Топ-10 клиентов по выручке</div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>№</th><th>ФИО</th><th>Телефон</th><th>Покупок</th><th>Сумма</th><th>Средний чек</th></tr></thead>
      <tbody>${data.map((r,i)=>`<tr>
        <td><span class="badge ${i<3?'badge-gold':''}">${i+1}</span></td>
        <td><b>${esc(r.fio||'—')}</b></td>
        <td>${esc(r.phone)}</td>
        <td>${r.count}</td>
        <td><b>${fmtMoney(r.total)}</b></td>
        <td>${fmtMoney(r.avg)}</td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

// ═══════════════════════════════════════════════════════════════
// PAGE: CATALOG (клиент)
// ═══════════════════════════════════════════════════════════════
async function pgCatalog(cat='',srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/products',{category:cat,search:srch});
    const cats=[...new Set(data.map(p=>p.category))].sort();
    const catOpts=cats.map(c=>`<option value="${c}" ${cat===c?'selected':''}>${c}</option>`).join('');
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Категория</label>
          <select id="cat-cat"><option value="">Все категории</option>${catOpts}</select></div>
        <div class="filter-group"><label>Поиск</label>
          <input type="text" id="cat-srch" value="${esc(srch)}" placeholder="Название..."></div>
        <button class="btn btn-primary btn-sm" onclick="pgCatalog(document.getElementById('cat-cat').value,document.getElementById('cat-srch').value)">Найти</button>
      </div>
    </div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:14px;margin-top:14px">
      ${data.map(p=>`
      <div class="card" style="padding:16px;margin-bottom:0">
        <div style="font-size:28px;text-align:center;margin-bottom:10px">💍</div>
        <div style="font-weight:600;margin-bottom:4px;font-size:13px">${esc(p.name)}</div>
        <div style="margin-bottom:8px"><span class="badge badge-gold">${esc(p.category)}</span></div>
        <div style="font-family:'Cormorant Garamond',serif;font-size:20px;color:var(--gold-dark);font-weight:400">${fmtMoney(p.price)}</div>
        <div style="font-size:11px;color:var(--smoke);margin-top:2px">Арт. ${p.article}</div>
      </div>`).join('')}
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: MY PURCHASES (клиент)
// ═══════════════════════════════════════════════════════════════
async function pgMyPurchases(from='',to=''){
  if(!REF)return setPage('<div class="alert alert-err">Не определён профиль клиента</div>');
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/clients/'+REF+'/sales',{from,to});
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="mp-from" value="${from}"></div>
        <div class="filter-group"><label>По</label><input type="date" id="mp-to" value="${to}"></div>
        <button class="btn btn-primary btn-sm" onclick="pgMyPurchases(document.getElementById('mp-from').value,document.getElementById('mp-to').value)">Применить</button>
      </div>
    </div>
    <div class="card">
      ${!data.length?'<div class="empty-state"><div class="esi">🛍️</div><p>Покупок пока нет</p></div>':''}
      <div class="tbl-wrap">${data.length?`<table>
        <thead><tr><th>Дата</th><th>Магазин</th><th>Товары</th><th>Сумма</th><th>Оплата</th></tr></thead>
        <tbody>${data.map(s=>`<tr>
          <td>${fmtDate(s.date)}</td>
          <td><small>${esc(s.store)}</small></td>
          <td><small>${esc((s.products||'').replace(/[{}"]/g,''))}</small></td>
          <td><b>${fmtMoney(s.total)}</b></td>
          <td>${esc(s.payment)}</td>
        </tr>`).join('')}</tbody>
      </table>`:''}
      </div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// ═══════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded',()=>{
  tryAutoLogin();
  document.getElementById('au-pass')?.addEventListener('keydown',e=>{if(e.key==='Enter')doLogin();});
  document.getElementById('au-user')?.addEventListener('keydown',e=>{if(e.key==='Enter')doLogin();});
});
JS6_EOF
ok "app.js: Reports, Catalog, MyPurchases, init"


# ═══════════════════════════════════════════════════════════════
# FINAL: README + run script + completion message
# ═══════════════════════════════════════════════════════════════
hdr "12. README"
cat > "$PROJ/README.md" << 'README_EOF'
# LUMI·NET — ИС для сети ювелирных магазинов

## Стек
- **Backend**: C++17 / Drogon 1.8+
- **База данных**: PostgreSQL 15
- **Frontend**: Vanilla JS SPA + Nginx
- **Оркестрация**: Docker Compose

## Быстрый старт

```bash
# 1. Убедитесь, что установлены Docker и Docker Compose
docker --version && docker compose version

# 2. Запустите проект
docker compose up --build

# 3. Откройте браузер
# http://localhost
```

## Тестовые аккаунты

| Логин     | Пароль   | Роль               |
|-----------|----------|--------------------|
| admin     | admin123 | Администратор сети |
| manager1  | pass123  | Менеджер (маг. 1)  |
| manager2  | pass123  | Менеджер (маг. 2)  |
| cashier1  | pass123  | Кассир (маг. 1)    |
| cashier2  | pass123  | Кассир (маг. 1)    |
| client1   | pass123  | Клиент             |

## API Endpoints

### Auth
- `POST /api/auth/login` — вход
- `POST /api/auth/register` — регистрация клиента
- `GET  /api/auth/me` — текущий пользователь

### Продажи
- `GET  /api/sales` — список продаж (фильтры: store_id, from, to)
- `GET  /api/sales/:id` — детали продажи
- `POST /api/sales` — создать продажу
- `GET  /api/clients/:id/sales` — история клиента

### Товары
- `GET    /api/products` — каталог (фильтры: category, search, store_id)
- `POST   /api/products` — добавить товар
- `PUT    /api/products/:article` — обновить
- `DELETE /api/products/:article` — удалить

### Остатки
- `GET /api/stores/:id/stock` — остатки магазина (фильтр: threshold)
- `PUT /api/stock/:id` — изменить количество

### Заказы
- `GET /api/orders` — заказы (фильтры: store_id, status, supplier_id)
- `GET /api/orders/:id` — детали
- `POST /api/orders` — создать (вызывает хранимую процедуру)
- `PUT  /api/orders/:id/status` — изменить статус

### Отчёты
- `GET /api/reports/sales-by-category` — продажи по категориям
- `GET /api/reports/stock-status` — остатки (требует store_id)
- `GET /api/reports/orders` — заказы поставщикам
- `GET /api/reports/revenue-by-store` — выручка по магазинам
- `GET /api/reports/top-customers` — топ клиентов

## Структура БД

13 таблиц: CLIENT, CASHIER, MANAGER, STORE, SUPPLIER, PRODUCT,
SALE, SALE_ITEM, ORDER, ORDER_ITEM, STOCK, REVIEW, app_users

**Триггеры:**
- `trg_update_stock_on_sale` — авто-списание остатков при продаже
- `trg_check_unique_email` — проверка уникальности email клиента

**Хранимая процедура:**
- `create_supplier_order(...)` — транзакционное создание заказа
README_EOF
ok "README.md"

# ─── run.sh — удобный запуск ─────────────────────────────────
cat > "$PROJ/run.sh" << 'RUN_EOF'
#!/bin/bash
echo "🚀 Запуск LUMI·NET..."
cd "$(dirname "$0")"
docker compose down 2>/dev/null
docker compose up --build "$@"
RUN_EOF
chmod +x "$PROJ/run.sh"
ok "run.sh"

# ─── .dockerignore ───────────────────────────────────────────
cat > "$PROJ/backend/.dockerignore" << 'EOF'
cmake-build/
*.o
*.a
.git
EOF

# ─── Итоговый вывод ──────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅  Проект сгенерирован успешно!${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  📁 Структура:"
echo -e "     ├── database/          ← SQL скрипты (ваши + seed)"
echo -e "     ├── backend/           ← C++17/Drogon REST API"
echo -e "     │   ├── src/controllers/  (11 контроллеров)"
echo -e "     │   ├── src/utils/        (JWT без зависимостей)"
echo -e "     │   └── Dockerfile"
echo -e "     ├── frontend/          ← SPA (HTML + JS)"
echo -e "     ├── nginx/             ← reverse proxy конфиг"
echo -e "     ├── docker-compose.yml"
echo -e "     └── run.sh"
echo ""
echo -e "  🚀 ${BOLD}Запуск:${NC}"
echo -e "     ${YELLOW}./run.sh${NC}"
echo -e "     или: ${YELLOW}docker compose up --build${NC}"
echo ""
echo -e "  🌐 Откройте браузер: ${BLUE}http://localhost${NC}"
echo ""
echo -e "  🔑 Тестовые аккаунты:"
echo -e "     admin / admin123    (Администратор)"
echo -e "     manager1 / pass123  (Менеджер)"
echo -e "     cashier1 / pass123  (Кассир)"
echo -e "     client1 / pass123   (Клиент)"
echo ""
echo -e "  ⏱️  Первый билд займёт 5–10 минут"
echo -e "     (компиляция Drogon из drogonframework/drogon:latest)"
echo ""

