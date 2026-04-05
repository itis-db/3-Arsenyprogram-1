CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;


CREATE TABLE publishers (
    publisher_id BIGSERIAL PRIMARY KEY,
    name          VARCHAR(200) NOT NULL UNIQUE,
    city          VARCHAR(100) NOT NULL
);

CREATE TABLE authors (
    author_id      BIGSERIAL PRIMARY KEY,
    last_name      VARCHAR(100) NOT NULL,
    first_name     VARCHAR(100) NOT NULL,
    middle_name    VARCHAR(100),
    birth_date     DATE,
    country        VARCHAR(100),
    CONSTRAINT uq_author UNIQUE (last_name, first_name, middle_name, birth_date)
);

CREATE TABLE categories (
    category_id BIGSERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE books (
    book_id             BIGSERIAL PRIMARY KEY,
    title               VARCHAR(300) NOT NULL,
    isbn                VARCHAR(20) UNIQUE,
    publisher_id        BIGINT NOT NULL REFERENCES publishers(publisher_id),
    publication_year    INT NOT NULL CHECK (publication_year BETWEEN 1900 AND 2100),
    price               NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    stock_qty           INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    description         TEXT NOT NULL,
    search_vector       tsvector
);

CREATE TABLE book_authors (
    book_id   BIGINT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    author_id BIGINT NOT NULL REFERENCES authors(author_id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, author_id)
);

CREATE TABLE book_categories (
    book_id      BIGINT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    category_id  BIGINT NOT NULL REFERENCES categories(category_id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, category_id)
);

CREATE TABLE customers (
    customer_id   BIGSERIAL PRIMARY KEY,
    last_name     VARCHAR(100) NOT NULL,
    first_name    VARCHAR(100) NOT NULL,
    email         VARCHAR(200) NOT NULL UNIQUE,
    phone         VARCHAR(30),
    registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    order_id        BIGSERIAL PRIMARY KEY,
    customer_id     BIGINT NOT NULL REFERENCES customers(customer_id),
    order_date      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status          VARCHAR(30) NOT NULL CHECK (status IN ('new', 'paid', 'shipped', 'completed', 'cancelled')),
    total_amount    NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0)
);

CREATE TABLE order_items (
    order_item_id   BIGSERIAL PRIMARY KEY,
    order_id        BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    book_id         BIGINT NOT NULL REFERENCES books(book_id),
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    CONSTRAINT uq_order_book UNIQUE (order_id, book_id)
);


