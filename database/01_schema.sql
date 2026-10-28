CREATE EXTENSION IF NOT EXISTS btree_gist;  

CREATE TYPE booking_channel   AS ENUM ('site', 'phone', 'visit');                    
CREATE TYPE booking_status    AS ENUM ('pending_review', 'awaiting_client',
                                       'confirmed', 'completed', 'cancelled');           
CREATE TYPE employee_role     AS ENUM ('admin', 'owner');                              
CREATE TYPE notification_type AS ENUM ('confirmation', 'offer', 'reminder', 'cancellation');
CREATE TYPE notification_channel AS ENUM ('email', 'sms');
CREATE TYPE delivery_status   AS ENUM ('sent', 'delivered', 'failed');


CREATE TABLE services (
    service_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         VARCHAR(100)  NOT NULL,
    description  TEXT,
    duration_min INTEGER       NOT NULL CHECK (duration_min > 0),     
    price        NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    is_published BOOLEAN       NOT NULL DEFAULT FALSE,                
    is_archived  BOOLEAN       NOT NULL DEFAULT FALSE                  
);

CREATE TABLE photographers (
    photographer_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    bio             TEXT,
    photo_url       VARCHAR(500),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE                 
);

CREATE TABLE photographer_services (
    photographer_id INTEGER NOT NULL REFERENCES photographers (photographer_id),
    service_id      INTEGER NOT NULL REFERENCES services (service_id),
    PRIMARY KEY (photographer_id, service_id)
);

CREATE TABLE work_intervals (
    interval_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    photographer_id INTEGER     NOT NULL REFERENCES photographers (photographer_id) ON DELETE CASCADE,
    start_at        TIMESTAMPTZ NOT NULL,
    end_at          TIMESTAMPTZ NOT NULL,
    CHECK (end_at > start_at),
    CONSTRAINT work_intervals_no_overlap
        EXCLUDE USING gist (photographer_id WITH =, tstzrange(start_at, end_at, '[)') WITH &&)
);

CREATE TABLE portfolio_works (
    work_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    photographer_id INTEGER      NOT NULL REFERENCES photographers (photographer_id) ON DELETE CASCADE,
    image_url       VARCHAR(500) NOT NULL,
    title           VARCHAR(100),
    sort_order      INTEGER      NOT NULL DEFAULT 0,
    is_published    BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE clients (
    client_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(50),
    phone         VARCHAR(12) UNIQUE,                                  
    email         VARCHAR(254),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    anonymized_at TIMESTAMPTZ,                                        
    CONSTRAINT clients_contacts_required CHECK (
        anonymized_at IS NOT NULL
        OR (name IS NOT NULL AND phone IS NOT NULL AND email IS NOT NULL)
    ),
    CONSTRAINT clients_name_format  CHECK (name  IS NULL OR name ~ '^[A-Za-zА-Яа-яЁё '' -]{2,50}$'),    
    CONSTRAINT clients_phone_format CHECK (phone IS NULL OR phone ~ '^\+7[0-9]{10}$'),                 
    CONSTRAINT clients_email_format CHECK (email IS NULL OR
        (char_length(email) <= 254 AND email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'))                          
);

CREATE TABLE consents (                                                
    consent_id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id    INTEGER     NOT NULL REFERENCES clients (client_id),
    given_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    text_version VARCHAR(20) NOT NULL
);

CREATE TABLE employees (
    employee_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100)  NOT NULL,
    email           VARCHAR(254)  NOT NULL UNIQUE,
    password_hash   VARCHAR(255)  NOT NULL,                            
    role            employee_role NOT NULL,                            
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    failed_attempts INTEGER       NOT NULL DEFAULT 0,                  
    locked_until    TIMESTAMPTZ
);

CREATE TABLE bookings (
    booking_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id         INTEGER         NOT NULL REFERENCES clients (client_id),
    photographer_id   INTEGER         NOT NULL REFERENCES photographers (photographer_id),
    service_id        INTEGER         NOT NULL REFERENCES services (service_id),
    start_at          TIMESTAMPTZ     NOT NULL,
    end_at            TIMESTAMPTZ     NOT NULL,                       
    channel           booking_channel NOT NULL,                       
    status            booking_status  NOT NULL,
    wishes            TEXT CHECK (wishes IS NULL OR char_length(wishes) <= 500),
    response_deadline TIMESTAMPTZ,                                     
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),
    created_by_id     INTEGER REFERENCES employees (employee_id),      
    cancel_token_hash VARCHAR(64)     NOT NULL,                        
    idempotency_key   VARCHAR(36) UNIQUE,                              
    CHECK (end_at > start_at),
    CHECK ((channel = 'site') = (created_by_id IS NULL)),
    CHECK (channel <> 'site' OR idempotency_key IS NOT NULL),
    CONSTRAINT bookings_no_overlap
        EXCLUDE USING gist (photographer_id WITH =, tstzrange(start_at, end_at, '[)') WITH &&)
        WHERE (status <> 'cancelled')
);

CREATE INDEX idx_bookings_photographer_start ON bookings (photographer_id, start_at);
CREATE INDEX idx_bookings_client ON bookings (client_id);

CREATE TABLE status_history (
    history_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id    INTEGER        NOT NULL REFERENCES bookings (booking_id),
    status        booking_status NOT NULL,
    changed_at    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    changed_by_id INTEGER REFERENCES employees (employee_id),          
    comment       TEXT
);

CREATE TABLE notifications (
    notification_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id      INTEGER              NOT NULL REFERENCES bookings (booking_id),
    type            notification_type    NOT NULL,
    channel         notification_channel NOT NULL,
    sent_at         TIMESTAMPTZ          NOT NULL DEFAULT now(),
    delivery_status delivery_status      NOT NULL                       
);

CREATE TABLE faq_items (
    faq_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    question     VARCHAR(255) NOT NULL,
    answer       TEXT         NOT NULL,
    sort_order   INTEGER      NOT NULL DEFAULT 0,
    is_published BOOLEAN      NOT NULL DEFAULT FALSE
);
