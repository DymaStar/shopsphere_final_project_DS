/*
====================================================================
SHOPSPHERE — ДОПОМІЖНІ SQL-ЗАПИТИ ДЛЯ TABLEAU ТА БІЗНЕС-КЕЙСІВ
====================================================================

Файл містить supporting queries A1–A6.
Вони не замінюють обов'язкові Task 1.1–1.5, а готують зручні таблиці
для візуалізацій Tableau та відповідей на бізнес-питання.

Як працювати з файлом:
1. Виконуйте кожен запит окремо.
2. Експортуйте тільки результат основного запиту, а не validation.
3. Кожний експортований CSV підключайте в Tableau як окремий Data Source.
4. Не робіть JOIN між агрегованими CSV: вони мають різний grain.

Що експортуємо:
- A1 → tableau_a1_monthly_revenue.csv
- A3 → tableau_a3_customer_pareto.csv
- A4 → tableau_a4_discount_segments.csv
- A5 → tableau_a5_ab_overall.csv
- A6 → tableau_a6_ab_segments.csv

A2 використовується як аналітична перевірка регіонального зростання.
Основний multi-line chart будується з результату Task 1.1.
*/


/*
====================================================================
A1. MONTHLY REVENUE TREND
====================================================================

Мета:
Підготувати місячну динаміку виручки за 2022–2024 роки.

Рівень деталізації:
один рядок = один календарний місяць.

Алгоритм:
1. strftime('%Y-%m', order_date) об'єднує рік і місяць.
2. Групуємо всі замовлення одного місяця.
3. Рахуємо виручку, замовлення та середній чек.
4. Сортуємо місяці хронологічно.

Tableau:
лінійний графік Monthly Revenue Trend.

Важливо для висновку:
зростання від року до року не є автоматичним доказом сезонності.
Повторювані піки потрібно порівнювати між роками.
*/

SELECT
    -- Формат YYYY-MM зберігає правильний хронологічний порядок
    strftime('%Y-%m', order_date) AS year_month,

    ROUND(SUM(net_amount), 2) AS total_net_revenue,

    COUNT(DISTINCT order_id) AS total_orders,

    ROUND(
        SUM(net_amount) / COUNT(DISTINCT order_id),
        2
    ) AS average_order_value

FROM shopsphere_orders

GROUP BY
    strftime('%Y-%m', order_date)

ORDER BY
    year_month;


/*
--------------------------------------------------------------------
A1 VALIDATION — ТЕХНІЧНА ПЕРЕВІРКА, НЕ ЕКСПОРТУВАТИ
--------------------------------------------------------------------

Перевіряє:
- кількість місяців;
- загальну виручку;
- кількість замовлень;
- перший і останній місяць.

Очікується:
36 місяців, $3,474,016.03, 12,274 orders, 2022-01 — 2024-12.
*/

SELECT
    COUNT(*) AS total_months,
    ROUND(SUM(monthly_revenue), 2) AS total_net_revenue,
    SUM(monthly_orders) AS total_orders,
    MIN(year_month) AS first_month,
    MAX(year_month) AS last_month

FROM (
    SELECT
        strftime('%Y-%m', order_date) AS year_month,
        SUM(net_amount) AS monthly_revenue,
        COUNT(DISTINCT order_id) AS monthly_orders
    FROM shopsphere_orders
    GROUP BY strftime('%Y-%m', order_date)
) AS monthly_summary;


/*
====================================================================
A2. REGIONAL YEAR-OVER-YEAR REVENUE GROWTH
====================================================================

Мета:
Порахувати зміну регіональної виручки порівняно з попереднім роком.

Рівень деталізації:
один рядок = один регіон + один рік.

Алгоритм:
1. Перший CTE regional_yearly агрегує виручку за region і year.
2. LAG бере виручку попереднього року всередині того самого регіону.
3. YoY = (поточна - попередня) / попередня × 100.
4. Для 2022 року previous_year_revenue і yoy_growth_pct будуть NULL,
   оскільки в датасеті немає 2021 року.

Що таке CTE:
WITH створює тимчасовий іменований результат усередині одного запиту.

Що таке LAG:
віконна функція повертає значення з попереднього рядка після сортування.

Tableau:
A2 можна використати як перевірку. Основний regional chart будуємо
з Task 1.1, щоб не дублювати джерела.
*/

