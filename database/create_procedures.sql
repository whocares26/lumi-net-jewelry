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
