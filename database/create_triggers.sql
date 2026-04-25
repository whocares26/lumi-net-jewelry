CREATE OR REPLACE FUNCTION update_stock_on_sale()
RETURNS TRIGGER AS $$
DECLARE
    v_store_id      INTEGER;
    v_current_stock INTEGER;
BEGIN
    -- Получить магазин из соответствующей продажи
    SELECT store_id INTO v_store_id
    FROM SALE WHERE sale_id = NEW.sale_id;

    -- Найти текущий остаток
    SELECT stock_quantity INTO v_current_stock
    FROM STOCK
    WHERE store_id = v_store_id
      AND product_article = NEW.product_article;

    -- Проверка достаточности остатка
    IF v_current_stock < NEW.sale_item_quantity THEN
        RAISE EXCEPTION
            'Недостаточно товара на складе. Требуется %, доступно %.',
            NEW.sale_item_quantity, v_current_stock;
    END IF;

    -- Уменьшить остаток
    UPDATE STOCK
    SET stock_quantity = stock_quantity - NEW.sale_item_quantity
    WHERE store_id = v_store_id
      AND product_article = NEW.product_article;

    RAISE NOTICE 'Обновлён остаток товара % на складе %: -% шт.',
        NEW.product_article, v_store_id, NEW.sale_item_quantity;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_stock_on_sale ON SALE_ITEM;

CREATE TRIGGER trg_update_stock_on_sale
AFTER INSERT ON SALE_ITEM
FOR EACH ROW
EXECUTE FUNCTION update_stock_on_sale();



CREATE OR REPLACE FUNCTION check_unique_client_email()
RETURNS TRIGGER AS $$
DECLARE
    v_existing_client_id INT;
BEGIN
    SELECT client_id INTO v_existing_client_id
    FROM CLIENT
    WHERE client_email = NEW.client_email
      AND client_id != NEW.client_id;

    IF v_existing_client_id IS NOT NULL THEN
        RAISE EXCEPTION
            'Клиент с email "%" уже существует (ID: %).'
            ' Email должен быть уникальным.',
            NEW.client_email, v_existing_client_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_unique_email
BEFORE INSERT OR UPDATE OF client_email ON CLIENT
FOR EACH ROW
EXECUTE FUNCTION check_unique_client_email();