WITH regional_yearly AS (
    -- Крок 1: річна виручка кожного регіону
    SELECT
        c.region,
        o.order_year,
        SUM(o.net_amount) AS total_net_revenue

    FROM shopsphere_orders AS o

    JOIN shopsphere_customers AS c
        ON o.customer_id = c.customer_id

    GROUP BY
        c.region,
        o.order_year
),

regional_with_previous AS (
    -- Крок 2: додаємо виручку попереднього року
    SELECT
        region,
        order_year,
        total_net_revenue,

        LAG(total_net_revenue) OVER (
            PARTITION BY region
            ORDER BY order_year
        ) AS previous_year_revenue

    FROM regional_yearly
)

SELECT
    region,
    order_year,
    ROUND(total_net_revenue, 2) AS total_net_revenue,
    ROUND(previous_year_revenue, 2) AS previous_year_revenue,

    -- Крок 3: відсоток зміни до попереднього року
    ROUND(
        100.0 * (total_net_revenue - previous_year_revenue)
        / previous_year_revenue,
        2
    ) AS yoy_growth_pct

FROM regional_with_previous

ORDER BY
    region,
    order_year;


/*
====================================================================
A3. CUSTOMER-LEVEL DATASET FOR PARETO AND LTV PROXY
====================================================================

Мета:
Створити таблицю, де кожен клієнт має загальні витрати, кількість
замовлень, регіон і канал залучення.

Рівень деталізації:
один рядок = один клієнт.

Алгоритм:
1. JOIN додає region та acquisition channel до orders.
2. GROUP BY збирає всі замовлення одного клієнта.
3. SUM(net_amount) рахує total_spend клієнта.
4. COUNT(DISTINCT order_id) рахує його замовлення.
5. Сортуємо клієнтів за total_spend DESC.

Чому кумулятивні частки не рахуються тут:
Running Total, cumulative revenue share та cumulative customer share
зручніше зробити table calculations у Tableau. Це зберігає баланс:
SQL готує правильний customer-level grain, Tableau будує Pareto.

Використання:
- Block 2.5 Pareto;
- Question 4: Average Customer Spend by Acquisition Channel (LTV proxy);
- Question 9: Top 5% customers і їхній профіль;
- Top 10 можна отримати з перших десяти рядків.

Примітка:
У SQLiteOnline поле acquisition_channel збережене як acquisition_chan.
*/

SELECT
    o.customer_id,
    c.region,
    c.acquisition_chan AS acquisition_channel,

    -- Загальна сума витрат клієнта
    ROUND(SUM(o.net_amount), 2) AS total_spend,

    -- Кількість замовлень клієнта
    COUNT(DISTINCT o.order_id) AS total_orders

FROM shopsphere_orders AS o

JOIN shopsphere_customers AS c
    ON o.customer_id = c.customer_id

GROUP BY
    o.customer_id,
    c.region,
    c.acquisition_chan

ORDER BY
    total_spend DESC;


/*
====================================================================
A4. CUSTOMER BEHAVIOUR BY DISCOUNT SEGMENT
====================================================================

Мета:
Порівняти клієнтів із середньою знижкою понад 20% з рештою клієнтів.

Чому спочатку потрібен customer-level CTE:
Сегмент визначається за середньою знижкою конкретного клієнта, тому
спочатку потрібно агрегувати всі його замовлення, а лише потім
порівнювати сегменти.

Алгоритм:
1. CTE customer_discount_stats створює один рядок на клієнта.
2. AVG(discount_pct) визначає середню отриману знижку.
3. CASE ділить клієнтів на High Discount і Standard Discount.
4. Зовнішній SELECT порівнює розмір сегмента, частоту покупок,
   середні витрати, виручку та AOV.

Tableau:
Discount Customer Behaviour, Question 8, creative worksheet 2.6.
*/

WITH customer_discount_stats AS (
    -- Крок 1: показники кожного клієнта
    SELECT
        customer_id,
        AVG(discount_pct) AS average_discount_pct,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(net_amount) AS total_spend

    FROM shopsphere_orders

    GROUP BY
        customer_id
)

