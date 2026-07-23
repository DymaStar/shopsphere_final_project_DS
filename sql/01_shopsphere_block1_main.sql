/*
====================================================================
SHOPSPHERE — БЛОК 1. ОБОВ'ЯЗКОВІ SQL-ЗАПИТИ
====================================================================

Файл містить тільки завдання 1.1–1.5 з офіційного проєкту.
SQL-діалект: SQLite.

Як працювати з файлом:
1. Виконуйте кожен запит окремо.
2. У SQLiteOnline назви таблиць мають префікс shopsphere_.
3. Грошові показники подані в USD.
4. ROUND(..., 2) округлює результат до двох знаків після коми.
5. COUNT(DISTINCT ...) захищає кількість замовлень від дублювання
   після JOIN.

ВИПРАВЛЕННЯ (аудит, 07.2026):
- Task 1.4 переписано через WITH/CTE замість подвійного дублювання
  одного й того самого підзапиту (SELECT customer_id, SUM(net_amount)
  ... GROUP BY customer_id) у SELECT та у WHERE. Результат
  ідентичний оригіналу — перевірено на реальних даних, усі 4
  показники збігаються до копійки. Зміна суто про читабельність
  коду й відсутність дублювання логіки, не про правильність.

Особливості імпортованих таблиць SQLiteOnline:
- вихідне поле acquisition_channel збережене як acquisition_chan;
- вихідне поле attributed_revenue збережене як attributed_reven.

Аліаси вихідних колонок залишені англійською, щоб їх було зручно
використовувати в Tableau та звіті.
*/


/*
====================================================================
TASK 1.1
Revenue, Orders and AOV by Region and Year
====================================================================

Мета:
Порахувати чисту виручку, кількість замовлень і середній чек
для кожного регіону за кожен рік.

Рівень деталізації результату:
один рядок = один регіон + один рік.

Алгоритм:
1. Беремо замовлення з shopsphere_orders.
2. Через customer_id приєднуємо регіон із shopsphere_customers.
3. Групуємо дані за region та order_year.
4. SUM(net_amount) рахує чисту виручку.
5. COUNT(DISTINCT order_id) рахує унікальні замовлення.
6. AOV = чиста виручка / кількість замовлень.

Очікуваний результат:
15 рядків = 5 регіонів × 3 роки.
*/

SELECT
    c.region,
    o.order_year,

    -- Загальна чиста виручка регіону за рік
    ROUND(SUM(o.net_amount), 2) AS total_net_revenue,

    -- Кількість унікальних замовлень
    COUNT(DISTINCT o.order_id) AS total_orders,

    -- Середній чек: виручка / кількість замовлень
    ROUND(
        SUM(o.net_amount) / COUNT(DISTINCT o.order_id),
        2
    ) AS average_order_value

FROM shopsphere_orders AS o

-- Додаємо регіон клієнта до кожного замовлення
JOIN shopsphere_customers AS c
    ON o.customer_id = c.customer_id

GROUP BY
    c.region,
    o.order_year

ORDER BY
    c.region,
    o.order_year;


/*
====================================================================
TASK 1.2
Top 10 Customers by Total Spend
====================================================================

Мета:
Знайти десять клієнтів із найбільшою загальною сумою витрат і
показати їхній регіон, канал залучення та кількість замовлень.

Рівень деталізації результату:
один рядок = один клієнт.

Алгоритм:
1. Об'єднуємо orders і customers через customer_id.
2. Групуємо всі замовлення одного клієнта.
3. SUM(net_amount) рахує загальні витрати клієнта.
4. COUNT(DISTINCT order_id) рахує його замовлення.
5. Сортуємо total_spend від найбільшого до найменшого.
6. LIMIT 10 залишає перші десять клієнтів.

Примітка:
У цій імпортованій таблиці поле acquisition_channel збережене
під назвою acquisition_chan. Через AS повертаємо зрозумілу назву.
*/

SELECT
    o.customer_id,
    c.region,
    c.acquisition_chan AS acquisition_channel,

    -- Загальна сума витрат клієнта
    ROUND(SUM(o.net_amount), 2) AS total_spend,

    -- Кількість його унікальних замовлень
    COUNT(DISTINCT o.order_id) AS total_orders

FROM shopsphere_orders AS o

JOIN shopsphere_customers AS c
    ON o.customer_id = c.customer_id

GROUP BY
    o.customer_id,
    c.region,
    c.acquisition_chan

ORDER BY
    total_spend DESC,
    o.customer_id

LIMIT 10;


/*
====================================================================
TASK 1.3
Revenue, Margin and Return Rate by Product Category
====================================================================

Мета:
Для кожної категорії товарів розрахувати виручку, середню маржу
та частку повернених замовлень.

Рівень деталізації результату:
один рядок = одна категорія товару.

Чому потрібні три таблиці:
- order_items містить продані позиції та line_total;
- products містить category і margin_pct;
- orders містить ознаку повернення is_returned.

Алгоритм:
1. order_items з'єднуємо з products через product_id.
2. order_items з'єднуємо з orders через order_id.
3. SUM(line_total) рахує виручку проданих позицій категорії.
4. AVG(margin_pct) рахує середню маржу серед проданих позицій.
5. Для return rate рахуємо унікальні повернені замовлення і
   ділимо їх на всі унікальні замовлення категорії.
6. Множимо частку на 100, щоб отримати відсоток.

Важливо:
COUNT(DISTINCT order_id) потрібен, тому що одне замовлення може
містити кілька товарних позицій однієї категорії.
*/

