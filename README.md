# LUMI·NET — ИС для сети ювелирных магазинов

## Стек
- **Backend**: C++23 / Drogon 1.8+
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