SELECT
    -- Крок 2: сегментація за середньою знижкою клієнта
    CASE
        WHEN average_discount_pct > 20
            THEN 'High Discount (>20%)'
        ELSE 'Standard Discount (<=20%)'
    END AS discount_segment,

    COUNT(*) AS total_customers,

    ROUND(AVG(average_discount_pct), 2)
        AS average_discount_pct,

    ROUND(AVG(total_orders), 2)
        AS average_orders_per_customer,

    ROUND(AVG(total_spend), 2)
        AS average_customer_spend,

    ROUND(SUM(total_spend), 2)
        AS total_revenue,

    -- Середній чек сегмента = revenue / orders
    ROUND(
        SUM(total_spend) / SUM(total_orders),
        2
    ) AS average_order_value

FROM customer_discount_stats

GROUP BY
    discount_segment

ORDER BY
    average_discount_pct;


/*
====================================================================
A5. OVERALL A/B TEST RESULTS
====================================================================

Мета:
Порівняти загальні результати checkout variants A та B.

Фільтр експерименту:
- початок: 2024-06-01;
- використовуємо тільки ab_variant A або B;
- попередні NULL-значення не входять до аналізу.

Рівень деталізації:
один рядок = один A/B variant.

Алгоритм:
1. WHERE залишає тільки період експерименту та групи A/B.
2. GROUP BY ab_variant створює дві групи.
3. Рахуємо orders, customers, revenue та AOV.

Tableau/report:
Question 10 — загальне порівняння A і B.
*/

SELECT
    ab_variant,

    COUNT(DISTINCT order_id) AS total_orders,

    COUNT(DISTINCT customer_id) AS total_customers,

    ROUND(SUM(net_amount), 2) AS total_net_revenue,

    ROUND(AVG(net_amount), 2) AS average_order_value

FROM shopsphere_orders

WHERE order_date >= '2024-06-01'
  AND ab_variant IN ('A', 'B')

GROUP BY
    ab_variant

ORDER BY
    ab_variant;


/*
====================================================================
A6. A/B RESULTS BY NEW AND REPEAT CUSTOMER SEGMENTS
====================================================================

Мета:
Перевірити, чи однаково працює variant B для New і Repeat customers.

Правило сегментації:
- New: замовлення відбулося через 0–60 днів після signup_date;
- Repeat: замовлення відбулося пізніше ніж через 60 днів.

Як працює julianday:
julianday(date) перетворює дату на числове значення. Різниця між
julianday(order_date) і julianday(signup_date) дає кількість днів.

Алгоритм:
1. JOIN додає signup_date клієнта до замовлення.
2. CASE створює customer_type New або Repeat.
3. WHERE залишає тільки період експерименту та A/B.
4. GROUP BY variant і customer_type створює чотири підгрупи.
5. Для кожної підгрупи рахуємо orders, customers, revenue та AOV.

Tableau/report:
Questions 11–13. Загальний результат A5 потрібно показувати разом
із сегментованим результатом A6, щоб не приховувати різницю груп.
*/

SELECT
    o.ab_variant,

    -- Визначаємо тип клієнта за кількістю днів після реєстрації
    CASE
        WHEN julianday(o.order_date) - julianday(c.signup_date)
             BETWEEN 0 AND 60
            THEN 'New'
        ELSE 'Repeat'
    END AS customer_type,

    COUNT(DISTINCT o.order_id) AS total_orders,

    COUNT(DISTINCT o.customer_id) AS total_customers,

    ROUND(SUM(o.net_amount), 2) AS total_net_revenue,

    ROUND(AVG(o.net_amount), 2) AS average_order_value

FROM shopsphere_orders AS o

-- Додаємо дату реєстрації клієнта
JOIN shopsphere_customers AS c
    ON o.customer_id = c.customer_id

WHERE o.order_date >= '2024-06-01'
  AND o.ab_variant IN ('A', 'B')

GROUP BY
    o.ab_variant,
    customer_type

ORDER BY
    customer_type,
    o.ab_variant;

