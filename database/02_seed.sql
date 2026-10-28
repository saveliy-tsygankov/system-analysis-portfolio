-- Тестовые данные 


INSERT INTO services (name, description, duration_min, price, is_published) VALUES
 ('Портретная съёмка',  'Студийный портрет, 1 час',            60, 3500.00, TRUE),
 ('Семейная съёмка',    'Съёмка семьи до 5 человек, 1,5 часа', 90, 5500.00, TRUE),
 ('Съёмка для бренда',  'Предметная и имиджевая съёмка, 2 часа', 120, 8000.00, TRUE);


INSERT INTO photographers (name, bio) VALUES
 ('Анна',  'Портрет и семейная съёмка'),
 ('Игорь', 'Портрет, предметная и имиджевая съёмка');

INSERT INTO photographer_services (photographer_id, service_id) VALUES
 (1, 1), (1, 2), (1, 3),
 (2, 1), (2, 2);


INSERT INTO work_intervals (photographer_id, start_at, end_at)
SELECT p.photographer_id,
       (d::date + TIME '10:00') AT TIME ZONE 'Europe/Moscow',
       (d::date + TIME '19:00') AT TIME ZONE 'Europe/Moscow'
FROM photographers p
CROSS JOIN generate_series(TIMESTAMP '2026-11-02', TIMESTAMP '2026-12-31', INTERVAL '1 day') AS d
WHERE (p.photographer_id = 1 AND EXTRACT(ISODOW FROM d) BETWEEN 1 AND 6)
   OR (p.photographer_id = 2 AND EXTRACT(ISODOW FROM d) BETWEEN 2 AND 6);

INSERT INTO portfolio_works (photographer_id, image_url, title, sort_order, is_published)
SELECT p.photographer_id,
       'https://example.com/portfolio/' || p.photographer_id || '/' || n || '.jpg',
       'Работа ' || n, n, TRUE
FROM photographers p CROSS JOIN generate_series(1, 6) AS n;

INSERT INTO employees (name, email, password_hash, role) VALUES
 ('Мария (администратор)', 'admin@example.com', 'demo-hash-not-a-real-password', 'admin'),
 ('Владелец студии',       'owner@example.com', 'demo-hash-not-a-real-password', 'owner');

INSERT INTO clients (name, phone, email, created_at) VALUES
 ('Пётр',   '+79030000001', 'petr@example.com',   '2026-10-20 12:00+03'),
 ('Елена',  '+79030000002', 'elena@example.com',  '2026-10-20 13:00+03'),
 ('Дмитрий','+79030000003', 'dmitry@example.com', '2026-10-21 09:30+03'),
 ('Ольга',  '+79030000004', 'olga@example.com',   '2026-10-21 10:15+03'),
 ('Сергей', '+79030000005', 'sergey@example.com', '2026-10-21 11:40+03');

INSERT INTO consents (client_id, given_at, text_version) VALUES
 (1, '2026-10-20 12:00+03', '2026-09'),
 (2, '2026-10-20 13:00+03', '2026-09'),
 (3, '2026-10-21 09:30+03', '2026-09'),
 (4, '2026-10-21 10:15+03', '2026-09'),
 (5, '2026-10-21 11:40+03', '2026-09'),
 (1, '2026-10-21 14:00+03', '2026-09');


INSERT INTO bookings
 (client_id, photographer_id, service_id, start_at, end_at, channel, status,
  wishes, response_deadline, created_at, created_by_id, cancel_token_hash, idempotency_key)
VALUES
 (1, 1, 1, '2026-11-03 10:00+03', '2026-11-03 11:00+03', 'site',  'confirmed',
  NULL, NULL, '2026-10-20 12:00+03', NULL, encode(sha256(convert_to('token-1', 'UTF8')), 'hex'), gen_random_uuid()::text),
 (2, 1, 2, '2026-11-03 12:00+03', '2026-11-03 13:30+03', 'phone', 'confirmed',
  NULL, NULL, '2026-10-20 13:05+03', 1,    encode(sha256(convert_to('token-2', 'UTF8')), 'hex'), NULL),
 (3, 2, 1, '2026-11-03 14:00+03', '2026-11-03 15:00+03', 'site',  'confirmed',
  NULL, NULL, '2026-10-21 09:30+03', NULL, encode(sha256(convert_to('token-3', 'UTF8')), 'hex'), gen_random_uuid()::text),
 (4, 1, 3, '2026-11-04 11:00+03', '2026-11-04 13:00+03', 'site',  'pending_review',
  'Нужен белый фон и реквизит для предметной съёмки', NULL, '2026-10-21 10:15+03', NULL,
  encode(sha256(convert_to('token-4', 'UTF8')), 'hex'), gen_random_uuid()::text),
 (1, 2, 2, '2026-11-04 15:00+03', '2026-11-04 16:30+03', 'visit', 'confirmed',
  NULL, NULL, '2026-10-21 14:00+03', 1,    encode(sha256(convert_to('token-5', 'UTF8')), 'hex'), NULL),
 (5, 1, 1, '2026-11-03 15:00+03', '2026-11-03 16:00+03', 'site',  'cancelled',
  NULL, NULL, '2026-10-21 11:40+03', NULL, encode(sha256(convert_to('token-6', 'UTF8')), 'hex'), gen_random_uuid()::text),
 (2, 1, 1, '2026-11-03 15:00+03', '2026-11-03 16:00+03', 'site',  'confirmed',
  NULL, NULL, '2026-10-21 12:00+03', NULL, encode(sha256(convert_to('token-7', 'UTF8')), 'hex'), gen_random_uuid()::text),
 (3, 2, 1, '2026-11-05 10:00+03', '2026-11-05 11:00+03', 'site',  'awaiting_client',
  'Съёмка в тёмной одежде, можно ли позже?', '2026-10-22 12:00+03', '2026-10-21 12:30+03', NULL,
  encode(sha256(convert_to('token-8', 'UTF8')), 'hex'), gen_random_uuid()::text);

INSERT INTO status_history (booking_id, status, changed_at, changed_by_id)
SELECT booking_id, status, created_at, created_by_id FROM bookings WHERE booking_id <> 6;

INSERT INTO status_history (booking_id, status, changed_at, changed_by_id, comment) VALUES
 (6, 'confirmed', '2026-10-21 11:40+03', NULL, NULL),
 (6, 'cancelled', '2026-10-21 11:55+03', NULL, 'Клиент отменил запись по ссылке из письма');

INSERT INTO notifications (booking_id, type, channel, sent_at, delivery_status) VALUES
 (1, 'confirmation', 'email', '2026-10-20 12:00:05+03', 'delivered'),
 (3, 'confirmation', 'email', '2026-10-21 09:30:04+03', 'failed'),
 (6, 'cancellation', 'email', '2026-10-21 11:55:03+03', 'delivered'),
 (8, 'offer',        'email', '2026-10-21 12:30:03+03', 'delivered');

INSERT INTO faq_items (question, answer, sort_order, is_published) VALUES
 ('Как отменить запись?',     'По ссылке из письма или SMS, не позже чем за 24 часа до съёмки.', 1, TRUE),
 ('Как оплатить съёмку?',     'Оплата в студии после съёмки.',                                    2, TRUE),
 ('Через сколько будут фото?', 'Срок зависит от услуги, администратор сообщит при записи.',      3, TRUE);