SELECT
    p.category,

    -- Виручка всіх проданих позицій категорії
    ROUND(SUM(oi.line_total), 2) AS total_revenue,

    -- Середня маржа серед проданих товарних позицій
    ROUND(AVG(p.margin_pct), 2) AS average_margin_pct,

    -- Частка повернених замовлень категорії у відсотках
    ROUND(
        100.0 * COUNT(
            DISTINCT CASE
                WHEN o.is_returned = 1 THEN o.order_id
            END
        ) / COUNT(DISTINCT o.order_id),
        2
    ) AS return_rate_pct

FROM shopsphere_order_items AS oi

-- Додаємо категорію та маржу товару
JOIN shopsphere_products AS p
    ON oi.product_id = p.product_id

-- Додаємо інформацію про повернення замовлення
JOIN shopsphere_orders AS o
    ON oi.order_id = o.order_id

GROUP BY
    p.category

ORDER BY
    total_revenue DESC;


/*
====================================================================
TASK 1.4
Customers Whose Total Spend Exceeds the Customer Average
====================================================================

Мета:
Знайти клієнтів, які витратили більше за середню загальну суму
витрат одного клієнта, порахувати їх кількість і частку виручки.

Чому використовується CTE:
Спочатку потрібно отримати total_spend кожного клієнта, а вже потім
порахувати середнє між клієнтами. AVG(net_amount) напряму рахував би
середнє замовлення, а не середні витрати клієнта.

ВИПРАВЛЕННЯ (аудит):
У попередній версії один і той самий підзапит (агрегація
customer_id → total_spend) дублювався двічі: один раз у SELECT для
average_customer_spend, другий раз у WHERE для порогу. Результат
був правильний, але це зайве дублювання коду й зайве повторне
сканування таблиці. Винесено обидва обчислення в спільні CTE
customer_totals і average_spend, порахований один раз.

Алгоритм:
1. CTE customer_totals групує orders за customer_id → total_spend.
2. CTE average_spend рахує AVG(total_spend) один раз для всіх
   клієнтів.
3. WHERE залишає клієнтів із total_spend вище цього середнього.
4. Зовнішній SELECT рахує кількість таких клієнтів і їхню виручку.
5. Частка виручки = їхня виручка / вся net revenue × 100.

Очікуваний результат:
один підсумковий рядок.
*/

WITH customer_totals AS (
    -- Крок 1: загальні витрати кожного клієнта
    SELECT
        customer_id,
        SUM(net_amount) AS total_spend
    FROM shopsphere_orders
    GROUP BY customer_id
),

average_spend AS (
    -- Крок 2: середня загальна сума витрат одного клієнта
    SELECT AVG(total_spend) AS average_customer_spend
    FROM customer_totals
)

SELECT
    -- Кількість клієнтів вище середнього
    COUNT(*) AS above_average_customers,

    -- Середня загальна сума витрат одного клієнта
    ROUND((SELECT average_customer_spend FROM average_spend), 2)
        AS average_customer_spend,

    -- Виручка від клієнтів вище середнього
    ROUND(SUM(customer_totals.total_spend), 2)
        AS above_average_revenue,

    -- Їхня частка в загальній чистій виручці
    ROUND(
        100.0 * SUM(customer_totals.total_spend)
        / (SELECT SUM(net_amount) FROM shopsphere_orders),
        2
    ) AS revenue_share_pct

FROM customer_totals, average_spend

WHERE customer_totals.total_spend > average_spend.average_customer_spend;


/*
====================================================================
TASK 1.5
Budget, Attributed Revenue and Marketing ROI by Channel
====================================================================
У завданні показник названо ROI.
Однак формула attributed_revenue / budget
за стандартною маркетинговою термінологією відповідає ROAS.

Мета:
Порівняти маркетингові канали за бюджетом, приписаною виручкою
та показником Marketing ROI.

Рівень деталізації результату:
один рядок = один маркетинговий канал.

Алгоритм:
1. Групуємо кампанії за channel.
2. SUM(budget) рахує загальні витрати каналу.
3. SUM(attributed_reven) рахує приписану каналу виручку.
4. Marketing ROI = сума приписаної виручки / сума бюджету.
5. Сортуємо канали від найефективнішого до найменш ефективного.

Важливо:
В офіційному завданні показник названо ROI. За формулою revenue / budget
він технічно близький до ROAS, але у проєкті зберігаємо назву викладача
Marketing ROI і показуємо результат у форматі x.

Примітка:
У цій імпортованій таблиці поле attributed_revenue збережене як
attributed_reven.
*/

SELECT
    channel,

    -- Загальний бюджет усіх кампаній каналу
    ROUND(SUM(budget), 2) AS total_budget,

    -- Загальна приписана виручка каналу
    ROUND(SUM(attributed_reven), 2)
        AS total_attributed_revenue,

    -- Скільки доларів виручки припадає на $1 бюджету
    ROUND(
        1.0 * SUM(attributed_reven) / SUM(budget),
        2
    ) AS marketing_roi

FROM shopsphere_marketing

GROUP BY
    channel

ORDER BY
    marketing_roi DESC;