/*
====================================================================
A7. CUSTOMER VALUE BY ACQUISITION CHANNEL
====================================================================

Мета:
Розрахувати цінність клієнтів для кожного каналу залучення
та порівняти результат із Marketing ROI.

Логіка:
average_customer_spend використовується як LTV proxy —
спрощена оцінка цінності клієнта за наявний період даних,
а не як повний прогноз Lifetime Value.

Рівень деталізації:
- у CTE customer_metrics: 1 рядок = 1 клієнт;
- у фінальному результаті: 1 рядок = 1 acquisition channel.

Алгоритм:
1. JOIN додає замовлення до кожного клієнта.
2. У CTE для кожного клієнта рахуємо total spend
   та кількість унікальних замовлень.
3. У фінальному SELECT групуємо клієнтів
   за acquisition_channel.
4. Для кожного каналу рахуємо:
   customers, average customer spend,
   total customer revenue та average orders per customer.

Tableau/report:
Question 4. Результат потрібно порівняти з Marketing ROI,
щоб оцінити канали не лише за ефективністю кампаній,
а й за довгостроковою цінністю залучених клієнтів.
*/

WITH customer_metrics AS (
    SELECT
        c.customer_id,

        -- Перейменовуємо скорочену назву поля
        c.acquisition_chan AS acquisition_channel,

        -- Загальна чиста виручка від одного клієнта
        SUM(o.net_amount) AS customer_spend,

        -- Кількість унікальних замовлень одного клієнта
        COUNT(DISTINCT o.order_id) AS customer_orders

    FROM shopsphere_customers AS c

    -- Додаємо замовлення клієнтів
    JOIN shopsphere_orders AS o
        ON c.customer_id = o.customer_id

    -- Агрегуємо дані до рівня одного клієнта
    GROUP BY
        c.customer_id,
        c.acquisition_chan
)

SELECT
    acquisition_channel,

    -- Кількість активних клієнтів каналу
    COUNT(*) AS total_customers,

    -- Середня сума витрат одного клієнта
    ROUND(AVG(customer_spend), 2) AS average_customer_spend,

    -- Загальна чиста виручка клієнтів каналу
    ROUND(SUM(customer_spend), 2) AS total_customer_revenue,

    -- Середня кількість замовлень на одного клієнта
    ROUND(AVG(customer_orders), 2) AS average_orders_per_customer

FROM customer_metrics

GROUP BY acquisition_channel

ORDER BY average_customer_spend DESC;
    acquisition_channel,

    -- Кількість активних клієнтів каналу
    COUNT(*) AS total_customers,

    -- Середня загальна сума витрат одного клієнта
    -- Використовується як LTV proxy
    ROUND(AVG(customer_spend), 2) AS average_customer_spend,

    -- Загальна чиста виручка від клієнтів каналу
    ROUND(SUM(customer_spend), 2) AS total_customer_revenue,

    -- Середня кількість замовлень одного клієнта
    ROUND(AVG(customer_orders), 2) AS average_orders_per_customer

FROM customer_metrics

-- Фінальне групування за каналом залучення
GROUP BY acquisition_channel

-- Канали з найбільшою середньою цінністю клієнта зверху
ORDER BY average_customer_spend DESC;

/*
====================================================================
A8. INTERACTIVE CATEGORY DATASET FOR TABLEAU
====================================================================

Мета:
Підготувати деталізоване джерело для Category Performance,
щоб у Tableau працювали фільтри за роком, місяцем, регіоном,
каналом і пристроєм.

Рівень деталізації:
один рядок = одна товарна позиція замовлення.
*/

SELECT
    oi.item_id,
    oi.order_id,
    o.customer_id,
    o.order_date,
    o.order_year,
    o.order_month,

    c.region,

    o.device,
    o.channel AS sales_channel,

    p.category,
    oi.line_total,
    p.margin_pct,
    o.is_returned

FROM shopsphere_order_items AS oi

JOIN shopsphere_products AS p
    ON oi.product_id = p.product_id

JOIN shopsphere_orders AS o
    ON oi.order_id = o.order_id

JOIN shopsphere_customers AS c
    ON o.customer_id = c.customer_id

ORDER BY
    o.order_date,
    oi.item_id;
