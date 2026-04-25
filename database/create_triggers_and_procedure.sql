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

CREATE OR REPLACE PROCEDURE create_supplier_order(
    p_store_id INT,
    p_supplier_id INT,
    p_product_articles INT[],
    p_quantities INT[],
    OUT p_new_order_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_amount INT8 := 0;
    v_manager_snils CHAR(14);
    v_product_article INT4;
    v_order_quantity INT4;
    v_product_price INT4;
    v_item_cost INT8;
    v_order_date DATE := CURRENT_DATE;
    v_order_item_id INT4 := 1;
    i INT;
    v_array_length INT;
BEGIN
    -- 1. Проверка существования магазина
    IF NOT EXISTS (SELECT 1 FROM STORE WHERE store_id = p_store_id) THEN
        RAISE EXCEPTION 'Магазин с ID % не найден.', p_store_id;
    END IF;

    -- 2. Получение СНИЛС менеджера магазина
    SELECT manager_snils INTO v_manager_snils
    FROM STORE WHERE store_id = p_store_id;

    IF v_manager_snils IS NULL THEN
        RAISE EXCEPTION 'У магазина с ID % не назначен менеджер.', p_store_id;
    END IF;

    -- 3. Проверка существования поставщика
    IF NOT EXISTS (SELECT 1 FROM SUPPLIER WHERE supplier_id = p_supplier_id) THEN
        RAISE EXCEPTION 'Поставщик с ID % не найден.', p_supplier_id;
    END IF;

    -- 4. Проверка массивов товаров и количеств
    v_array_length := array_length(p_product_articles, 1);
    IF v_array_length IS NULL OR v_array_length = 0
       OR v_array_length != array_length(p_quantities, 1) THEN
        RAISE EXCEPTION 'Массивы товаров и количеств должны быть
                         непустыми и одинаковой длины.';
    END IF;

    -- 5. Создание записи заказа
    INSERT INTO "ORDER" (store_id, supplier_id, manager_snils,
                          order_date, order_status, order_total)
    VALUES (p_store_id, p_supplier_id, v_manager_snils,
            v_order_date, 'ожидается', 0)
    RETURNING order_id INTO p_new_order_id;

    -- 6. Обход позиций заказа
    FOR i IN 1..v_array_length LOOP
        v_product_article := p_product_articles[i];
        v_order_quantity  := p_quantities[i];

        SELECT product_price INTO v_product_price
        FROM PRODUCT WHERE product_article = v_product_article;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Товар с артикулом % не найден.', v_product_article;
        END IF;

        v_item_cost      := v_product_price * v_order_quantity;
        v_total_amount   := v_total_amount + v_item_cost;

        INSERT INTO ORDER_ITEM (order_id, order_item_id,
                                product_article, order_item_quantity)
        VALUES (p_new_order_id, v_order_item_id,
                v_product_article, v_order_quantity);

        v_order_item_id := v_order_item_id + 1;
    END LOOP;

    -- 7. Обновление итоговой суммы заказа
    UPDATE "ORDER"
    SET order_total = v_total_amount
    WHERE order_id = p_new_order_id;

    RAISE NOTICE 'Заказ % создан на сумму % руб.',
                  p_new_order_id, v_total_amount;
END;
$$;
