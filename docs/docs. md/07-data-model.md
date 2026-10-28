# 7. Модель данных

Модель содержит 12 сущностей в третьей нормальной форме. Главная сущность «Запись» связывает клиента, фотографа и услугу. Свободное время в базе не хранится: оно вычисляется из графика работы и записей (FR-12). Реализация в PostgreSQL: [database/01_schema.sql](../database/01_schema.sql).

На схеме показаны ключевые поля, полный состав атрибутов ниже.

![ER-диаграмма](../diagrams/er-diagram.png)

## 7.1 Атрибуты сущностей

| Сущность | Таблица | Атрибуты (тип, ограничения) | Откуда |
| --- | --- | --- | --- |
| Клиент | `clients` | client_id INTEGER PK; name VARCHAR(50); phone VARCHAR(12) UNIQUE, формат +7XXXXXXXXXX; email VARCHAR(254); created_at TIMESTAMP; anonymized_at TIMESTAMP, пусто у необезличенных. После обезличивания name, phone, email стираются | FR-1–FR-4, НФ-11 |
| Согласие | `consents` | consent_id INTEGER PK; client_id INTEGER FK → Клиент; given_at TIMESTAMP; text_version VARCHAR(20) | НФ-11 |
| Услуга | `services` | service_id INTEGER PK; name VARCHAR(100); description TEXT, необязательно; duration_min INTEGER; price DECIMAL(10,2); is_published BOOLEAN; is_archived BOOLEAN | ВИ-1, FR-6 |
| Фотограф | `photographers` | photographer_id INTEGER PK; name VARCHAR(100); bio TEXT, необязательно; photo_url VARCHAR(500), необязательно; is_active BOOLEAN | ВИ-2 |
| Фотограф—Услуга | `photographer_services` | photographer_id INTEGER PK, FK → Фотограф; service_id INTEGER PK, FK → Услуга (составной ключ, связь M:M) | UC-4, шаг 3 |
| Интервал работы | `work_intervals` | interval_id INTEGER PK; photographer_id INTEGER FK → Фотограф; start_at TIMESTAMP; end_at TIMESTAMP, end_at > start_at, интервалы одного фотографа не пересекаются | ВИ-12, FR-12 |
| Работа портфолио | `portfolio_works` | work_id INTEGER PK; photographer_id INTEGER FK → Фотограф; image_url VARCHAR(500); title VARCHAR(100), необязательно; sort_order INTEGER; is_published BOOLEAN | ВИ-2, ВИ-14, НФ-3 |
| Запись | `bookings` | booking_id INTEGER PK; client_id, photographer_id, service_id INTEGER FK; start_at, end_at TIMESTAMP; channel ENUM (сайт, телефон, визит); status ENUM (5 статусов); wishes TEXT, необязательно; response_deadline TIMESTAMP, необязательно; created_at TIMESTAMP; created_by_id INTEGER FK → Сотрудник, только для записей по телефону и визиту; cancel_token_hash VARCHAR(64); idempotency_key VARCHAR(36) UNIQUE, для записей с сайта | UC-4, БЦ-1, FR-15 |
| Сотрудник | `employees` | employee_id INTEGER PK; name VARCHAR(100); email VARCHAR(254) UNIQUE; password_hash VARCHAR(255); role ENUM (администратор, владелец); is_active BOOLEAN; failed_attempts INTEGER; locked_until TIMESTAMP, необязательно | НФ-9, НФ-10 |
| Уведомление | `notifications` | notification_id INTEGER PK; booking_id INTEGER FK → Запись; type ENUM (подтверждение, предложение, напоминание, отмена); channel ENUM (email, SMS); sent_at TIMESTAMP; delivery_status ENUM (отправлено, доставлено, не доставлено) | ВИ-15, схема В |
| История статусов | `status_history` | history_id INTEGER PK; booking_id INTEGER FK → Запись; status ENUM; changed_at TIMESTAMP; changed_by_id INTEGER FK → Сотрудник, пусто, если изменила система или клиент; comment TEXT, необязательно | UC-9 |
| Вопрос FAQ | `faq_items` | faq_id INTEGER PK; question VARCHAR(255); answer TEXT; sort_order INTEGER; is_published BOOLEAN | ВИ-3 |

В SQL значения перечислений записаны латиницей: канал `site`, `phone`, `visit`; статусы `pending_review`, `awaiting_client`, `confirmed`, `completed`, `cancelled`.

## 7.2 Связи и удаление

| Связь | Тип | При удалении |
| --- | --- | --- |
| Клиент — Запись | 1:M | Клиента с записями не удаляем; по запросу обезличиваем, записи остаются, и БЦ-1, БЦ-2 считаются верно |
| Клиент — Согласие | 1:M, идентифицирующая | Согласие не существует без клиента |
| Фотограф — Запись | 1:M | Фотографа не удаляем, ставим is_active = false |
| Услуга — Запись | 1:M | Услугу не удаляем, ставим is_archived = true |
| Фотограф — Интервал работы | 1:M, идентифицирующая | Удаляются вместе с фотографом, если записей нет |
| Фотограф — Работа портфолио | 1:M, идентифицирующая | То же |
| Фотограф — Услуга | M:M через таблицу-связку | Строка связки удаляется |
| Запись — Уведомление | 1:M, идентифицирующая | Не удаляем: журнал |
| Запись — История статусов | 1:M, идентифицирующая | Не удаляем: журнал |
| Сотрудник — Запись | 1:M, необязательная | Сотрудника не удаляем, ставим is_active = false |

## 7.3 Проектные решения и проверка

- Телефон хранится строкой в едином формате и уникален: повторная запись находит клиента, а не создаёт дубль.
- Пожелания лежат в записи, а не в клиенте: они относятся к конкретной съёмке (третья нормальная форма).
- Конец записи `end_at` хранится, а не вычисляется: если длительность услуги изменится, старые записи не сдвинутся.
- Текущий статус хранится в записи (быстрый показ и фильтры) и в истории (кто и когда менял). Это осознанное дублирование, оба значения пишутся в одной транзакции.
- Нормализация: все атрибуты атомарны (1НФ), частичных зависимостей нет (2НФ), транзитивных зависимостей нет (3НФ); многозначная связь фотографов и услуг вынесена в таблицу-связку.
- Запрет двойной записи реализован ограничением базы `bookings_no_overlap`, а не только проверкой в коде (FR-7).
- Если в студии несколько залов, нужна сущность «Зал», а FR-6 надо расширить проверкой занятости зала (открытый вопрос).
