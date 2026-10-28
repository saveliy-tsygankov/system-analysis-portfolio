-- Проверка FR-7 и НФ-12: два запроса на один слот не создают две записи.




-- Тест A. Запись, пересекающаяся с существующей (booking 1: Анна, 3 ноября 10:00–11:00).
-- Должна быть отклонена. Блок сам сообщает результат.
DO $$
BEGIN
    INSERT INTO bookings
        (client_id, photographer_id, service_id, start_at, end_at, channel, status,
         cancel_token_hash, idempotency_key)
    VALUES
        (2, 1, 1, '2026-11-03 10:30+03', '2026-11-03 11:30+03', 'site', 'confirmed',
         encode(sha256(convert_to('test-a', 'UTF8')), 'hex'), gen_random_uuid()::text);

    RAISE EXCEPTION 'ТЕСТ A НЕ ПРОЙДЕН: пересекающаяся запись создана';
EXCEPTION
    WHEN exclusion_violation THEN
        RAISE NOTICE 'ТЕСТ A ПРОЙДЕН: пересекающаяся запись отклонена';
END $$;


-- Тест B. Слот отменённой записи свободен.
-- Запись 6 (отменена) и запись 7 занимают одно и то же время у Анны (3 ноября 15:00–16:00).
-- Ожидаемо: две строки, у одной статус cancelled, у другой confirmed.

SELECT booking_id, status, start_at, end_at
FROM bookings
WHERE photographer_id = 1
  AND start_at = '2026-11-03 15:00+03'
ORDER BY booking_id;


-- Тест C. Одновременная запись двумя сессиями (выполнить вручную, в двух окнах DBeaver
-- или двух терминалах psql). Слот: Игорь, 10 ноября, 14:00–15:00.
--
-- Сессия 1:
--   BEGIN;
--   INSERT INTO bookings (client_id, photographer_id, service_id, start_at, end_at,
--                         channel, status, cancel_token_hash, idempotency_key)
--   VALUES (1, 2, 1, '2026-11-10 14:00+03', '2026-11-10 15:00+03', 'site', 'confirmed',
--           encode(sha256(convert_to('c-1', 'UTF8')), 'hex'), gen_random_uuid()::text);
--   -- не завершать транзакцию
--
-- Сессия 2 (пока сессия 1 открыта):
--   BEGIN;
--   INSERT INTO bookings (client_id, photographer_id, service_id, start_at, end_at,
--                         channel, status, cancel_token_hash, idempotency_key)
--   VALUES (2, 2, 1, '2026-11-10 14:00+03', '2026-11-10 15:00+03', 'site', 'confirmed',
--           encode(sha256(convert_to('c-2', 'UTF8')), 'hex'), gen_random_uuid()::text);
--   -- запрос ждёт завершения сессии 1
--
-- Сессия 1:  COMMIT;
--   Сессия 2 получает ошибку: conflicting key value violates exclusion constraint
--   "bookings_no_overlap". Остаётся ровно одна запись на этот слот.
-- Сессия 2:  ROLLBACK;



-- Создание записи одной транзакцией Если слот занят, срабатывает ограничение и откатывается всё.
BEGIN;

WITH client AS (
    INSERT INTO clients (name, phone, email)
    VALUES ('Анна-Мария', '+79030000099', 'anna@example.com')
    ON CONFLICT (phone) DO UPDATE
        SET name = EXCLUDED.name, email = EXCLUDED.email
    RETURNING client_id
),
consent AS (
    INSERT INTO consents (client_id, given_at, text_version)
    SELECT client_id, now(), '2026-09' FROM client
),
booking AS (
    INSERT INTO bookings
        (client_id, photographer_id, service_id, start_at, end_at, channel, status,
         cancel_token_hash, idempotency_key)
    SELECT client.client_id, 2, 1,
           TIMESTAMPTZ '2026-11-12 11:00+03', TIMESTAMPTZ '2026-11-12 12:00+03',
           'site'::booking_channel, 'confirmed'::booking_status,
           encode(sha256(convert_to('demo-token', 'UTF8')), 'hex'),
           gen_random_uuid()::text
    FROM client
    RETURNING booking_id, status, created_by_id
)
INSERT INTO status_history (booking_id, status, changed_at, changed_by_id)
SELECT booking_id, status, now(), created_by_id FROM booking;

SELECT b.booking_id, c.name, b.start_at, b.status
FROM bookings b
JOIN clients c ON c.client_id = b.client_id
WHERE b.start_at = '2026-11-12 11:00+03';

ROLLBACK;
