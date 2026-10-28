
-- Запросы для анализа и проверки 

-- Q1. Свободные слоты фотографа на дату 
-- Свободное время не хранится: это рабочие интервалы минус активные записи.
-- Параметры: фотограф 2, услуга 1 (60 минут), дата 2026-11-03, шаг 30 минут.
-- Ожидаемо для тестовых данных: 14 слотов; занят промежуток 14:00–15:00,
-- поэтому слоты с началом 13:30, 14:00 и 14:30 в списке отсутствуют.

WITH params AS (
    SELECT 2 AS photographer_id, 1 AS service_id,
           DATE '2026-11-03' AS day, INTERVAL '30 minutes' AS step
),
day_bounds AS (
    SELECT p.*, (p.day::timestamp AT TIME ZONE 'Europe/Moscow') AS day_start
    FROM params p
),
svc AS (
    SELECT s.service_id, make_interval(mins => s.duration_min) AS dur
    FROM services s
    JOIN params p ON p.service_id = s.service_id
    WHERE s.is_published AND NOT s.is_archived
),
candidates AS (
    SELECT d.photographer_id, g AS start_at, g + svc.dur AS end_at
    FROM day_bounds d
    JOIN photographers ph          ON ph.photographer_id = d.photographer_id AND ph.is_active
    JOIN photographer_services ps  ON ps.photographer_id = d.photographer_id
                                  AND ps.service_id = d.service_id
    JOIN work_intervals wi         ON wi.photographer_id = d.photographer_id
                                  AND wi.start_at >= d.day_start
                                  AND wi.start_at <  d.day_start + INTERVAL '1 day'
    CROSS JOIN svc
    CROSS JOIN LATERAL generate_series(wi.start_at, wi.end_at - svc.dur, d.step) AS g
)
SELECT c.start_at, c.end_at
FROM candidates c
WHERE c.start_at >= now() + INTERVAL '2 hours'                  
  AND NOT EXISTS (                                                
        SELECT 1
        FROM bookings b
        WHERE b.photographer_id = c.photographer_id
          AND b.status <> 'cancelled'
          AND tstzrange(b.start_at, b.end_at, '[)') && tstzrange(c.start_at, c.end_at, '[)')
  )
ORDER BY c.start_at;


-- Q2. Отчёт владельца: записи по месяцам и доля канала «сайт»

SELECT date_trunc('month', created_at AT TIME ZONE 'Europe/Moscow')::date AS month,
       count(*)                                                           AS total_bookings,
       count(*) FILTER (WHERE channel = 'site')                           AS via_site,
       round(100.0 * count(*) FILTER (WHERE channel = 'site') / count(*), 1) AS site_share_pct
FROM bookings
GROUP BY 1
ORDER BY 1;



-- Q3. Записи по каналам и статусам

SELECT channel, status, count(*) AS bookings
FROM bookings
GROUP BY channel, status
ORDER BY channel, status;



-- Q4. Недоставленные уведомления: кому звонит администратор 

SELECT b.booking_id, c.name, c.phone, b.start_at, n.type, n.sent_at
FROM notifications n
JOIN bookings b ON b.booking_id = n.booking_id
JOIN clients  c ON c.client_id  = b.client_id
WHERE n.delivery_status = 'failed'
  AND b.status = 'confirmed'
ORDER BY b.start_at;


-- Q5. Записи, ожидающие решения администратора дольше 4 часов.
-- Для них должна уйти эскалация владельцу; запись не отменяется.

SELECT booking_id, photographer_id, start_at, created_at,
       now() - created_at AS waiting
FROM bookings
WHERE status = 'pending_review'
  AND created_at < now() - INTERVAL '4 hours'
ORDER BY created_at;


-- Q6. Предложения студии, на которые клиент не ответил в срок (схема Б)
-- По ним запись отменяется автоматически, время освобождается.

SELECT booking_id, client_id, response_deadline
FROM bookings
WHERE status = 'awaiting_client'
  AND response_deadline < now();


-- Q7. Клиенты с несколькими записями.

SELECT c.client_id, c.name, count(*) AS bookings
FROM clients c
JOIN bookings b ON b.client_id = c.client_id
GROUP BY c.client_id, c.name
HAVING count(*) > 1
ORDER BY bookings DESC, c.client_id;


-- Q8. Фотографы без записей на дату.

SELECT p.photographer_id, p.name
FROM photographers p
LEFT JOIN bookings b
       ON b.photographer_id = p.photographer_id
      AND b.status <> 'cancelled'
      AND b.start_at >= TIMESTAMPTZ '2026-11-02 00:00+03'
      AND b.start_at <  TIMESTAMPTZ '2026-11-03 00:00+03'
WHERE b.booking_id IS NULL
ORDER BY p.photographer_id;


-- Q9. Загрузка фотографов: часы подтверждённых и выполненных съёмок.

SELECT p.name,
       count(*) AS bookings,
       round(sum(EXTRACT(EPOCH FROM (b.end_at - b.start_at))) / 3600, 1) AS hours
FROM bookings b
JOIN photographers p ON p.photographer_id = b.photographer_id
WHERE b.status IN ('confirmed', 'completed')
GROUP BY p.name
ORDER BY hours DESC;


-- Q10. Условие запуска: у каждого фотографа не менее 5 опубликованных работ.

SELECT p.photographer_id, p.name,
       count(w.work_id) FILTER (WHERE w.is_published)       AS published_works,
       count(w.work_id) FILTER (WHERE w.is_published) >= 5 AS ready_for_launch
FROM photographers p
LEFT JOIN portfolio_works w ON w.photographer_id = p.photographer_id
GROUP BY p.photographer_id, p.name
ORDER BY p.photographer_id;



-- Q11. Обезличивание клиента по запросу.
-- Клиента не удаляем: записи остаются, и отчёты БЦ-1 и БЦ-2 не ломаются.
-- Транзакция откатывается, чтобы тестовые данные не менялись.

BEGIN;

UPDATE clients
SET name = NULL, phone = NULL, email = NULL, anonymized_at = now()
WHERE client_id = 5;

SELECT c.client_id, c.name, c.phone, c.anonymized_at, count(b.booking_id) AS bookings_kept
FROM clients c
LEFT JOIN bookings b ON b.client_id = c.client_id
WHERE c.client_id = 5
GROUP BY c.client_id;

ROLLBACK;
