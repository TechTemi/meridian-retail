\set ON_ERROR_STOP on

\getenv DB_NAME DB_NAME
\getenv DB_ADMIN_USER DB_ADMIN_USER

\getenv AUTH_DB_USER AUTH_DB_USER
\getenv AUTH_DB_PASSWORD AUTH_DB_PASSWORD

\getenv CATALOG_DB_USER CATALOG_DB_USER
\getenv CATALOG_DB_PASSWORD CATALOG_DB_PASSWORD

\getenv ORDERS_DB_USER ORDERS_DB_USER
\getenv ORDERS_DB_PASSWORD ORDERS_DB_PASSWORD


BEGIN;


-- ============================================================
-- 1. Runtime roles
-- ============================================================

SELECT format(
    'CREATE ROLE %I LOGIN',
    :'AUTH_DB_USER'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = :'AUTH_DB_USER'
)
\gexec

SELECT format(
    'CREATE ROLE %I LOGIN',
    :'CATALOG_DB_USER'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = :'CATALOG_DB_USER'
)
\gexec

SELECT format(
    'CREATE ROLE %I LOGIN',
    :'ORDERS_DB_USER'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = :'ORDERS_DB_USER'
)
\gexec


ALTER ROLE :"AUTH_DB_USER"
    LOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    PASSWORD :'AUTH_DB_PASSWORD';

ALTER ROLE :"CATALOG_DB_USER"
    LOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    PASSWORD :'CATALOG_DB_PASSWORD';

ALTER ROLE :"ORDERS_DB_USER"
    LOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    PASSWORD :'ORDERS_DB_PASSWORD';


-- ============================================================
-- 2. Dedicated service schemas
-- ============================================================

CREATE SCHEMA IF NOT EXISTS auth
    AUTHORIZATION :"DB_ADMIN_USER";

CREATE SCHEMA IF NOT EXISTS catalog
    AUTHORIZATION :"DB_ADMIN_USER";

CREATE SCHEMA IF NOT EXISTS orders
    AUTHORIZATION :"DB_ADMIN_USER";


REVOKE ALL ON SCHEMA auth FROM PUBLIC;
REVOKE ALL ON SCHEMA catalog FROM PUBLIC;
REVOKE ALL ON SCHEMA orders FROM PUBLIC;


-- ============================================================
-- 3. Move existing production tables without copying data
-- ============================================================

DO $$
BEGIN
    IF to_regclass('auth.users') IS NOT NULL
       AND to_regclass('public.users') IS NOT NULL THEN
        RAISE EXCEPTION
            'Both auth.users and public.users exist; refusing ambiguous migration';
    END IF;

    IF to_regclass('auth.users') IS NULL
       AND to_regclass('public.users') IS NOT NULL THEN
        ALTER TABLE public.users SET SCHEMA auth;
    END IF;
END
$$;


DO $$
BEGIN
    IF to_regclass('catalog.products') IS NOT NULL
       AND to_regclass('public.products') IS NOT NULL THEN
        RAISE EXCEPTION
            'Both catalog.products and public.products exist; refusing ambiguous migration';
    END IF;

    IF to_regclass('catalog.products') IS NULL
       AND to_regclass('public.products') IS NOT NULL THEN
        ALTER TABLE public.products SET SCHEMA catalog;
    END IF;
END
$$;


DO $$
BEGIN
    IF to_regclass('orders.orders') IS NOT NULL
       AND to_regclass('public.orders') IS NOT NULL THEN
        RAISE EXCEPTION
            'Both orders.orders and public.orders exist; refusing ambiguous migration';
    END IF;

    IF to_regclass('orders.orders') IS NULL
       AND to_regclass('public.orders') IS NOT NULL THEN
        ALTER TABLE public.orders SET SCHEMA orders;
    END IF;
END
$$;


-- ============================================================
-- 4. Fresh-database compatibility
--
-- Exact definitions mirror the immutable pre-built services.
-- Existing production relations are preserved by IF NOT EXISTS.
-- ============================================================

CREATE TABLE IF NOT EXISTS auth.users (
    id UUID PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS catalog.products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    category TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);


CREATE TABLE IF NOT EXISTS orders.orders (
    id UUID PRIMARY KEY,
    user_id TEXT NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    total_price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);


-- Match the immutable catalog service's seed-on-empty behavior.
INSERT INTO catalog.products (
    name,
    price,
    category
)
SELECT *
FROM (
    VALUES
        ('Adire Wrap Dress', 45.0::numeric, 'Womenswear'),
        ('Aso-Oke Woven Tote', 32.5::numeric, 'Accessories'),
        ('Kente Trim Blazer', 89.0::numeric, 'Menswear'),
        ('Beaded Coral Necklace', 21.0::numeric, 'Jewellery'),
        ('Ankara Print Sneakers', 58.0::numeric, 'Footwear')
) AS seed(name, price, category)
WHERE NOT EXISTS (
    SELECT 1
    FROM catalog.products
);


-- ============================================================
-- 5. Database/schema boundaries
-- ============================================================

REVOKE ALL
    ON DATABASE :"DB_NAME"
    FROM PUBLIC;

GRANT CONNECT
    ON DATABASE :"DB_NAME"
    TO :"AUTH_DB_USER",
       :"CATALOG_DB_USER",
       :"ORDERS_DB_USER";


GRANT USAGE, CREATE
    ON SCHEMA auth
    TO :"AUTH_DB_USER";

GRANT USAGE, CREATE
    ON SCHEMA catalog
    TO :"CATALOG_DB_USER";

GRANT USAGE, CREATE
    ON SCHEMA orders
    TO :"ORDERS_DB_USER";


-- ============================================================
-- 6. Exact runtime data privileges
-- ============================================================

REVOKE ALL
    ON TABLE auth.users
    FROM PUBLIC;

REVOKE ALL
    ON TABLE catalog.products
    FROM PUBLIC;

REVOKE ALL
    ON TABLE orders.orders
    FROM PUBLIC;


GRANT SELECT, INSERT
    ON TABLE auth.users
    TO :"AUTH_DB_USER";

GRANT SELECT, INSERT
    ON TABLE catalog.products
    TO :"CATALOG_DB_USER";

GRANT SELECT, INSERT
    ON TABLE orders.orders
    TO :"ORDERS_DB_USER";


REVOKE ALL
    ON SEQUENCE catalog.products_id_seq
    FROM PUBLIC;

GRANT USAGE
    ON SEQUENCE catalog.products_id_seq
    TO :"CATALOG_DB_USER";


-- ============================================================
-- 7. Role-specific name resolution
--
-- The immutable services use unqualified table names.
-- Dedicated search_path values preserve that behavior while
-- isolating each service's CREATE privilege to one namespace.
-- ============================================================

ALTER ROLE :"AUTH_DB_USER"
    IN DATABASE :"DB_NAME"
    SET search_path = auth, pg_catalog;

ALTER ROLE :"CATALOG_DB_USER"
    IN DATABASE :"DB_NAME"
    SET search_path = catalog, pg_catalog;

ALTER ROLE :"ORDERS_DB_USER"
    IN DATABASE :"DB_NAME"
    SET search_path = orders, pg_catalog;


COMMIT;