--Автоматическое обновление полнотекстового индекса
CREATE OR REPLACE FUNCTION books_search_vector_update()
RETURNS trigger AS
$$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('russian', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('russian', coalesce(NEW.description, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_books_search_vector
BEFORE INSERT OR UPDATE OF title, description
ON books
FOR EACH ROW
EXECUTE FUNCTION books_search_vector_update();

-- Тут индексы для внешних ключей
CREATE INDEX idx_books_publisher_id         ON books(publisher_id);
CREATE INDEX idx_book_authors_author_id     ON book_authors(author_id);
CREATE INDEX idx_book_categories_category_id ON book_categories(category_id);
CREATE INDEX idx_orders_customer_id         ON orders(customer_id);
CREATE INDEX idx_order_items_order_id       ON order_items(order_id);
CREATE INDEX idx_order_items_book_id        ON order_items(book_id);

-- Тут индексы для WHERE / JOIN / ORDER BY

CREATE INDEX idx_books_publication_year ON books(publication_year);
CREATE INDEX idx_books_price            ON books(price);
CREATE INDEX idx_orders_order_date      ON orders(order_date);
CREATE INDEX idx_orders_status          ON orders(status);
CREATE INDEX idx_customers_email        ON customers(email);

-- Полнотекстовый индекс
CREATE INDEX idx_books_search_vector
ON books
USING GIN(search_vector);

-- Триграммные индексы
CREATE INDEX idx_books_title_trgm
ON books
USING GIN (title gin_trgm_ops);

CREATE INDEX idx_books_description_trgm
ON books
USING GIN (description gin_trgm_ops);

INSERT INTO publishers (name, city) VALUES
('Эксмо', 'Москва'),
('АСТ', 'Москва'),
('Питер', 'Санкт-Петербург'),
('МИФ', 'Москва'),
('БХВ-Петербург', 'Санкт-Петербург');

INSERT INTO authors (last_name, first_name, middle_name, birth_date, country) VALUES
('Достоевский', 'Фёдор', 'Михайлович', '1821-11-11', 'Россия'),
('Толстой', 'Лев', 'Николаевич', '1828-09-09', 'Россия'),
('Пелевин', 'Виктор', 'Олегович', '1962-11-22', 'Россия'),
('Глуховский', 'Дмитрий', 'Алексеевич', '1979-06-12', 'Россия'),
('Булгаков', 'Михаил', 'Афанасьевич', '1891-05-15', 'Россия'),
('Тургенев', 'Иван', 'Сергеевич', '1818-11-09', 'Россия'),
('Кинг', 'Стивен', NULL, '1947-09-21', 'США'),
('Роулинг', 'Джоан', NULL, '1965-07-31', 'Великобритания');

INSERT INTO categories (name) VALUES
('Классическая литература'),
('Фантастика'),
('Постапокалипсис'),
('Психология'),
('Ужасы'),
('Фэнтези'),
('Современная проза');

INSERT INTO books (title, isbn, publisher_id, publication_year, price, stock_qty, description) VALUES
(
 'Преступление и наказание',
 '9785170906306',
 1,
 2022,
 650.00,
 12,
 'Роман о внутренней борьбе студента Родиона Раскольникова, преступлении, вине и нравственном возрождении.'
),
(
 'Идиот',
 '9785171203213',
 2,
 2021,
 590.00,
 8,
 'История князя Мышкина, человека необыкновенной доброты, попадающего в жестокий и противоречивый мир общества.'
),
(
 'Война и мир',
 '9785170831158',
 1,
 2020,
 990.00,
 5,
 'Эпический роман о судьбах семей на фоне Отечественной войны 1812 года, любви, чести и исторических перемен.'
),
(
 'Анна Каренина',
 '9785171183669',
 2,
 2019,
 720.00,
 7,
 'Роман о любви, семейной жизни, нравственном выборе и трагедии личности в русском обществе XIX века.'
),
(
 'Generation П',
 '9785699987654',
 3,
 2023,
 540.00,
 15,
 'Сатирический роман о рекламе, телевидении, мифах массовой культуры и поиске смысла в постсоветской реальности.'
),
(
 'Чапаев и Пустота',
 '9785699999999',
 3,
 2022,
 560.00,
 11,
 'Философский роман о сознании, пустоте, иллюзии реальности и духовном поиске.'
),
(
 'Метро 2033',
 '9785170498153',
 2,
 2024,
 680.00,
 20,
 'Постапокалиптический роман о выживании людей в московском метро после ядерной катастрофы.'
),
(
 'Метро 2034',
 '9785170500000',
 2,
 2024,
 690.00,
 10,
 'Продолжение истории о жизни в туннелях метро, страхе, надежде и борьбе за будущее.'
),
(
 'Мастер и Маргарита',
 '9785171560001',
 1,
 2023,
 710.00,
 9,
 'Мистический роман о добре и зле, любви, свободе и сатирическом изображении московской жизни.'
),
(
 'Отцы и дети',
 '9785170999889',
 1,
 2021,
 430.00,
 14,
 'Роман о конфликте поколений, нигилизме, любви и переменах в русском обществе.'
),
(
 'Сияние',
 '9785389201234',
 4,
 2022,
 760.00,
 6,
 'Психологический роман ужасов о семье, оказавшейся в изолированном отеле с мрачной историей.'
),
(
 'Гарри Поттер и философский камень',
 '9785389074357',
 2,
 2020,
 850.00,
 13,
 'Фэнтези-роман о мальчике-волшебнике, школе магии, дружбе и противостоянии злу.'
);

INSERT INTO book_authors (book_id, author_id) VALUES
(1, 1),
(2, 1),
(3, 2),
(4, 2),
(5, 3),
(6, 3),
(7, 4),
(8, 4),
(9, 5),
(10, 6),
(11, 7),
(12, 8);

INSERT INTO book_categories (book_id, category_id) VALUES
(1, 1),
(2, 1),
(3, 1),
(4, 1),
(5, 7),
(6, 7),
(7, 2),
(7, 3),
(8, 2),
(8, 3),
(9, 1),
(10, 1),
(11, 5),
(12, 6);

INSERT INTO customers (last_name, first_name, email, phone) VALUES
('Иванов', 'Сергей', 'ivanov@mail.ru', '+79990000001'),
('Петрова', 'Анна', 'petrova@mail.ru', '+79990000002'),
('Смирнов', 'Олег', 'smirnov@mail.ru', '+79990000003');

INSERT INTO orders (customer_id, order_date, status, total_amount) VALUES
(1, '2026-03-15 10:30:00', 'completed', 1240.00),
(2, '2026-03-20 14:10:00', 'paid', 680.00),
(3, '2026-03-25 18:00:00', 'shipped', 1550.00);

INSERT INTO order_items (order_id, book_id, quantity, unit_price) VALUES
(1, 1, 1, 650.00),
(1, 10, 1, 430.00),
(2, 7, 1, 680.00),
(3, 9, 1, 710.00),
(3, 12, 1, 850.00);

UPDATE books
SET title = title;

-- Полнотекстовый поиск

--Полнотекстовый поиск с учетом морфологии
SELECT
    b.book_id,
    b.title,
    ts_rank_cd(
            b.search_vector,
            to_tsquery('russian', 'любовь | трагедия')
    ) AS relevance
FROM books b
WHERE b.search_vector @@ to_tsquery('russian', 'любовь | трагедия')
ORDER BY relevance DESC;


SELECT
    b.book_id,
    b.title,
    ts_rank_cd(
        b.search_vector,
        websearch_to_tsquery('russian', 'метро катастрофа')
    ) AS relevance
FROM books b
WHERE b.search_vector @@ websearch_to_tsquery('russian', 'метро катастрофа')
ORDER BY relevance DESC;


SELECT
    book_id,
    title,
    similarity(title, 'Метро') AS sim
FROM books
WHERE title ILIKE '%Метро%'
   OR title % 'Метро'
ORDER BY sim DESC, title;

-- Комбинированный поиск: полнотекстовый + триграммы
SELECT
    b.book_id,
    b.title,
    ts_rank_cd(
        b.search_vector,
        websearch_to_tsquery('russian', 'московском метро катастрофа')
    ) AS fts_rank,
    similarity(b.title, 'метро') AS title_sim,
    similarity(b.description, 'катастрофа') AS desc_sim,
    (
        ts_rank_cd(
            b.search_vector,
            websearch_to_tsquery('russian', 'московском метро катастрофа')
        ) * 0.7
        + greatest(similarity(b.title, 'метро'), similarity(b.description, 'катастрофа')) * 0.3
    ) AS total_rank
FROM books b
WHERE
    b.search_vector @@ websearch_to_tsquery('russian', 'московском метро катастрофа')
    OR b.title % 'метро'
    OR b.description % 'катастрофа'
ORDER BY total_rank DESC, b.title;

-- EXPLAIN ANALYZE для полнотекстового поиска
EXPLAIN ANALYZE
SELECT
    b.book_id,
    b.title,
    ts_rank_cd(
            b.search_vector,
            websearch_to_tsquery('russian', 'любовь трагедия')
    ) AS relevance
FROM books b
WHERE b.search_vector @@ websearch_to_tsquery('russian', 'любовь трагедия')
ORDER BY relevance DESC, b.title;

-- EXPLAIN ANALYZE для триграммного поиска
EXPLAIN ANALYZE
SELECT
    book_id,
    title,
    similarity(title, 'метр') AS sim
FROM books
WHERE title % 'метр'
ORDER BY sim DESC, title;

-- EXPLAIN ANALYZE для комбинированного поиска
EXPLAIN ANALYZE
SELECT
    b.book_id,
    b.title,
    ts_rank_cd(
        b.search_vector,
        websearch_to_tsquery('russian', 'московском метро катастрофа')
    ) AS fts_rank,
    similarity(b.title, 'метро') AS title_sim,
    similarity(b.description, 'катастрофа') AS desc_sim
FROM books b
WHERE
    b.search_vector @@ websearch_to_tsquery('russian', 'московском метро катастрофа')
    OR b.title % 'метро'
    OR b.description % 'катастрофа'
ORDER BY fts_rank DESC, title_sim DESC;

