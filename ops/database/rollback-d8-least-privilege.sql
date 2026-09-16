\set ON_ERROR_STOP on

\getenv DB_NAME DB_NAME
\getenv DB_ADMIN_USER DB_ADMIN_USER
\getenv AUTH_DB_USER AUTH_DB_USER
\getenv CATALOG_DB_USER CATALOG_DB_USER
\getenv ORDERS_DB_USER ORDERS_DB_USER


BEGIN;


-- ============================================================
-- 1. Refuse ambiguous relation topology
-- ============================================================

DO $$
BEGIN
    IF to_regclass('public.users') IS NOT NULL
       AND to_regclass('auth.users') IS NOT NULL THEN
        RAISE EXCEPTION
            'Rollback refused: both public.users and auth.users exist';
    END IF;

    IF to_regclass('public.products') IS NOT NULL
       AND to_regclass('catalog.products') IS NOT NULL THEN
        RAISE EXCEPTION
            'Rollback refused: both public.products and catalog.products exist';
    END IF;

    IF to_regclass('public.orders') IS NOT NULL
       AND to_regclass('orders.orders') IS NOT NULL THEN
        RAISE EXCEPTION
            'Rollback refused: both public.orders and orders.orders exist';
    END IF;
END
$$;


-- ============================================================
-- 2. Return existing relations to Stage-6-compatible public schema
--
-- PostgreSQL moves the SERIAL-owned sequence with products.
-- ============================================================

DO $$
BEGIN
    IF to_regclass('public.users') IS NULL
       AND to_regclass('auth.users') IS NOT NULL THEN
        ALTER TABLE auth.users
            SET SCHEMA public;
    END IF;
END
$$;


DO $$
BEGIN
    IF to_regclass('public.products') IS NULL
       AND to_regclass('catalog.products') IS NOT NULL THEN
        ALTER TABLE catalog.products
            SET SCHEMA public;
    END IF;
END
$$;


DO $$
BEGIN
    IF to_regclass('public.orders') IS NULL
       AND to_regclass('orders.orders') IS NOT NULL THEN
        ALTER TABLE orders.orders
            SET SCHEMA public;
    END IF;
END
$$;


-- ============================================================
-- 3. Required post-move topology
-- ============================================================

DO $$
BEGIN
    IF to_regclass('public.users') IS NULL THEN
        RAISE EXCEPTION
            'Rollback refused/incomplete: public.users is absent';
    END IF;

    IF to_regclass('public.products') IS NULL THEN
        RAISE EXCEPTION
            'Rollback refused/incomplete: public.products is absent';
    END IF;

    IF to_regclass('public.orders') IS NULL THEN
        RAISE EXCEPTION
            'Rollback refused/incomplete: public.orders is absent';
    END IF;

    IF to_regclass('public.products_id_seq') IS NULL THEN
        RAISE EXCEPTION
            'Rollback refused/incomplete: public.products_id_seq is absent';
    END IF;
END
$$;


-- ============================================================
-- 4. Remove D8 runtime-role database settings
-- ============================================================

ALTER ROLE :"AUTH_DB_USER"
    IN DATABASE :"DB_NAME"
    RESET search_path;

ALTER ROLE :"CATALOG_DB_USER"
    IN DATABASE :"DB_NAME"
    RESET search_path;

ALTER ROLE :"ORDERS_DB_USER"
    IN DATABASE :"DB_NAME"
    RESET search_path;


-- ============================================================
-- 5. Make D8 runtime identities inert
--
-- Roles are deliberately NOT dropped.
-- Keeping them permits a controlled forward re-application without
-- destructive role recreation while preventing rolled-back runtime use.
-- ============================================================

REVOKE ALL PRIVILEGES
    ON DATABASE :"DB_NAME"
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";


REVOKE ALL
    ON SCHEMA auth
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";

REVOKE ALL
    ON SCHEMA catalog
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";

REVOKE ALL
    ON SCHEMA orders
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";


REVOKE ALL
    ON TABLE public.users
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";

REVOKE ALL
    ON TABLE public.products
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";

REVOKE ALL
    ON TABLE public.orders
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";


REVOKE ALL
    ON SEQUENCE public.products_id_seq
    FROM :"AUTH_DB_USER",
         :"CATALOG_DB_USER",
         :"ORDERS_DB_USER";


-- ============================================================
-- 6. Admin/owner identity remains unchanged
--
-- No ALTER ROLE is issued against DB_ADMIN_USER.
-- No data is deleted.
-- No object is dropped.
-- ============================================================


COMMIT;