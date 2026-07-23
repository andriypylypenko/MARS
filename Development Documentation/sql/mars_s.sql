--
-- PostgreSQL database dump
--

\restrict bDDWb3XiGeN28BMkQpPxveU3fAV9pNMarPNhlV5BZlGk0eGVTd3AcxdJSoQQ4Wq

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: audit; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA audit;


ALTER SCHEMA audit OWNER TO postgres;

--
-- Name: global; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA global;


ALTER SCHEMA global OWNER TO postgres;

--
-- Name: btree_gin; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gin WITH SCHEMA public;


--
-- Name: EXTENSION btree_gin; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION btree_gin IS 'support for indexing common datatypes in GIN';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: fn_log_mutation(); Type: FUNCTION; Schema: audit; Owner: postgres
--

CREATE FUNCTION audit.fn_log_mutation() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_row_id          text;
    v_identity_id     bigint;
    v_identity_code   text;
    v_pk_column       text := TG_ARGV[0];
BEGIN
    -- Read session identity
    BEGIN
        v_identity_id   := current_setting('mars.current_identity_id',   true)::bigint;
    EXCEPTION WHEN OTHERS THEN
        v_identity_id   := NULL;
    END;

    BEGIN
        v_identity_code := current_setting('mars.current_identity_code', true);
    EXCEPTION WHEN OTHERS THEN
        v_identity_code := 'UNKNOWN';
    END;

    -- Extract PK value from affected row
    IF TG_OP = 'DELETE' THEN
        v_row_id := (row_to_json(OLD)::jsonb) ->> v_pk_column;
    ELSE
        v_row_id := (row_to_json(NEW)::jsonb) ->> v_pk_column;
    END IF;

    INSERT INTO audit.log
        (table_name, row_id, action, performed_by_id, performed_by_code, performed_at)
    VALUES
        (TG_TABLE_NAME, v_row_id, TG_OP, v_identity_id, v_identity_code, now());

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION audit.fn_log_mutation() OWNER TO postgres;

--
-- Name: fn_generate_primitives(); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_generate_primitives() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_line      RECORD;
    v_alloc     RECORD;
    v_coa       RECORD;
    v_amount    numeric;
    v_coa_id    bigint;
    v_direction varchar(8);
BEGIN
    IF NEW.event_status != 'committed' THEN RETURN NEW; END IF;
    IF NEW.amount IS NULL THEN RETURN NEW; END IF;

    FOR v_line IN
        SELECT rl.*
        FROM global."203_fin_ruleset_lines" rl
        WHERE rl.entity_1_id = NEW.entity_id
          AND rl.event_type  = NEW.event_type
          AND (rl.entity_2_id IS NULL OR rl.entity_2_id = NEW.entity_id)
          AND rl.valid_from <= NEW.valid_time
          AND rl.valid_to   >= NEW.valid_time
    LOOP
        IF NOT v_line.has_allocations THEN
            SELECT normal_balance INTO v_coa
            FROM global."201_fin_coa" WHERE coa_id = v_line.coa_id;

            IF v_coa.normal_balance IS NULL THEN
                RAISE EXCEPTION 'normal_balance is NULL for coa_id=% (account_code=%)',
                    v_line.coa_id, v_line.account_code;
            END IF;

            v_direction := CASE
                WHEN v_line.trf_direction IN ('increase','decrease')
                    THEN v_line.trf_direction
                WHEN v_line.trf_direction = 'debit'
                    THEN CASE WHEN v_coa.normal_balance = 'debit'
                         THEN 'increase' ELSE 'decrease' END
                WHEN v_line.trf_direction = 'credit'
                    THEN CASE WHEN v_coa.normal_balance = 'credit'
                         THEN 'increase' ELSE 'decrease' END
            END;

            INSERT INTO global."302_evt_primitive_transitions"
                (event_id, entity_id, transformation_direction,
                 amount, currency_code, valid_time, assertion_time,
                 coa_id, transition_description, primitive_transition_type,
                 scenario_id)
            VALUES
                (NEW.event_id, NEW.entity_id, v_direction,
                 NEW.amount, NEW.currency_code,
                 NEW.valid_time, now(),
                 v_line.coa_id, v_line.line_description, NEW.event_type,
                 NEW.scenario_id);

        ELSE
            FOR v_alloc IN
                SELECT * FROM global."206_fin_allocation_rules"
                WHERE line_id  = v_line.line_id
                  AND valid_from <= NEW.valid_time
                  AND valid_to   >= NEW.valid_time
            LOOP
                v_amount := NEW.amount * v_alloc.allocation_pct;
                v_coa_id := COALESCE(v_alloc.coa_id, v_line.coa_id);

                SELECT normal_balance INTO v_coa
                FROM global."201_fin_coa" WHERE coa_id = v_coa_id;

                IF v_coa.normal_balance IS NULL THEN
                    RAISE EXCEPTION 'normal_balance is NULL for coa_id=%', v_coa_id;
                END IF;

                v_direction := CASE
                    WHEN v_line.trf_direction IN ('increase','decrease')
                        THEN v_line.trf_direction
                    WHEN v_line.trf_direction = 'debit'
                        THEN CASE WHEN v_coa.normal_balance = 'debit'
                             THEN 'increase' ELSE 'decrease' END
                    WHEN v_line.trf_direction = 'credit'
                        THEN CASE WHEN v_coa.normal_balance = 'credit'
                             THEN 'increase' ELSE 'decrease' END
                END;

                INSERT INTO global."302_evt_primitive_transitions"
                    (event_id, entity_id, transformation_direction,
                     amount, currency_code, valid_time, assertion_time,
                     coa_id, transition_description, primitive_transition_type,
                     scenario_id)
                VALUES
                    (NEW.event_id, NEW.entity_id, v_direction,
                     v_amount, NEW.currency_code,
                     NEW.valid_time, now(),
                     v_coa_id,
                     v_line.line_description || ' [alloc ' || v_alloc.allocation_pct || ']',
                     NEW.event_type,
                     NEW.scenario_id);
            END LOOP;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;


ALTER FUNCTION global.fn_generate_primitives() OWNER TO postgres;

--
-- Name: fn_get_exchange_rate(character, character, date); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_get_exchange_rate(p_base character, p_quote character, p_date date) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rate numeric;
BEGIN

    -- ── Guard: same currency ───────────────────────────────────────
    IF TRIM(p_base) = TRIM(p_quote) THEN
        RETURN 1.0;
    END IF;

    -- ── Guard: null inputs ─────────────────────────────────────────
    IF p_base IS NULL OR p_quote IS NULL OR p_date IS NULL THEN
        RAISE EXCEPTION 'fn_get_exchange_rate: NULL input — base=%, quote=%, date=%',
            p_base, p_quote, p_date;
    END IF;

    -- ── 1. Manual override — highest priority ──────────────────────
    SELECT exchange_rate INTO v_rate
    FROM global."401_ref_exchange_rates"
    WHERE base_currency  = p_base
      AND quote_currency = p_quote
      AND rate_timestamp::date = p_date
      AND rate_code = 'rate_manual'
    ORDER BY rate_timestamp DESC LIMIT 1;
    IF FOUND THEN
        RAISE WARNING 'FX %/% @ % — manual override applied', p_base, p_quote, p_date;
        RETURN v_rate;
    END IF;

    -- ── 2. Exact direct ───────────────────────────────────────────
    SELECT exchange_rate INTO v_rate
    FROM global."401_ref_exchange_rates"
    WHERE base_currency  = p_base
      AND quote_currency = p_quote
      AND rate_timestamp::date = p_date
    ORDER BY rate_timestamp DESC LIMIT 1;
    IF FOUND THEN RETURN v_rate; END IF;

    -- ── 3. Exact inverse ──────────────────────────────────────────
    SELECT ROUND(1.0 / exchange_rate, 10) INTO v_rate
    FROM global."401_ref_exchange_rates"
    WHERE base_currency  = p_quote
      AND quote_currency = p_base
      AND rate_timestamp::date = p_date
      AND exchange_rate  > 0
    ORDER BY rate_timestamp DESC LIMIT 1;
    IF FOUND THEN
        RAISE WARNING 'FX %/% @ % — inverse of %/%',
            p_base, p_quote, p_date, p_quote, p_base;
        RETURN v_rate;
    END IF;

    -- ── 4. Carry-forward direct ───────────────────────────────────
    SELECT exchange_rate INTO v_rate
    FROM global."401_ref_exchange_rates"
    WHERE base_currency  = p_base
      AND quote_currency = p_quote
      AND rate_timestamp::date < p_date
    ORDER BY rate_timestamp DESC LIMIT 1;
    IF FOUND THEN
        RAISE WARNING 'FX %/% @ % — carry-forward (prior date)',
            p_base, p_quote, p_date;
        RETURN v_rate;
    END IF;

    -- ── 5. Carry-forward inverse ──────────────────────────────────
    SELECT ROUND(1.0 / exchange_rate, 10) INTO v_rate
    FROM global."401_ref_exchange_rates"
    WHERE base_currency  = p_quote
      AND quote_currency = p_base
      AND rate_timestamp::date < p_date
      AND exchange_rate  > 0
    ORDER BY rate_timestamp DESC LIMIT 1;
    IF FOUND THEN
        RAISE WARNING 'FX %/% @ % — carry-forward inverse (prior date)',
            p_base, p_quote, p_date;
        RETURN v_rate;
    END IF;

    -- ── 6. Forward-fill direct ────────────────────────────────────
    SELECT exchange_rate INTO v_rate
    FROM global."401_ref_exchange_rates"
    WHERE base_currency  = p_base
      AND quote_currency = p_quote
      AND rate_timestamp::date > p_date
    ORDER BY rate_timestamp ASC LIMIT 1;
    IF FOUND THEN
        RAISE WARNING 'FX %/% @ % — forward-fill (future date)',
            p_base, p_quote, p_date;
        RETURN v_rate;
    END IF;

    -- ── 7. Forward-fill inverse ───────────────────────────────────
    SELECT ROUND(1.0 / exchange_rate, 10) INTO v_rate
    FROM global."401_ref_exchange_rates"
    WHERE base_currency  = p_quote
      AND quote_currency = p_base
      AND rate_timestamp::date > p_date
      AND exchange_rate  > 0
    ORDER BY rate_timestamp ASC LIMIT 1;
    IF FOUND THEN
        RAISE WARNING 'FX %/% @ % — forward-fill inverse (future date)',
            p_base, p_quote, p_date;
        RETURN v_rate;
    END IF;

    -- ── 8. Hard fail ──────────────────────────────────────────────
    RAISE EXCEPTION 'No exchange rate found for %/% near % (direct, inverse, carry-forward, or forward-fill)',
        p_base, p_quote, p_date;

END;
$$;


ALTER FUNCTION global.fn_get_exchange_rate(p_base character, p_quote character, p_date date) OWNER TO postgres;

--
-- Name: fn_is_entity_position(bigint); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_entity_position(p_position_id bigint) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF p_position_id IS NULL THEN RETURN TRUE; END IF;
    RETURN EXISTS (
        SELECT 1 FROM global."502_hr_positions"
        WHERE position_id    = p_position_id
          AND position_class = 'statutory'
    );
END;
$$;


ALTER FUNCTION global.fn_is_entity_position(p_position_id bigint) OWNER TO postgres;

--
-- Name: FUNCTION fn_is_entity_position(p_position_id bigint); Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON FUNCTION global.fn_is_entity_position(p_position_id bigint) IS 'Returns true if the given position_id exists in gd_027_positions with position_class = ''entity_position''. Used in CHECK constraint on gd_026_teammembers.entity_position_id. STABLE — result depends on current registry contents.';


--
-- Name: fn_is_project_position(bigint); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_project_position(p_position_id bigint) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF p_position_id IS NULL THEN RETURN TRUE; END IF;
    RETURN EXISTS (
        SELECT 1 FROM global."502_hr_positions"
        WHERE position_id    = p_position_id
          AND position_class = 'operational'
    );
END;
$$;


ALTER FUNCTION global.fn_is_project_position(p_position_id bigint) OWNER TO postgres;

--
-- Name: FUNCTION fn_is_project_position(p_position_id bigint); Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON FUNCTION global.fn_is_project_position(p_position_id bigint) IS 'Returns true if the given position_id exists in gd_027_positions with position_class = ''project_position''. Used in CHECK constraint on gd_026_teammembers.project_position_id. STABLE — result depends on current registry contents.';


--
-- Name: fn_is_valid_commit_status(character varying); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_valid_commit_status(p_status_code character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM global."407_ref_statuses"
        WHERE status_type = 'commit_status'
          AND status_code = p_status_code
    );
END;
$$;


ALTER FUNCTION global.fn_is_valid_commit_status(p_status_code character varying) OWNER TO postgres;

--
-- Name: FUNCTION fn_is_valid_commit_status(p_status_code character varying); Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON FUNCTION global.fn_is_valid_commit_status(p_status_code character varying) IS 'Returns true if p_status_code exists in gd_007_status_registry for status_type = ''commit_status''. Used in CHECK constraint on gd_006_commit_records.commit_status. Declared STABLE — result depends on current registry contents, not solely on the argument.';


--
-- Name: fn_is_valid_event_status(character varying); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_valid_event_status(p_status_code character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM global."407_ref_statuses"
        WHERE status_type = 'event_status'
          AND status_code = p_status_code
    );
END;
$$;


ALTER FUNCTION global.fn_is_valid_event_status(p_status_code character varying) OWNER TO postgres;

--
-- Name: FUNCTION fn_is_valid_event_status(p_status_code character varying); Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON FUNCTION global.fn_is_valid_event_status(p_status_code character varying) IS 'Returns true if p_status_code exists in gd_007_status_registry for status_type = ''event_status''. Used in CHECK constraint on gd_001_events.event_status. Declared STABLE — result depends on current registry contents, not solely on the argument.';


--
-- Name: fn_is_valid_position_superior(bigint, text, bigint, bigint); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_valid_position_superior(p_superior_id bigint, p_class text, p_project_id bigint, p_entity_id bigint) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF p_superior_id IS NULL THEN RETURN TRUE; END IF;
    RETURN EXISTS (
        SELECT 1 FROM global."502_hr_positions"
        WHERE position_id    = p_superior_id
          AND position_class = p_class
          AND (
              (p_project_id IS NOT NULL AND project_id = p_project_id)
              OR
              (p_entity_id IS NOT NULL AND entity_id = p_entity_id AND project_id IS NULL)
              OR
              (p_project_id IS NULL AND p_entity_id IS NULL
                   AND project_id IS NULL AND entity_id IS NULL)
          )
    );
END;
$$;


ALTER FUNCTION global.fn_is_valid_position_superior(p_superior_id bigint, p_class text, p_project_id bigint, p_entity_id bigint) OWNER TO postgres;

--
-- Name: FUNCTION fn_is_valid_position_superior(p_superior_id bigint, p_class text, p_project_id bigint, p_entity_id bigint); Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON FUNCTION global.fn_is_valid_position_superior(p_superior_id bigint, p_class text, p_project_id bigint, p_entity_id bigint) IS 'Validates that position_superior_id references a position with the same class and same scope context (same project, same entity, or both universal). Prevents cross-project and cross-entity hierarchy contamination. STABLE.';


--
-- Name: fn_is_valid_scenario_status(character varying); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_valid_scenario_status(p_status_code character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF p_status_code IS NULL THEN RETURN TRUE; END IF;
    RETURN EXISTS (
        SELECT 1 FROM global."407_ref_statuses"
        WHERE status_type = 'scenario_status'
          AND status_code  = p_status_code
    );
END;
$$;


ALTER FUNCTION global.fn_is_valid_scenario_status(p_status_code character varying) OWNER TO postgres;

--
-- Name: FUNCTION fn_is_valid_scenario_status(p_status_code character varying); Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON FUNCTION global.fn_is_valid_scenario_status(p_status_code character varying) IS 'Returns true if p_status_code exists in gd_007_status_registry for status_type = ''scenario_status''. STABLE.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: log; Type: TABLE; Schema: audit; Owner: postgres
--

CREATE TABLE audit.log (
    log_id bigint NOT NULL,
    table_name text NOT NULL,
    row_id text NOT NULL,
    action text NOT NULL,
    performed_by_id bigint,
    performed_by_code text,
    performed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_log_action_chk CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


ALTER TABLE audit.log OWNER TO postgres;

--
-- Name: log_log_id_seq; Type: SEQUENCE; Schema: audit; Owner: postgres
--

ALTER TABLE audit.log ALTER COLUMN log_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME audit.log_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: 001_core_entities; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."001_core_entities" (
    entity_id bigint CONSTRAINT gd_003_entities_entity_id_not_null NOT NULL,
    entity_reg_number character varying(128) CONSTRAINT gd_003_entities_entity_reg_number_not_null NOT NULL,
    country_code character(2) CONSTRAINT gd_003_entities_country_code_not_null NOT NULL,
    legal_name text CONSTRAINT gd_003_entities_legal_name_not_null NOT NULL,
    normalized_name text CONSTRAINT gd_003_entities_normalized_name_not_null NOT NULL,
    tax_id character varying(128),
    vat_id character varying(128),
    legal_address text,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_003_entities_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_003_entities_valid_to_not_null NOT NULL,
    CONSTRAINT gd_003_entities_identity_chk CHECK (((vat_id IS NOT NULL) OR (tax_id IS NOT NULL) OR (normalized_name IS NOT NULL))),
    CONSTRAINT gd_003_entities_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global."001_core_entities" OWNER TO postgres;

--
-- Name: TABLE "001_core_entities"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."001_core_entities" IS 'Canonical registry of organizational entities participating in deterministic replay, governance reconstruction and operational interpretation.';


--
-- Name: COLUMN "001_core_entities".entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".entity_id IS 'Stable internal identity of organizational entity.';


--
-- Name: COLUMN "001_core_entities".entity_reg_number; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".entity_reg_number IS 'Canonical registration identifier assigned to organizational entity.';


--
-- Name: COLUMN "001_core_entities".country_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".country_code IS 'Jurisdictional country code associated with organizational entity registration.';


--
-- Name: COLUMN "001_core_entities".legal_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".legal_name IS 'Official legal designation of organizational entity.';


--
-- Name: COLUMN "001_core_entities".normalized_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".normalized_name IS 'Normalized searchable representation of organizational entity name used for deterministic matching and deduplication.';


--
-- Name: COLUMN "001_core_entities".tax_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".tax_id IS 'Jurisdictional taxpayer identification reference of organizational entity.';


--
-- Name: COLUMN "001_core_entities".vat_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".vat_id IS 'Jurisdictional VAT registration reference of organizational entity.';


--
-- Name: COLUMN "001_core_entities".legal_address; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".legal_address IS 'Registered legal address of organizational entity.';


--
-- Name: COLUMN "001_core_entities".valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".valid_from IS 'Beginning of organizational entity applicability interval.';


--
-- Name: COLUMN "001_core_entities".valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."001_core_entities".valid_to IS 'End of organizational entity applicability interval.';


--
-- Name: 002_core_people; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."002_core_people" (
    person_id bigint CONSTRAINT gd_007_people_person_id_not_null NOT NULL,
    person_code character varying(128),
    first_name character varying(128) CONSTRAINT gd_007_people_first_name_not_null NOT NULL,
    middle_name character varying(128),
    last_name character varying(128) CONSTRAINT gd_007_people_last_name_not_null NOT NULL,
    tax_id character varying(128),
    date_of_birth date,
    country_code character(2)
);


ALTER TABLE global."002_core_people" OWNER TO postgres;

--
-- Name: TABLE "002_core_people"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."002_core_people" IS 'Canonical registry of real-world persons participating in organizational reconstruction and governance relations.';


--
-- Name: COLUMN "002_core_people".person_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".person_id IS 'Stable internal identity of person record.';


--
-- Name: COLUMN "002_core_people".person_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".person_code IS 'Canonical external or organizational identifier of person.';


--
-- Name: COLUMN "002_core_people".first_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".first_name IS 'Registered first name of person.';


--
-- Name: COLUMN "002_core_people".middle_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".middle_name IS 'Registered middle name of person.';


--
-- Name: COLUMN "002_core_people".last_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".last_name IS 'Registered last name of person.';


--
-- Name: COLUMN "002_core_people".tax_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".tax_id IS 'Jurisdictional taxpayer or national identification reference of person.';


--
-- Name: COLUMN "002_core_people".date_of_birth; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".date_of_birth IS 'Declared date of birth of person.';


--
-- Name: COLUMN "002_core_people".country_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."002_core_people".country_code IS 'Canonical country code associated with person record.';


--
-- Name: 003_core_projects; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."003_core_projects" (
    project_id bigint CONSTRAINT gd_025_projects_project_id_nn NOT NULL,
    project_code text CONSTRAINT gd_025_projects_project_code_nn NOT NULL,
    project_name text CONSTRAINT gd_025_projects_project_name_nn NOT NULL,
    project_owner_arrangement_id bigint,
    description text,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_025_projects_valid_from_nn NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_025_projects_valid_to_nn NOT NULL,
    CONSTRAINT gd_025_projects_temporal_chk CHECK ((valid_from < valid_to))
);


ALTER TABLE global."003_core_projects" OWNER TO postgres;

--
-- Name: TABLE "003_core_projects"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."003_core_projects" IS 'Project registry. Each row represents a named organizational project. Referenced by gd_026_teammembers for project allocation tracking.';


--
-- Name: COLUMN "003_core_projects".project_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."003_core_projects".project_code IS 'Short stable human-readable code (e.g. ''Astra'', ''Delta'').';


--
-- Name: COLUMN "003_core_projects".project_owner_arrangement_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."003_core_projects".project_owner_arrangement_id IS 'The specific team member arrangement of the person responsible for this project. References gd_026_teammembers — ownership is attributed to a person in their organizational capacity, not merely as a natural person. Nullable: set to NULL when creating the project, updated once the owner arrangement record exists.';


--
-- Name: 101_gov_identities; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."101_gov_identities" (
    governance_identity_id bigint CONSTRAINT gd_013_governance_identities_governance_identity_id_not_null NOT NULL,
    identity_type character varying(64) CONSTRAINT gd_013_governance_identities_identity_type_not_null NOT NULL,
    identity_name character varying(256) CONSTRAINT gd_013_governance_identities_identity_name_not_null NOT NULL,
    identity_code character varying(128) CONSTRAINT gd_013_governance_identities_identity_code_not_null NOT NULL,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_013_governance_identities_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_013_governance_identities_valid_to_not_null NOT NULL,
    identity_status character varying(32) CONSTRAINT gd_013_governance_identities_identity_status_not_null NOT NULL,
    identity_description text,
    created_by_identity_id bigint,
    person_id bigint,
    CONSTRAINT gd_008_governance_identities_identity_type_chk CHECK (((identity_type)::text = ANY ((ARRAY['human_controller'::character varying, 'system'::character varying, 'auditor'::character varying, 'external'::character varying])::text[]))),
    CONSTRAINT gd_013_governance_identities_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global."101_gov_identities" OWNER TO postgres;

--
-- Name: COLUMN "101_gov_identities".identity_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."101_gov_identities".identity_type IS 'Category of governance identity. human_controller: primary governance authority with independent commit rights. system: automated service identity (AI, data pipelines, scheduled processes). auditor: read and disclosure access, no commit authority. external: outside party authorized to receive disclosures. Authority gradient within human_controller population is managed via gd_022_delegations — identity_type records category, not current scope.';


--
-- Name: COLUMN "101_gov_identities".created_by_identity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."101_gov_identities".created_by_identity_id IS 'Governance identity that created this record. Self-referencing FK. NULL only on the bootstrap genesis record — the organizational trust anchor that has no authority predecessor within the system. All subsequent governance identity records must reference an existing identity. This is a governance traceability field, not merely an audit convenience field.';


--
-- Name: 102_gov_proposals; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."102_gov_proposals" (
    proposal_id bigint CONSTRAINT gd_021_proposals_proposal_id_nn NOT NULL,
    proposal_type text CONSTRAINT gd_021_proposals_proposal_type_nn NOT NULL,
    proposal_status text DEFAULT 'pending'::text CONSTRAINT gd_021_proposals_proposal_status_nn NOT NULL,
    source_type text CONSTRAINT gd_021_proposals_source_type_nn NOT NULL,
    source_ref text,
    entity_id bigint,
    scenario_id bigint,
    proposal_description text CONSTRAINT gd_021_proposals_description_nn NOT NULL,
    proposal_payload jsonb,
    generated_by text CONSTRAINT gd_021_proposals_generated_by_nn NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    review_notes text,
    superseded_by bigint,
    CONSTRAINT gd_021_proposals_proposal_status_chk CHECK ((proposal_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'superseded'::text, 'archived'::text]))),
    CONSTRAINT gd_021_proposals_proposal_type_chk CHECK ((proposal_type = ANY (ARRAY['corrective'::text, 'governance'::text, 'disclosure'::text, 'analytical'::text, 'operational'::text]))),
    CONSTRAINT gd_021_proposals_review_consistency_chk CHECK ((((reviewed_by IS NULL) AND (reviewed_at IS NULL)) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL)))),
    CONSTRAINT gd_021_proposals_source_type_chk CHECK ((source_type = ANY (ARRAY['ai_analysis'::text, 'anomaly_detection'::text, 'replay_analysis'::text, 'scenario_analysis'::text, 'governance_escalation'::text, 'disclosure_review'::text, 'manual'::text])))
);


ALTER TABLE global."102_gov_proposals" OWNER TO postgres;

--
-- Name: TABLE "102_gov_proposals"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."102_gov_proposals" IS 'Canonical landing zone for governance-reviewable candidate organizational mutations. Non-authoritative until governance-recognized authoritative commit occurs. Interim structure: proposal_payload is JSONB pending stabilization of per-category typed schemas.';


--
-- Name: COLUMN "102_gov_proposals".proposal_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".proposal_type IS 'Category of mutation being proposed. Governs interpretation of proposal_payload.';


--
-- Name: COLUMN "102_gov_proposals".proposal_status; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".proposal_status IS 'Lifecycle state. Proposals move from pending → approved/rejected/superseded.';


--
-- Name: COLUMN "102_gov_proposals".source_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".source_type IS 'What produced this proposal — AI pipeline, escalation, manual, etc.';


--
-- Name: COLUMN "102_gov_proposals".source_ref; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".source_ref IS 'Free-text reference to the specific source artifact or process run.';


--
-- Name: COLUMN "102_gov_proposals".entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".entity_id IS 'Organizational entity this proposal concerns. Nullable — not all proposals are entity-scoped.';


--
-- Name: COLUMN "102_gov_proposals".scenario_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".scenario_id IS 'Scenario context when proposal derives from scenario projection analysis.';


--
-- Name: COLUMN "102_gov_proposals".proposal_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".proposal_description IS 'Human-readable statement of what is being proposed and the basis for it.';


--
-- Name: COLUMN "102_gov_proposals".proposal_payload; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".proposal_payload IS 'Structured mutation details. Shape varies by proposal_type. Interim JSONB — to be replaced by typed per-category structures once payload schemas are confirmed stable.';


--
-- Name: COLUMN "102_gov_proposals".generated_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".generated_by IS 'Identity of the actor or system that generated this proposal.';


--
-- Name: COLUMN "102_gov_proposals".reviewed_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".reviewed_by IS 'Governance identity that reviewed this proposal. Null until reviewed.';


--
-- Name: COLUMN "102_gov_proposals".reviewed_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".reviewed_at IS 'Timestamp of governance review. Null until reviewed.';


--
-- Name: COLUMN "102_gov_proposals".review_notes; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".review_notes IS 'Reviewer commentary — rationale for approval, rejection, or conditions.';


--
-- Name: COLUMN "102_gov_proposals".superseded_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."102_gov_proposals".superseded_by IS 'References the proposal that supersedes this one. Superseded proposals remain reconstructable per additive correction doctrine.';


--
-- Name: 103_gov_delegations; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."103_gov_delegations" (
    delegation_id bigint CONSTRAINT gd_022_delegations_delegation_id_nn NOT NULL,
    delegator_id bigint CONSTRAINT gd_022_delegations_delegator_id_nn NOT NULL,
    delegatee_id bigint CONSTRAINT gd_022_delegations_delegatee_id_nn NOT NULL,
    delegation_scope text CONSTRAINT gd_022_delegations_delegation_scope_nn NOT NULL,
    entity_id bigint,
    valid_from timestamp with time zone CONSTRAINT gd_022_delegations_valid_from_nn NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_022_delegations_valid_to_nn NOT NULL,
    revoked_at timestamp with time zone,
    revoked_by text,
    delegation_description text,
    CONSTRAINT gd_022_delegations_revocation_consistency_chk CHECK ((((revoked_at IS NULL) AND (revoked_by IS NULL)) OR ((revoked_at IS NOT NULL) AND (revoked_by IS NOT NULL)))),
    CONSTRAINT gd_022_delegations_revocation_temporal_chk CHECK (((revoked_at IS NULL) OR (revoked_at >= valid_from))),
    CONSTRAINT gd_022_delegations_scope_chk CHECK ((delegation_scope = ANY (ARRAY['authoritative_commit'::text, 'replay_execution'::text, 'disclosure_authorization'::text, 'delegation_issuance'::text, 'escalation_handling'::text, 'scenario_execution'::text]))),
    CONSTRAINT gd_022_delegations_self_delegation_chk CHECK ((delegator_id <> delegatee_id)),
    CONSTRAINT gd_022_delegations_temporal_chk CHECK ((valid_from < valid_to))
);


ALTER TABLE global."103_gov_delegations" OWNER TO postgres;

--
-- Name: TABLE "103_gov_delegations"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."103_gov_delegations" IS 'Canonical registry of governance delegations per Doc 21 §6. Delegation represents bounded governance-authorized transfer of limited authority scope. Delegations are explicit, revocable, temporally scoped, reconstructable, and non-inheritable. Expired and revoked delegations are never deleted — historical reconstructability must be preserved.';


--
-- Name: COLUMN "103_gov_delegations".delegator_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".delegator_id IS 'Governance identity issuing the delegation. Must hold the authority being delegated at time of issuance.';


--
-- Name: COLUMN "103_gov_delegations".delegatee_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".delegatee_id IS 'Governance identity receiving the delegation. Cannot be the same as delegator_id.';


--
-- Name: COLUMN "103_gov_delegations".delegation_scope; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".delegation_scope IS 'Bounded authority category being transferred. Constrained to the six authorization categories defined in Doc 21 §5.1. Scope remains explicitly bounded — delegation does not grant unrestricted authority.';


--
-- Name: COLUMN "103_gov_delegations".entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".entity_id IS 'Organizational entity this delegation is scoped to. NULL denotes an organisation-wide delegation not bounded to a single entity.';


--
-- Name: COLUMN "103_gov_delegations".valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".valid_from IS 'Timestamp from which the delegation becomes effective.';


--
-- Name: COLUMN "103_gov_delegations".valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".valid_to IS 'Timestamp at which the delegation expires. Defaults to effectively unbounded (3001-12-31). Expiry does not destroy historical reconstructability.';


--
-- Name: COLUMN "103_gov_delegations".revoked_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".revoked_at IS 'Timestamp of explicit revocation. NULL while delegation is active. Revocation is recorded additively — the row is never deleted.';


--
-- Name: COLUMN "103_gov_delegations".revoked_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".revoked_by IS 'Identity that performed the revocation. Must be populated together with revoked_at.';


--
-- Name: COLUMN "103_gov_delegations".delegation_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."103_gov_delegations".delegation_description IS 'Human-readable statement of scope boundaries, conditions, and governance context of this delegation.';


--
-- Name: 104_gov_commits; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."104_gov_commits" (
    commit_id bigint CONSTRAINT gd_005_commit_records_commit_id_not_null NOT NULL,
    commit_timestamp timestamp with time zone CONSTRAINT gd_005_commit_records_commit_timestamp_not_null NOT NULL,
    committing_authority_id bigint CONSTRAINT gd_005_commit_records_committing_authority_id_not_null NOT NULL,
    commit_type character varying(64) CONSTRAINT gd_005_commit_records_commit_type_not_null NOT NULL,
    commit_reason text,
    commit_status character varying(32) CONSTRAINT gd_005_commit_records_commit_status_not_null NOT NULL,
    CONSTRAINT gd_006_commit_records_commit_status_chk CHECK (global.fn_is_valid_commit_status(commit_status)),
    CONSTRAINT gd_006_commit_records_commit_timestamp_chk CHECK ((commit_timestamp >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone))
);


ALTER TABLE global."104_gov_commits" OWNER TO postgres;

--
-- Name: 105_gov_shareholdings; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."105_gov_shareholdings" (
    shareholding_id bigint NOT NULL,
    entity_id bigint NOT NULL,
    governance_identity_id bigint NOT NULL,
    share_pct numeric(8,4) NOT NULL,
    share_class character varying(64),
    valid_from timestamp with time zone NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone NOT NULL,
    notes text,
    CONSTRAINT chk_shareholding_dates CHECK ((valid_from < valid_to)),
    CONSTRAINT chk_shareholding_pct CHECK (((share_pct > (0)::numeric) AND (share_pct <= (100)::numeric)))
);


ALTER TABLE global."105_gov_shareholdings" OWNER TO postgres;

--
-- Name: TABLE "105_gov_shareholdings"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."105_gov_shareholdings" IS 'Shareholding registry. One row per owner per entity per validity period. Changing ownership produces a new row with updated valid_from — prior row closed with valid_to. Sum of share_pct for a given entity_id at any point in time should equal 100.';


--
-- Name: 105_gov_shareholdings_shareholding_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."105_gov_shareholdings" ALTER COLUMN shareholding_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME global."105_gov_shareholdings_shareholding_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: 201_fin_coa; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."201_fin_coa" (
    account_code character varying(128) CONSTRAINT gd_016_coa_account_code_not_null NOT NULL,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_016_coa_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_016_coa_valid_to_not_null NOT NULL,
    account_type text,
    account_name text,
    coa_id bigint NOT NULL,
    coa_set_code character varying(64) DEFAULT 'internal_project_coa'::character varying NOT NULL,
    parent_coa_id bigint,
    normal_balance character(6),
    column6 character varying(50),
    CONSTRAINT "201_fin_coa_normal_balance_check" CHECK ((normal_balance = ANY (ARRAY['debit'::bpchar, 'credit'::bpchar]))),
    CONSTRAINT gd_016_coa_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global."201_fin_coa" OWNER TO postgres;

--
-- Name: TABLE "201_fin_coa"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."201_fin_coa" IS 'Canonical accounting topology. Defines the account hierarchy via parent_account_code self-FK. Account names and multilingual equivalents are held in gd_017_naming_conventions (object_type = ''coa_account'', object_ref = account_code). Rulesets reference accounts via gd_005_ruleset_lines.account_code — the interpretive direction is Ruleset → CoA, not CoA → Ruleset.';


--
-- Name: COLUMN "201_fin_coa".account_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."201_fin_coa".account_code IS 'Stable canonical accounting topology identifier.';


--
-- Name: COLUMN "201_fin_coa".valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."201_fin_coa".valid_from IS 'Beginning of accounting topology applicability interval.';


--
-- Name: COLUMN "201_fin_coa".valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."201_fin_coa".valid_to IS 'End of accounting topology applicability interval.';


--
-- Name: COLUMN "201_fin_coa".account_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."201_fin_coa".account_type IS 'Classification of this account within the financial reporting structure. References gd_028_coa_account_types. Nullable for structural/grouping nodes that exist only as hierarchy containers.';


--
-- Name: COLUMN "201_fin_coa".account_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."201_fin_coa".account_name IS 'Human-readable account label for operational convenience. Canonical and multilingual names are held in gd_017_naming_conventions (object_type = ''coa_account'', object_ref = account_code). This field is a working label, not the authoritative name source.';


--
-- Name: 201_fin_coa_coa_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."201_fin_coa" ALTER COLUMN coa_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME global."201_fin_coa_coa_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: 202_fin_rulesets; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."202_fin_rulesets" (
    ruleset_id character varying(128) CONSTRAINT gd_008_ruleset_registry_ruleset_id_not_null NOT NULL,
    ruleset_name character varying(256) CONSTRAINT gd_008_ruleset_registry_ruleset_name_not_null NOT NULL,
    ruleset_type character varying(64) CONSTRAINT gd_008_ruleset_registry_ruleset_type_not_null NOT NULL,
    ruleset_description text,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_008_ruleset_registry_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_008_ruleset_registry_valid_to_not_null NOT NULL,
    governance_scope_id bigint,
    CONSTRAINT gd_008_ruleset_registry_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global."202_fin_rulesets" OWNER TO postgres;

--
-- Name: TABLE "202_fin_rulesets"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."202_fin_rulesets" IS 'Canonical registry of governance-approved Rulesets participating in deterministic reconstruction and replay.';


--
-- Name: COLUMN "202_fin_rulesets".ruleset_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."202_fin_rulesets".ruleset_id IS 'Stable canonical Ruleset identity.';


--
-- Name: COLUMN "202_fin_rulesets".ruleset_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."202_fin_rulesets".ruleset_name IS 'Human-readable Ruleset name.';


--
-- Name: COLUMN "202_fin_rulesets".ruleset_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."202_fin_rulesets".ruleset_type IS 'Canonical Ruleset classification.';


--
-- Name: COLUMN "202_fin_rulesets".ruleset_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."202_fin_rulesets".ruleset_description IS 'Human-readable Ruleset explanation and applicability notes.';


--
-- Name: COLUMN "202_fin_rulesets".valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."202_fin_rulesets".valid_from IS 'Beginning of Ruleset applicability interval.';


--
-- Name: COLUMN "202_fin_rulesets".valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."202_fin_rulesets".valid_to IS 'End of Ruleset applicability interval.';


--
-- Name: COLUMN "202_fin_rulesets".governance_scope_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."202_fin_rulesets".governance_scope_id IS 'Governance applicability scope participating in Ruleset authorization and replay semantics.';


--
-- Name: 203_fin_ruleset_lines; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."203_fin_ruleset_lines" (
    line_id bigint CONSTRAINT gd_009_ruleset_lines_line_id_not_null NOT NULL,
    ruleset_id character varying(128) CONSTRAINT gd_009_ruleset_lines_ruleset_id_not_null NOT NULL,
    entity_1_id bigint,
    entity_2_id bigint,
    trf_direction character varying(32) CONSTRAINT gd_009_ruleset_lines_trf_direction_not_null NOT NULL,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_009_ruleset_lines_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_009_ruleset_lines_valid_to_not_null NOT NULL,
    line_description text,
    coa_id bigint,
    has_allocations boolean DEFAULT false NOT NULL,
    policy_ref text,
    account_code character varying(128),
    coa_set_code character varying(64),
    event_type character varying(64),
    CONSTRAINT gd_009_ruleset_lines_transformation_direction_chk CHECK (((trf_direction)::text = ANY ((ARRAY['increase'::character varying, 'decrease'::character varying, 'recognize'::character varying, 'derecognize'::character varying, 'transfer_in'::character varying, 'transfer_out'::character varying, 'debit'::character varying, 'credit'::character varying])::text[]))),
    CONSTRAINT gd_009_ruleset_lines_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global."203_fin_ruleset_lines" OWNER TO postgres;

--
-- Name: COLUMN "203_fin_ruleset_lines".entity_1_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."203_fin_ruleset_lines".entity_1_id IS 'Primary organizational entity this Ruleset line applies to. Nullable — not all Ruleset lines are entity-scoped. References gd_004_entities.entity_id.';


--
-- Name: COLUMN "203_fin_ruleset_lines".entity_2_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."203_fin_ruleset_lines".entity_2_id IS 'Secondary organizational entity this Ruleset line applies to. Used for inter-entity rules such as intercompany transfers. Nullable. References gd_004_entities.entity_id.';


--
-- Name: 206_fin_allocation_rules; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."206_fin_allocation_rules" (
    allocation_id bigint NOT NULL,
    line_id bigint CONSTRAINT gd_006_alloc_line_nn NOT NULL,
    ruleset_id character varying(128) CONSTRAINT gd_006_alloc_ruleset_nn NOT NULL,
    allocation_pct numeric(8,6) CONSTRAINT gd_006_alloc_pct_nn NOT NULL,
    coa_id bigint,
    project_id bigint,
    entity_id bigint,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone NOT NULL,
    description text,
    CONSTRAINT gd_006_alloc_pct_range CHECK (((allocation_pct > (0)::numeric) AND (allocation_pct <= (1)::numeric))),
    CONSTRAINT gd_006_alloc_valid_range CHECK ((valid_to >= valid_from))
);


ALTER TABLE global."206_fin_allocation_rules" OWNER TO postgres;

--
-- Name: 206_fin_allocation_rules_allocation_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."206_fin_allocation_rules" ALTER COLUMN allocation_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME global."206_fin_allocation_rules_allocation_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: 301_evt_events; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."301_evt_events" (
    event_id bigint CONSTRAINT gd_001_events_event_id_not_null NOT NULL,
    event_type character varying(64) CONSTRAINT gd_001_events_event_type_not_null NOT NULL,
    source_type character varying(32) CONSTRAINT gd_001_events_source_type_not_null NOT NULL,
    source_ref character varying(256),
    valid_time timestamp with time zone CONSTRAINT gd_001_events_valid_time_not_null NOT NULL,
    assertion_time timestamp with time zone CONSTRAINT gd_001_events_assertion_time_not_null NOT NULL,
    entity_id bigint CONSTRAINT gd_001_events_entity_id_not_null NOT NULL,
    governance_scope_id bigint,
    commit_id bigint CONSTRAINT gd_001_events_commit_id_not_null NOT NULL,
    event_description text,
    event_status character varying(32) CONSTRAINT gd_001_events_event_status_not_null NOT NULL,
    corrective_of_event_id bigint,
    replay_sequence bigint,
    amount numeric,
    currency_code character(3),
    scenario_id bigint,
    CONSTRAINT gd_001_events_assertion_time_chk CHECK ((assertion_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone)),
    CONSTRAINT gd_001_events_corrective_consistency_chk CHECK (((corrective_of_event_id IS NULL) OR ((corrective_of_event_id IS NOT NULL) AND ((event_type)::text = 'corrective'::text)))),
    CONSTRAINT gd_001_events_event_status_type_chk CHECK (global.fn_is_valid_event_status(event_status)),
    CONSTRAINT gd_001_events_valid_time_chk CHECK ((valid_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone))
);


ALTER TABLE global."301_evt_events" OWNER TO postgres;

--
-- Name: COLUMN "301_evt_events".corrective_of_event_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."301_evt_events".corrective_of_event_id IS 'References the Event this Event additively corrects. NULL on original Events. Populated only on corrective Events. Original Events are never modified — correction linkage is carried exclusively by the corrective Event. May form a chain: each corrective Event points to its immediate predecessor in the correction history.';


--
-- Name: COLUMN "301_evt_events".replay_sequence; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."301_evt_events".replay_sequence IS 'Globally monotonic database-assigned sequence providing deterministic replay sub-ordering within and across commits. Assigned exclusively by the database — never by the application layer. Canonical replay ordering: ORDER BY commit_id, replay_sequence. Immutable after assignment.';


--
-- Name: 302_evt_primitive_transitions; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."302_evt_primitive_transitions" (
    primitive_transition_id bigint CONSTRAINT gd_002_primitive_transitions_primitive_transition_id_not_null NOT NULL,
    event_id bigint CONSTRAINT gd_002_primitive_transitions_event_id_not_null NOT NULL,
    entity_id bigint CONSTRAINT gd_002_primitive_transitions_entity_id_not_null NOT NULL,
    transformation_direction character varying(32) CONSTRAINT gd_002_primitive_transitions_transformation_direction_not_null NOT NULL,
    amount numeric(20,6) CONSTRAINT gd_002_primitive_transitions_amount_not_null NOT NULL,
    currency_code character(3),
    valid_time timestamp with time zone CONSTRAINT gd_002_primitive_transitions_valid_time_not_null NOT NULL,
    assertion_time timestamp with time zone CONSTRAINT gd_002_primitive_transitions_assertion_time_not_null NOT NULL,
    transition_description text,
    primitive_transition_type text CONSTRAINT gd_002_primitive_transitions_type_nn NOT NULL,
    coa_id bigint NOT NULL,
    scenario_id bigint,
    CONSTRAINT gd_002_primitive_transitions_amount_chk CHECK ((amount >= (0)::numeric)),
    CONSTRAINT gd_002_primitive_transitions_assertion_time_chk CHECK ((assertion_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone)),
    CONSTRAINT gd_002_primitive_transitions_direction_chk CHECK (((transformation_direction)::text = ANY ((ARRAY['increase'::character varying, 'decrease'::character varying])::text[]))),
    CONSTRAINT gd_002_primitive_transitions_valid_time_chk CHECK ((valid_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone))
);


ALTER TABLE global."302_evt_primitive_transitions" OWNER TO postgres;

--
-- Name: TABLE "302_evt_primitive_transitions"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."302_evt_primitive_transitions" IS 'Canonical atomic state mutations participating in deterministic replay and organizational reconstruction.';


--
-- Name: COLUMN "302_evt_primitive_transitions".primitive_transition_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".primitive_transition_id IS 'Stable internal identity of primitive transition.';


--
-- Name: COLUMN "302_evt_primitive_transitions".event_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".event_id IS 'References originating Event producing primitive state mutation.';


--
-- Name: COLUMN "302_evt_primitive_transitions".entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".entity_id IS 'Organizational entity whose state is affected by primitive transition.';


--
-- Name: COLUMN "302_evt_primitive_transitions".transformation_direction; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".transformation_direction IS 'Canonical polarity of primitive organizational state mutation.';


--
-- Name: COLUMN "302_evt_primitive_transitions".amount; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".amount IS 'Quantitative magnitude of primitive state mutation.';


--
-- Name: COLUMN "302_evt_primitive_transitions".currency_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".currency_code IS 'Currency applicable to quantitative mutation where relevant.';


--
-- Name: COLUMN "302_evt_primitive_transitions".valid_time; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".valid_time IS 'Business-effective timestamp of primitive transition applicability.';


--
-- Name: COLUMN "302_evt_primitive_transitions".assertion_time; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".assertion_time IS 'Timestamp at which primitive transition became known to the system.';


--
-- Name: COLUMN "302_evt_primitive_transitions".transition_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".transition_description IS 'Human-readable explanation of primitive transition semantics.';


--
-- Name: COLUMN "302_evt_primitive_transitions".primitive_transition_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."302_evt_primitive_transitions".primitive_transition_type IS 'Canonical type of this Primitive Transition. Determines replay stream participation. References gd_019_pt_types.pt_type_code.';


--
-- Name: 401_ref_exchange_rates; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."401_ref_exchange_rates" (
    rate_id bigint CONSTRAINT gd_004_exchange_rates_rate_id_not_null NOT NULL,
    rate_timestamp timestamp with time zone CONSTRAINT gd_004_exchange_rates_rate_timestamp_not_null NOT NULL,
    base_currency character(3) CONSTRAINT gd_004_exchange_rates_base_currency_not_null NOT NULL,
    quote_currency character(3) CONSTRAINT gd_004_exchange_rates_quote_currency_not_null NOT NULL,
    exchange_rate numeric(18,6) CONSTRAINT gd_004_exchange_rates_exchange_rate_not_null NOT NULL,
    rate_code character varying(64)
);


ALTER TABLE global."401_ref_exchange_rates" OWNER TO postgres;

--
-- Name: TABLE "401_ref_exchange_rates"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."401_ref_exchange_rates" IS 'Canonical exchange rate registry participating in deterministic replay and financial reconstruction.';


--
-- Name: COLUMN "401_ref_exchange_rates".rate_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."401_ref_exchange_rates".rate_id IS 'Stable internal identity of exchange rate record.';


--
-- Name: COLUMN "401_ref_exchange_rates".rate_timestamp; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."401_ref_exchange_rates".rate_timestamp IS 'Timestamp at which exchange rate becomes applicable for replay and interpretation.';


--
-- Name: COLUMN "401_ref_exchange_rates".base_currency; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."401_ref_exchange_rates".base_currency IS 'Source currency participating in exchange rate transformation.';


--
-- Name: COLUMN "401_ref_exchange_rates".quote_currency; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."401_ref_exchange_rates".quote_currency IS 'Target currency participating in exchange rate transformation.';


--
-- Name: COLUMN "401_ref_exchange_rates".exchange_rate; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."401_ref_exchange_rates".exchange_rate IS 'Deterministic conversion ratio between base and quote currency.';


--
-- Name: COLUMN "401_ref_exchange_rates".rate_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."401_ref_exchange_rates".rate_code IS 'Canonical exchange rate source or methodology identifier.';


--
-- Name: 402_ref_inflation_rates; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."402_ref_inflation_rates" (
    inflation_rate_id bigint CONSTRAINT gd_014_inflation_rates_inflation_rate_id_nn NOT NULL,
    applicable_year integer CONSTRAINT gd_014_inflation_rates_applicable_year_nn NOT NULL,
    currency_code character(3) CONSTRAINT gd_014_inflation_rates_currency_code_nn NOT NULL,
    inflation_rate numeric(10,6) CONSTRAINT gd_014_inflation_rates_inflation_rate_nn NOT NULL,
    rate_reference character varying(128),
    CONSTRAINT gd_014_inflation_rates_rate_range_chk CHECK (((inflation_rate >= ('-100'::integer)::numeric) AND (inflation_rate <= (1000000)::numeric))),
    CONSTRAINT gd_014_inflation_rates_year_chk CHECK (((applicable_year >= 1900) AND (applicable_year <= 3000)))
);


ALTER TABLE global."402_ref_inflation_rates" OWNER TO postgres;

--
-- Name: COLUMN "402_ref_inflation_rates".rate_reference; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."402_ref_inflation_rates".rate_reference IS 'Canonical identifier of the data source used to establish this rate. References gd_018_rate_codes. Nullable pending governance consensus on acceptable source registry for historical rows.';


--
-- Name: 403_ref_currencies; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."403_ref_currencies" (
    currency_id bigint CONSTRAINT gd_012_currency_registry_currency_id_not_null NOT NULL,
    currency_name character varying(128) CONSTRAINT gd_012_currency_registry_currency_name_not_null NOT NULL,
    iso_alpha_2 character(2),
    iso_alpha_3 character(3) CONSTRAINT gd_012_currency_registry_iso_alpha_3_not_null NOT NULL,
    currency_symbol character varying(16),
    issuing_jurisdiction character varying(128),
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_012_currency_registry_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_012_currency_registry_valid_to_not_null NOT NULL,
    CONSTRAINT gd_012_currency_registry_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global."403_ref_currencies" OWNER TO postgres;

--
-- Name: TABLE "403_ref_currencies"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."403_ref_currencies" IS 'Canonical registry of currencies participating in deterministic replay, valuation and financial reconstruction.';


--
-- Name: COLUMN "403_ref_currencies".currency_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".currency_id IS 'Stable internal identity of currency record.';


--
-- Name: COLUMN "403_ref_currencies".currency_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".currency_name IS 'Human-readable canonical currency name.';


--
-- Name: COLUMN "403_ref_currencies".iso_alpha_2; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".iso_alpha_2 IS 'Two-letter canonical currency abbreviation where applicable.';


--
-- Name: COLUMN "403_ref_currencies".iso_alpha_3; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".iso_alpha_3 IS 'Three-letter ISO currency code used in replay and reporting semantics.';


--
-- Name: COLUMN "403_ref_currencies".currency_symbol; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".currency_symbol IS 'Human-readable symbol representing currency in disclosure and reporting contexts.';


--
-- Name: COLUMN "403_ref_currencies".issuing_jurisdiction; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".issuing_jurisdiction IS 'Jurisdiction or authority associated with currency issuance.';


--
-- Name: COLUMN "403_ref_currencies".valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".valid_from IS 'Beginning of currency applicability interval.';


--
-- Name: COLUMN "403_ref_currencies".valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."403_ref_currencies".valid_to IS 'End of currency applicability interval.';


--
-- Name: 404_ref_rate_sources; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."404_ref_rate_sources" (
    rate_code text CONSTRAINT gd_018_rate_codes_rate_code_not_null NOT NULL,
    rate_name text CONSTRAINT gd_018_rate_codes_rate_name_not_null NOT NULL,
    rate_type text CONSTRAINT gd_018_rate_codes_rate_type_not_null NOT NULL,
    provider text,
    description text
);


ALTER TABLE global."404_ref_rate_sources" OWNER TO postgres;

--
-- Name: 405_ref_names; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."405_ref_names" (
    naming_id bigint CONSTRAINT gd_017_naming_conventions_naming_id_not_null NOT NULL,
    object_type character varying(128) CONSTRAINT gd_017_naming_conventions_object_type_not_null NOT NULL,
    object_ref text CONSTRAINT gd_017_naming_conventions_object_id_not_null NOT NULL,
    canonical_name character varying(256) CONSTRAINT gd_017_naming_conventions_canonical_name_not_null NOT NULL,
    translation_language character(2) CONSTRAINT gd_017_naming_conventions_translation_language_not_null NOT NULL,
    translated_name character varying(256) CONSTRAINT gd_017_naming_conventions_translated_name_not_null NOT NULL,
    translation_context character varying(128)
);


ALTER TABLE global."405_ref_names" OWNER TO postgres;

--
-- Name: TABLE "405_ref_names"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."405_ref_names" IS 'Canonical multilingual naming registry used for disclosure, reporting, localization and governance-readable reconstruction.';


--
-- Name: COLUMN "405_ref_names".naming_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."405_ref_names".naming_id IS 'Stable internal identity of naming convention record.';


--
-- Name: COLUMN "405_ref_names".object_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."405_ref_names".object_type IS 'Canonical classification of organizational object receiving translated naming semantics.';


--
-- Name: COLUMN "405_ref_names".object_ref; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."405_ref_names".object_ref IS 'Primary key value of the referenced object, stored as text. Holds stringified integer PKs (e.g. ''42'') for bigint-keyed tables and varchar PKs as-is (e.g. ''ACC-001-CASH'') for text-keyed tables such as gd_016_coa. Interpreted in conjunction with object_type. No FK enforcement — polymorphic references cannot be constrained at the database level.';


--
-- Name: COLUMN "405_ref_names".canonical_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."405_ref_names".canonical_name IS 'Primary canonical organizational name of object.';


--
-- Name: COLUMN "405_ref_names".translation_language; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."405_ref_names".translation_language IS 'Language code of translated naming representation.';


--
-- Name: COLUMN "405_ref_names".translated_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."405_ref_names".translated_name IS 'Localized or translated organizational naming representation.';


--
-- Name: COLUMN "405_ref_names".translation_context; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."405_ref_names".translation_context IS 'Optional disclosure, legal or reporting context governing translation applicability.';


--
-- Name: 406_ref_pt_types; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."406_ref_pt_types" (
    pt_type_code text CONSTRAINT gd_019_pt_types_pt_type_code_nn NOT NULL,
    pt_type_name text CONSTRAINT gd_019_pt_types_pt_type_name_nn NOT NULL,
    description text
);


ALTER TABLE global."406_ref_pt_types" OWNER TO postgres;

--
-- Name: TABLE "406_ref_pt_types"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."406_ref_pt_types" IS 'Canonical registry of Primitive Transition types as defined in Doc 19. Determines which reconstruction stream a Primitive Transition participates in.';


--
-- Name: COLUMN "406_ref_pt_types".pt_type_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."406_ref_pt_types".pt_type_code IS 'Stable short identifier referenced by gd_002_primitive_transitions.primitive_transition_type.';


--
-- Name: COLUMN "406_ref_pt_types".pt_type_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."406_ref_pt_types".pt_type_name IS 'Full canonical name of the Primitive Transition type.';


--
-- Name: COLUMN "406_ref_pt_types".description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."406_ref_pt_types".description IS 'Scope of mutations belonging to this type and their replay participation semantics.';


--
-- Name: 407_ref_statuses; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."407_ref_statuses" (
    status_code character varying(32) CONSTRAINT gd_006_event_status_registry_event_status_code_not_null NOT NULL,
    status_name character varying(128) CONSTRAINT gd_006_event_status_registry_event_status_name_not_null NOT NULL,
    status_description text,
    is_authoritative_replay_eligible boolean DEFAULT false CONSTRAINT gd_006_event_status_registr_is_authoritative_replay_el_not_null NOT NULL,
    is_terminal boolean DEFAULT false CONSTRAINT gd_006_event_status_registry_is_terminal_not_null NOT NULL,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_006_event_status_registry_created_at_not_null NOT NULL,
    status_type character varying(64) DEFAULT 'event_status'::character varying CONSTRAINT gd_006_status_registry_status_type_not_null NOT NULL
);


ALTER TABLE global."407_ref_statuses" OWNER TO postgres;

--
-- Name: 408_ref_event_types; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."408_ref_event_types" (
    event_type_code text CONSTRAINT gd_023_event_types_code_nn NOT NULL,
    event_type_name text CONSTRAINT gd_023_event_types_name_nn NOT NULL,
    description text
);


ALTER TABLE global."408_ref_event_types" OWNER TO postgres;

--
-- Name: TABLE "408_ref_event_types"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."408_ref_event_types" IS 'Canonical registry of Event types as defined in Doc 19 §5. Referenced by gd_001_events.event_type. Extending the type set requires only an INSERT — no DDL on gd_001_events.';


--
-- Name: COLUMN "408_ref_event_types".event_type_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."408_ref_event_types".event_type_code IS 'Stable short identifier referenced by gd_001_events.event_type.';


--
-- Name: COLUMN "408_ref_event_types".event_type_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."408_ref_event_types".event_type_name IS 'Full canonical name of the Event type per Doc 19.';


--
-- Name: COLUMN "408_ref_event_types".description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."408_ref_event_types".description IS 'Scope of Events belonging to this type and their replay participation semantics.';


--
-- Name: 409_ref_coa_account_types; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."409_ref_coa_account_types" (
    account_type_code text CONSTRAINT gd_028_coa_account_types_code_nn NOT NULL,
    account_type_name text CONSTRAINT gd_028_coa_account_types_name_nn NOT NULL,
    description text
);


ALTER TABLE global."409_ref_coa_account_types" OWNER TO postgres;

--
-- Name: TABLE "409_ref_coa_account_types"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."409_ref_coa_account_types" IS 'Registry of CoA account type classifications. Determines which financial statement an account participates in and governs its role in reconstruction and budgeting.';


--
-- Name: COLUMN "409_ref_coa_account_types".account_type_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."409_ref_coa_account_types".account_type_code IS 'Stable short identifier referenced by gd_016_coa.account_type.';


--
-- Name: 410_cal_holidays; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."410_cal_holidays" (
    holiday_id bigint CONSTRAINT gd_011_holidays_holiday_id_not_null NOT NULL,
    country_code character(2) CONSTRAINT gd_011_holidays_country_code_not_null NOT NULL,
    holiday_name character varying(256) CONSTRAINT gd_011_holidays_holiday_name_not_null NOT NULL,
    holiday_type character varying(64) CONSTRAINT gd_011_holidays_holiday_type_not_null NOT NULL,
    holiday_date date CONSTRAINT gd_011_holidays_holiday_date_not_null NOT NULL
);


ALTER TABLE global."410_cal_holidays" OWNER TO postgres;

--
-- Name: TABLE "410_cal_holidays"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."410_cal_holidays" IS 'Canonical registry of jurisdictional and organizational holidays participating in deterministic replay, scheduling and governance timing semantics.';


--
-- Name: COLUMN "410_cal_holidays".holiday_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_cal_holidays".holiday_id IS 'Stable internal identity of holiday record.';


--
-- Name: COLUMN "410_cal_holidays".country_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_cal_holidays".country_code IS 'Jurisdictional country code associated with holiday applicability.';


--
-- Name: COLUMN "410_cal_holidays".holiday_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_cal_holidays".holiday_name IS 'Human-readable designation of holiday.';


--
-- Name: COLUMN "410_cal_holidays".holiday_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_cal_holidays".holiday_type IS 'Canonical classification of holiday applicability and governance semantics.';


--
-- Name: COLUMN "410_cal_holidays".holiday_date; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_cal_holidays".holiday_date IS 'Calendar date on which holiday becomes applicable.';


--
-- Name: 410_ref_arrangement_types; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."410_ref_arrangement_types" (
    arrangement_type_code text CONSTRAINT gd_024_lat_code_nn NOT NULL,
    arrangement_type_name text CONSTRAINT gd_024_lat_name_nn NOT NULL,
    arrangement_category text CONSTRAINT gd_024_lat_category_nn NOT NULL,
    jurisdiction_code character(2),
    description text,
    CONSTRAINT gd_024_lat_category_chk CHECK ((arrangement_category = ANY (ARRAY['employment'::text, 'private_entrepreneur'::text, 'civil_contract'::text, 'secondment'::text, 'management_contract'::text, 'advisory'::text, 'internship'::text])))
);


ALTER TABLE global."410_ref_arrangement_types" OWNER TO postgres;

--
-- Name: TABLE "410_ref_arrangement_types"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."410_ref_arrangement_types" IS 'Registry of legal arrangement types governing human engagement. arrangement_category determines financial reconstruction semantics (payroll obligations, tax treatment, social contributions).';


--
-- Name: COLUMN "410_ref_arrangement_types".arrangement_type_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_ref_arrangement_types".arrangement_type_code IS 'Stable short identifier referenced by gd_026_teammembers.';


--
-- Name: COLUMN "410_ref_arrangement_types".arrangement_category; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_ref_arrangement_types".arrangement_category IS 'Broad category governing financial and governance reconstruction semantics.';


--
-- Name: COLUMN "410_ref_arrangement_types".jurisdiction_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."410_ref_arrangement_types".jurisdiction_code IS 'ISO 3166-1 alpha-2 country code of the governing legal jurisdiction. Null for jurisdiction-agnostic types (secondment, advisory).';


--
-- Name: 411_ref_amortization_rates; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."411_ref_amortization_rates" (
    rate_id bigint NOT NULL,
    asset_category_code character varying(64) NOT NULL,
    asset_category_name character varying(128) NOT NULL,
    jurisdiction character(2),
    rate_basis character varying(16) NOT NULL,
    method character varying(32) NOT NULL,
    min_useful_life_yrs numeric(5,2),
    max_useful_life_yrs numeric(5,2),
    annual_rate_pct numeric(8,4) NOT NULL,
    legal_basis text,
    notes text,
    valid_from date DEFAULT '1901-01-01'::date NOT NULL,
    valid_to date DEFAULT '3001-12-31'::date NOT NULL,
    CONSTRAINT chk_method CHECK (((method)::text = ANY ((ARRAY['straight_line'::character varying, 'declining_balance'::character varying, 'units_of_production'::character varying])::text[]))),
    CONSTRAINT chk_rate_basis CHECK (((rate_basis)::text = ANY ((ARRAY['tax'::character varying, 'ifrs'::character varying])::text[]))),
    CONSTRAINT chk_rate_pos CHECK ((annual_rate_pct > (0)::numeric))
);


ALTER TABLE global."411_ref_amortization_rates" OWNER TO postgres;

--
-- Name: TABLE "411_ref_amortization_rates"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."411_ref_amortization_rates" IS 'Statutory and IFRS depreciation/amortization rate reference. jurisdiction NULL = universal IFRS guidance. rate_basis: tax = statutory minimum for CIT purposes; ifrs = IFRS economic useful life guidance. annual_rate_pct = 100 / useful_life_years for straight-line.';


--
-- Name: 411_ref_amortization_rates_rate_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."411_ref_amortization_rates" ALTER COLUMN rate_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME global."411_ref_amortization_rates_rate_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: 501_hr_arrangements; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."501_hr_arrangements" (
    arrangement_id bigint CONSTRAINT gd_026_tm_id_nn NOT NULL,
    person_id bigint CONSTRAINT gd_026_tm_person_nn NOT NULL,
    entity_id bigint,
    arrangement_type_code text CONSTRAINT gd_026_tm_type_nn NOT NULL,
    position_id bigint,
    project_id bigint,
    valid_from timestamp with time zone CONSTRAINT gd_026_tm_from_nn NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_026_tm_to_nn NOT NULL,
    time_allocation numeric CONSTRAINT gd_026_tm_alloc_nn NOT NULL,
    pay_currency character(3),
    pay_unit text,
    pay_amount numeric,
    CONSTRAINT gd_026_tm_allocation_chk CHECK (((time_allocation > (0)::numeric) AND (time_allocation <= 1.0))),
    CONSTRAINT gd_026_tm_pay_unit_chk CHECK ((pay_unit = ANY (ARRAY['hour'::text, 'day'::text, 'month'::text, 'year'::text, 'delivery'::text]))),
    CONSTRAINT gd_026_tm_payment_consistency_chk CHECK ((((pay_currency IS NULL) AND (pay_unit IS NULL) AND (pay_amount IS NULL)) OR ((pay_currency IS NOT NULL) AND (pay_unit IS NOT NULL) AND (pay_amount IS NOT NULL)))),
    CONSTRAINT gd_026_tm_temporal_chk CHECK ((valid_from < valid_to))
);


ALTER TABLE global."501_hr_arrangements" OWNER TO postgres;

--
-- Name: TABLE "501_hr_arrangements"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."501_hr_arrangements" IS 'Team member arrangements. Each row represents one immutable state: a specific combination of person, arrangement type, position, project, time allocation, and compensation valid for a defined period. Any change to any attribute produces a new row. valid_from/valid_to are the canonical state validity bounds — the prior four-column date model (arrangement + project dates) has been consolidated into this single pair.';


--
-- Name: COLUMN "501_hr_arrangements".position_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."501_hr_arrangements".position_id IS 'Consolidated from entity_position_id and project_position_id. The position carries its own class (statutory/operational) and scope (entity_id or project_id) — separate columns were redundant.';


--
-- Name: COLUMN "501_hr_arrangements".valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."501_hr_arrangements".valid_from IS 'Start of this specific arrangement state. Derived from the more specific of project_valid_from or arrangement_valid_from in the prior model.';


--
-- Name: COLUMN "501_hr_arrangements".valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."501_hr_arrangements".valid_to IS 'End of this specific arrangement state. Derived from the more specific of project_valid_to or arrangement_valid_to in the prior model.';


--
-- Name: 502_hr_positions; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."502_hr_positions" (
    position_id bigint CONSTRAINT gd_027_positions_id_nn NOT NULL,
    position_class text CONSTRAINT gd_027_positions_class_nn NOT NULL,
    position_name text CONSTRAINT gd_027_positions_name_nn NOT NULL,
    position_superior_id bigint,
    position_description text,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_027_positions_valid_from_nn NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_027_positions_valid_to_nn NOT NULL,
    project_id bigint,
    entity_id bigint,
    CONSTRAINT gd_027_positions_class_chk CHECK ((position_class = ANY (ARRAY['statutory'::text, 'operational'::text]))),
    CONSTRAINT gd_027_positions_no_self_superior_chk CHECK (((position_superior_id IS NULL) OR (position_superior_id <> position_id))),
    CONSTRAINT gd_027_positions_scope_exclusivity_chk CHECK (((project_id IS NULL) OR (entity_id IS NULL))),
    CONSTRAINT gd_027_positions_superior_context_chk CHECK (global.fn_is_valid_position_superior(position_superior_id, position_class, project_id, entity_id)),
    CONSTRAINT gd_027_positions_temporal_chk CHECK ((valid_from < valid_to))
);


ALTER TABLE global."502_hr_positions" OWNER TO postgres;

--
-- Name: TABLE "502_hr_positions"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."502_hr_positions" IS 'Canonical position registry supporting two independent hierarchies: entity_position (formal statutory org structure) and project_position (project delivery structure). Hierarchy enforced within class only — cross-class superior references are prevented by the composite FK on (position_superior_id, position_class). Recursive CTE traversal produces full org/project tree from this table.';


--
-- Name: COLUMN "502_hr_positions".position_class; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."502_hr_positions".position_class IS 'entity_position: formal role within legal entity — appears on statutory filings. project_position: operational role within a project delivery context.';


--
-- Name: COLUMN "502_hr_positions".position_superior_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."502_hr_positions".position_superior_id IS 'Immediate superior position within the same class. NULL denotes a root node (top of hierarchy). Composite FK enforces same-class constraint — cross-class reference fails at insert.';


--
-- Name: COLUMN "502_hr_positions".position_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."502_hr_positions".position_description IS 'Scope, responsibilities, and authority boundaries of this position.';


--
-- Name: COLUMN "502_hr_positions".project_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."502_hr_positions".project_id IS 'Project this position belongs to. NULL for statutory (entity-scoped) or universal positions. Mutually exclusive with entity_id.';


--
-- Name: COLUMN "502_hr_positions".entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."502_hr_positions".entity_id IS 'Entity this statutory position belongs to. NULL for operational or universal positions. Mutually exclusive with project_id.';


--
-- Name: 602_scen_scenarios; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global."602_scen_scenarios" (
    scenario_id bigint CONSTRAINT gd_020_scenarios_scenario_id_nn NOT NULL,
    scenario_name text CONSTRAINT gd_020_scenarios_scenario_name_nn NOT NULL,
    scenario_description text,
    base_date date CONSTRAINT gd_020_scenarios_base_date_nn NOT NULL,
    scenario_type text DEFAULT 'projection'::text CONSTRAINT gd_020_scenarios_type_nn NOT NULL,
    scenario_status character varying(32) DEFAULT 'draft'::character varying CONSTRAINT gd_020_scenarios_status_nn NOT NULL,
    entity_id bigint,
    period_from date,
    period_to date,
    notes text,
    approved_by bigint,
    approved_at timestamp with time zone,
    superseded_by_scenario_id bigint,
    "scenario_status " character varying(50),
    CONSTRAINT gd_020_scenarios_no_self_supersede CHECK (((superseded_by_scenario_id IS NULL) OR (superseded_by_scenario_id <> scenario_id))),
    CONSTRAINT gd_020_scenarios_period_chk CHECK (((period_to IS NULL) OR (period_from IS NULL) OR (period_to >= period_from))),
    CONSTRAINT gd_020_scenarios_status_chk CHECK (global.fn_is_valid_scenario_status(scenario_status)),
    CONSTRAINT gd_020_scenarios_type_chk CHECK ((scenario_type = ANY (ARRAY['projection'::text, 'budget'::text, 'stress_test'::text, 'base_case'::text])))
);


ALTER TABLE global."602_scen_scenarios" OWNER TO postgres;

--
-- Name: TABLE "602_scen_scenarios"; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global."602_scen_scenarios" IS 'Header registry of named future projection scenarios. A Scenario is a branch of hypothetical future reality anchored at base_date. All values before base_date are authoritative and immutable. Hypothetical future values in variable tables are tagged with scenario_id.';


--
-- Name: COLUMN "602_scen_scenarios".scenario_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."602_scen_scenarios".scenario_id IS 'Stable surrogate identity of the scenario. Referenced as scenario_id in all scenario-tagged variable rows.';


--
-- Name: COLUMN "602_scen_scenarios".scenario_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."602_scen_scenarios".scenario_name IS 'Short unique human-readable name identifying this scenario.';


--
-- Name: COLUMN "602_scen_scenarios".scenario_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."602_scen_scenarios".scenario_description IS 'Narrative description of the assumptions adopted in this scenario.';


--
-- Name: COLUMN "602_scen_scenarios".base_date; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."602_scen_scenarios".base_date IS 'Temporal anchor from which this scenario projects forward. All hypothetical values tagged to this scenario must have applicable periods strictly after base_date.';


--
-- Name: COLUMN "602_scen_scenarios".scenario_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."602_scen_scenarios".scenario_type IS 'Broad classification of this scenario. projection: general what-if or forward analysis. budget: governance-approved planning scenario — detail in gd_029_budgets. stress_test: downside or sensitivity scenario. base_case: reference baseline scenario.';


--
-- Name: COLUMN "602_scen_scenarios".scenario_status; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global."602_scen_scenarios".scenario_status IS 'Governance lifecycle status of this scenario. draft → approved → superseded/archived. Validated by fn_is_valid_scenario_status against gd_007_status_registry.';


--
-- Name: gd_001_events_event_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_001_events_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_001_events_event_id_seq OWNER TO postgres;

--
-- Name: gd_001_events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_001_events_event_id_seq OWNED BY global."301_evt_events".event_id;


--
-- Name: gd_002_primitive_transitions_primitive_transition_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_002_primitive_transitions_primitive_transition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_002_primitive_transitions_primitive_transition_id_seq OWNER TO postgres;

--
-- Name: gd_002_primitive_transitions_primitive_transition_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_002_primitive_transitions_primitive_transition_id_seq OWNED BY global."302_evt_primitive_transitions".primitive_transition_id;


--
-- Name: gd_004_entities_entity_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_004_entities_entity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_004_entities_entity_id_seq OWNER TO postgres;

--
-- Name: gd_004_entities_entity_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_004_entities_entity_id_seq OWNED BY global."001_core_entities".entity_id;


--
-- Name: gd_005_ruleset_lines_line_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_005_ruleset_lines_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_005_ruleset_lines_line_id_seq OWNER TO postgres;

--
-- Name: gd_005_ruleset_lines_line_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_005_ruleset_lines_line_id_seq OWNED BY global."203_fin_ruleset_lines".line_id;


--
-- Name: gd_006_commit_records_commit_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_006_commit_records_commit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_006_commit_records_commit_id_seq OWNER TO postgres;

--
-- Name: gd_006_commit_records_commit_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_006_commit_records_commit_id_seq OWNED BY global."104_gov_commits".commit_id;


--
-- Name: gd_008_governance_identities_governance_identity_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_008_governance_identities_governance_identity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_008_governance_identities_governance_identity_id_seq OWNER TO postgres;

--
-- Name: gd_008_governance_identities_governance_identity_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_008_governance_identities_governance_identity_id_seq OWNED BY global."101_gov_identities".governance_identity_id;


--
-- Name: gd_011_holidays_holiday_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_011_holidays_holiday_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_011_holidays_holiday_id_seq OWNER TO postgres;

--
-- Name: gd_011_holidays_holiday_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_011_holidays_holiday_id_seq OWNED BY global."410_cal_holidays".holiday_id;


--
-- Name: gd_012_currency_registry_currency_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_012_currency_registry_currency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_012_currency_registry_currency_id_seq OWNER TO postgres;

--
-- Name: gd_012_currency_registry_currency_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_012_currency_registry_currency_id_seq OWNED BY global."403_ref_currencies".currency_id;


--
-- Name: gd_013_people_person_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_013_people_person_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_013_people_person_id_seq OWNER TO postgres;

--
-- Name: gd_013_people_person_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_013_people_person_id_seq OWNED BY global."002_core_people".person_id;


--
-- Name: gd_014_inflation_rates_inflation_rate_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."402_ref_inflation_rates" ALTER COLUMN inflation_rate_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_014_inflation_rates_inflation_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_015_exchange_rates_rate_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_015_exchange_rates_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_015_exchange_rates_rate_id_seq OWNER TO postgres;

--
-- Name: gd_015_exchange_rates_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_015_exchange_rates_rate_id_seq OWNED BY global."401_ref_exchange_rates".rate_id;


--
-- Name: gd_017_naming_conventions_naming_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_017_naming_conventions_naming_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_017_naming_conventions_naming_id_seq OWNER TO postgres;

--
-- Name: gd_017_naming_conventions_naming_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_017_naming_conventions_naming_id_seq OWNED BY global."405_ref_names".naming_id;


--
-- Name: gd_020_scenarios_scenario_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."602_scen_scenarios" ALTER COLUMN scenario_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_020_scenarios_scenario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_021_proposals_proposal_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."102_gov_proposals" ALTER COLUMN proposal_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_021_proposals_proposal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_022_delegations_delegation_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."103_gov_delegations" ALTER COLUMN delegation_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_022_delegations_delegation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_025_projects_project_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."003_core_projects" ALTER COLUMN project_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_025_projects_project_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_026_teammembers_arrangement_id_seq1; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."501_hr_arrangements" ALTER COLUMN arrangement_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_026_teammembers_arrangement_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_027_positions_position_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global."502_hr_positions" ALTER COLUMN position_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_027_positions_position_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: view_001_gamma_deliverable; Type: VIEW; Schema: global; Owner: postgres
--

CREATE VIEW global.view_001_gamma_deliverable AS
 SELECT c.account_code,
    c.account_name,
    (p.valid_time)::date AS movement_date,
    p.event_id,
    p.primitive_transition_id,
    ccy.currency_code,
    (p.amount * global.fn_get_exchange_rate(p.currency_code, (ccy.currency_code)::bpchar, (p.valid_time)::date)) AS amount,
        CASE
            WHEN (((c.normal_balance = 'debit'::bpchar) AND ((p.transformation_direction)::text = 'increase'::text)) OR ((c.normal_balance = 'credit'::bpchar) AND ((p.transformation_direction)::text = 'decrease'::text))) THEN 'Dr'::text
            ELSE 'Cr'::text
        END AS accounting_move
   FROM ((global."302_evt_primitive_transitions" p
     JOIN global."201_fin_coa" c ON ((c.coa_id = p.coa_id)))
     CROSS JOIN ( VALUES ('UAH'::text), ('USD'::text)) ccy(currency_code))
  WHERE ((c.coa_set_code)::text = 'ua_psbo'::text)
  ORDER BY p.primitive_transition_id, ccy.currency_code;


ALTER VIEW global.view_001_gamma_deliverable OWNER TO postgres;

--
-- Name: 001_core_entities entity_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."001_core_entities" ALTER COLUMN entity_id SET DEFAULT nextval('global.gd_004_entities_entity_id_seq'::regclass);


--
-- Name: 002_core_people person_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."002_core_people" ALTER COLUMN person_id SET DEFAULT nextval('global.gd_013_people_person_id_seq'::regclass);


--
-- Name: 101_gov_identities governance_identity_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."101_gov_identities" ALTER COLUMN governance_identity_id SET DEFAULT nextval('global.gd_008_governance_identities_governance_identity_id_seq'::regclass);


--
-- Name: 104_gov_commits commit_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."104_gov_commits" ALTER COLUMN commit_id SET DEFAULT nextval('global.gd_006_commit_records_commit_id_seq'::regclass);


--
-- Name: 203_fin_ruleset_lines line_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."203_fin_ruleset_lines" ALTER COLUMN line_id SET DEFAULT nextval('global.gd_005_ruleset_lines_line_id_seq'::regclass);


--
-- Name: 301_evt_events event_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events" ALTER COLUMN event_id SET DEFAULT nextval('global.gd_001_events_event_id_seq'::regclass);


--
-- Name: 302_evt_primitive_transitions primitive_transition_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."302_evt_primitive_transitions" ALTER COLUMN primitive_transition_id SET DEFAULT nextval('global.gd_002_primitive_transitions_primitive_transition_id_seq'::regclass);


--
-- Name: 401_ref_exchange_rates rate_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."401_ref_exchange_rates" ALTER COLUMN rate_id SET DEFAULT nextval('global.gd_015_exchange_rates_rate_id_seq'::regclass);


--
-- Name: 403_ref_currencies currency_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."403_ref_currencies" ALTER COLUMN currency_id SET DEFAULT nextval('global.gd_012_currency_registry_currency_id_seq'::regclass);


--
-- Name: 405_ref_names naming_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."405_ref_names" ALTER COLUMN naming_id SET DEFAULT nextval('global.gd_017_naming_conventions_naming_id_seq'::regclass);


--
-- Name: 410_cal_holidays holiday_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."410_cal_holidays" ALTER COLUMN holiday_id SET DEFAULT nextval('global.gd_011_holidays_holiday_id_seq'::regclass);


--
-- Name: log log_pkey; Type: CONSTRAINT; Schema: audit; Owner: postgres
--

ALTER TABLE ONLY audit.log
    ADD CONSTRAINT log_pkey PRIMARY KEY (log_id);


--
-- Name: 105_gov_shareholdings 105_gov_shareholdings_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."105_gov_shareholdings"
    ADD CONSTRAINT "105_gov_shareholdings_pkey" PRIMARY KEY (shareholding_id);


--
-- Name: 411_ref_amortization_rates 411_ref_amortization_rates_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."411_ref_amortization_rates"
    ADD CONSTRAINT "411_ref_amortization_rates_pkey" PRIMARY KEY (rate_id);


--
-- Name: 301_evt_events gd_001_events_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_pk PRIMARY KEY (event_id);


--
-- Name: 301_evt_events gd_001_events_replay_sequence_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_replay_sequence_uq UNIQUE (replay_sequence);


--
-- Name: 302_evt_primitive_transitions gd_002_primitive_transitions_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."302_evt_primitive_transitions"
    ADD CONSTRAINT gd_002_primitive_transitions_pk PRIMARY KEY (primitive_transition_id);


--
-- Name: 001_core_entities gd_003_entities_entity_reg_number_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."001_core_entities"
    ADD CONSTRAINT gd_003_entities_entity_reg_number_uq UNIQUE (entity_reg_number);


--
-- Name: 001_core_entities gd_003_entities_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."001_core_entities"
    ADD CONSTRAINT gd_003_entities_pk PRIMARY KEY (entity_id);


--
-- Name: 401_ref_exchange_rates gd_004_exchange_rates_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."401_ref_exchange_rates"
    ADD CONSTRAINT gd_004_exchange_rates_pk PRIMARY KEY (rate_id);


--
-- Name: 401_ref_exchange_rates gd_004_exchange_rates_unique_rate; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."401_ref_exchange_rates"
    ADD CONSTRAINT gd_004_exchange_rates_unique_rate UNIQUE (rate_timestamp, base_currency, quote_currency, rate_code);


--
-- Name: 104_gov_commits gd_005_commit_records_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."104_gov_commits"
    ADD CONSTRAINT gd_005_commit_records_pk PRIMARY KEY (commit_id);


--
-- Name: 206_fin_allocation_rules gd_006_alloc_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."206_fin_allocation_rules"
    ADD CONSTRAINT gd_006_alloc_pk PRIMARY KEY (allocation_id);


--
-- Name: 407_ref_statuses gd_006_status_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."407_ref_statuses"
    ADD CONSTRAINT gd_006_status_registry_pk PRIMARY KEY (status_type, status_code);


--
-- Name: 002_core_people gd_007_people_person_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."002_core_people"
    ADD CONSTRAINT gd_007_people_person_code_uq UNIQUE (person_code);


--
-- Name: 002_core_people gd_007_people_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."002_core_people"
    ADD CONSTRAINT gd_007_people_pk PRIMARY KEY (person_id);


--
-- Name: 202_fin_rulesets gd_008_ruleset_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."202_fin_rulesets"
    ADD CONSTRAINT gd_008_ruleset_registry_pk PRIMARY KEY (ruleset_id);


--
-- Name: 203_fin_ruleset_lines gd_009_ruleset_lines_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."203_fin_ruleset_lines"
    ADD CONSTRAINT gd_009_ruleset_lines_pk PRIMARY KEY (line_id);


--
-- Name: 410_cal_holidays gd_011_holidays_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."410_cal_holidays"
    ADD CONSTRAINT gd_011_holidays_pk PRIMARY KEY (holiday_id);


--
-- Name: 410_cal_holidays gd_011_holidays_unique; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."410_cal_holidays"
    ADD CONSTRAINT gd_011_holidays_unique UNIQUE (country_code, holiday_date, holiday_type);


--
-- Name: 403_ref_currencies gd_012_currency_registry_iso_alpha_3_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."403_ref_currencies"
    ADD CONSTRAINT gd_012_currency_registry_iso_alpha_3_uq UNIQUE (iso_alpha_3);


--
-- Name: 403_ref_currencies gd_012_currency_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."403_ref_currencies"
    ADD CONSTRAINT gd_012_currency_registry_pk PRIMARY KEY (currency_id);


--
-- Name: 101_gov_identities gd_013_governance_identities_identity_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."101_gov_identities"
    ADD CONSTRAINT gd_013_governance_identities_identity_code_uq UNIQUE (identity_code);


--
-- Name: 101_gov_identities gd_013_governance_identities_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."101_gov_identities"
    ADD CONSTRAINT gd_013_governance_identities_pk PRIMARY KEY (governance_identity_id);


--
-- Name: 404_ref_rate_sources gd_014_rate_codes_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."404_ref_rate_sources"
    ADD CONSTRAINT gd_014_rate_codes_pkey PRIMARY KEY (rate_code);


--
-- Name: 405_ref_names gd_017_naming_conventions_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."405_ref_names"
    ADD CONSTRAINT gd_017_naming_conventions_pk PRIMARY KEY (naming_id);


--
-- Name: 405_ref_names gd_017_naming_conventions_unique; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."405_ref_names"
    ADD CONSTRAINT gd_017_naming_conventions_unique UNIQUE (object_type, object_ref, translation_language);


--
-- Name: 406_ref_pt_types gd_019_pt_types_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."406_ref_pt_types"
    ADD CONSTRAINT gd_019_pt_types_pkey PRIMARY KEY (pt_type_code);


--
-- Name: 602_scen_scenarios gd_020_scenarios_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."602_scen_scenarios"
    ADD CONSTRAINT gd_020_scenarios_pkey PRIMARY KEY (scenario_id);


--
-- Name: 602_scen_scenarios gd_020_scenarios_scenario_name_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."602_scen_scenarios"
    ADD CONSTRAINT gd_020_scenarios_scenario_name_uq UNIQUE (scenario_name);


--
-- Name: 102_gov_proposals gd_021_proposals_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."102_gov_proposals"
    ADD CONSTRAINT gd_021_proposals_pkey PRIMARY KEY (proposal_id);


--
-- Name: 103_gov_delegations gd_022_delegations_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."103_gov_delegations"
    ADD CONSTRAINT gd_022_delegations_pkey PRIMARY KEY (delegation_id);


--
-- Name: 408_ref_event_types gd_023_event_types_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."408_ref_event_types"
    ADD CONSTRAINT gd_023_event_types_pkey PRIMARY KEY (event_type_code);


--
-- Name: 410_ref_arrangement_types gd_024_legal_arrangement_types_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."410_ref_arrangement_types"
    ADD CONSTRAINT gd_024_legal_arrangement_types_pkey PRIMARY KEY (arrangement_type_code);


--
-- Name: 003_core_projects gd_025_projects_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."003_core_projects"
    ADD CONSTRAINT gd_025_projects_code_uq UNIQUE (project_code);


--
-- Name: 003_core_projects gd_025_projects_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."003_core_projects"
    ADD CONSTRAINT gd_025_projects_pkey PRIMARY KEY (project_id);


--
-- Name: 501_hr_arrangements gd_026_tm_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."501_hr_arrangements"
    ADD CONSTRAINT gd_026_tm_pkey PRIMARY KEY (arrangement_id);


--
-- Name: 502_hr_positions gd_027_positions_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."502_hr_positions"
    ADD CONSTRAINT gd_027_positions_pkey PRIMARY KEY (position_id);


--
-- Name: 409_ref_coa_account_types gd_028_coa_account_types_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."409_ref_coa_account_types"
    ADD CONSTRAINT gd_028_coa_account_types_pkey PRIMARY KEY (account_type_code);


--
-- Name: 201_fin_coa pk_fin_coa; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."201_fin_coa"
    ADD CONSTRAINT pk_fin_coa PRIMARY KEY (coa_id);


--
-- Name: 201_fin_coa uq_fin_coa_set_code; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."201_fin_coa"
    ADD CONSTRAINT uq_fin_coa_set_code UNIQUE (coa_set_code, account_code);


--
-- Name: 411_ref_amortization_rates uq_rate; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."411_ref_amortization_rates"
    ADD CONSTRAINT uq_rate UNIQUE (asset_category_code, jurisdiction, rate_basis, method);


--
-- Name: audit_log_performed_idx; Type: INDEX; Schema: audit; Owner: postgres
--

CREATE INDEX audit_log_performed_idx ON audit.log USING btree (performed_by_id, performed_at);


--
-- Name: audit_log_table_row_idx; Type: INDEX; Schema: audit; Owner: postgres
--

CREATE INDEX audit_log_table_row_idx ON audit.log USING btree (table_name, row_id);


--
-- Name: audit_log_timestamp_idx; Type: INDEX; Schema: audit; Owner: postgres
--

CREATE INDEX audit_log_timestamp_idx ON audit.log USING btree (performed_at);


--
-- Name: gd_001_events_assertion_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_assertion_time_idx ON global."301_evt_events" USING btree (assertion_time);


--
-- Name: gd_001_events_commit_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_commit_id_idx ON global."301_evt_events" USING btree (commit_id);


--
-- Name: gd_001_events_commit_replay_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_commit_replay_idx ON global."301_evt_events" USING btree (commit_id, replay_sequence);


--
-- Name: gd_001_events_corrective_of_event_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_corrective_of_event_id_idx ON global."301_evt_events" USING btree (corrective_of_event_id) WHERE (corrective_of_event_id IS NOT NULL);


--
-- Name: gd_001_events_entity_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_entity_id_idx ON global."301_evt_events" USING btree (entity_id);


--
-- Name: gd_001_events_entity_status_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_entity_status_time_idx ON global."301_evt_events" USING btree (entity_id, event_status, valid_time);


--
-- Name: gd_001_events_entity_time_committed_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_entity_time_committed_idx ON global."301_evt_events" USING btree (entity_id, valid_time) WHERE ((event_status)::text = 'committed'::text);


--
-- Name: gd_001_events_event_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_event_status_idx ON global."301_evt_events" USING btree (event_status);


--
-- Name: gd_001_events_event_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_event_type_idx ON global."301_evt_events" USING btree (event_type);


--
-- Name: gd_001_events_replay_sequence_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_replay_sequence_idx ON global."301_evt_events" USING btree (replay_sequence);


--
-- Name: gd_001_events_valid_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_valid_time_idx ON global."301_evt_events" USING btree (valid_time);


--
-- Name: gd_002_primitive_transitions_description_trgm_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_description_trgm_idx ON global."302_evt_primitive_transitions" USING gin (transition_description public.gin_trgm_ops) WHERE (transition_description IS NOT NULL);


--
-- Name: gd_002_primitive_transitions_entity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_entity_idx ON global."302_evt_primitive_transitions" USING btree (entity_id);


--
-- Name: gd_002_primitive_transitions_event_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_event_idx ON global."302_evt_primitive_transitions" USING btree (event_id);


--
-- Name: gd_002_primitive_transitions_valid_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_valid_time_idx ON global."302_evt_primitive_transitions" USING btree (valid_time);


--
-- Name: gd_003_entities_country_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_country_code_idx ON global."001_core_entities" USING btree (country_code);


--
-- Name: gd_003_entities_name_trgm_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_name_trgm_idx ON global."001_core_entities" USING gin (normalized_name public.gin_trgm_ops);


--
-- Name: gd_003_entities_tax_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_tax_id_idx ON global."001_core_entities" USING btree (tax_id);


--
-- Name: gd_003_entities_vat_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_vat_id_idx ON global."001_core_entities" USING btree (vat_id);


--
-- Name: gd_004_exchange_rates_currency_pair_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_004_exchange_rates_currency_pair_idx ON global."401_ref_exchange_rates" USING btree (base_currency, quote_currency);


--
-- Name: gd_004_exchange_rates_rate_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_004_exchange_rates_rate_code_idx ON global."401_ref_exchange_rates" USING btree (rate_code);


--
-- Name: gd_004_exchange_rates_timestamp_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_004_exchange_rates_timestamp_idx ON global."401_ref_exchange_rates" USING btree (rate_timestamp);


--
-- Name: gd_005_commit_records_commit_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_status_idx ON global."104_gov_commits" USING btree (commit_status);


--
-- Name: gd_005_commit_records_commit_timestamp_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_timestamp_idx ON global."104_gov_commits" USING btree (commit_timestamp);


--
-- Name: gd_005_commit_records_commit_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_type_idx ON global."104_gov_commits" USING btree (commit_type);


--
-- Name: gd_005_commit_records_committing_authority_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_committing_authority_id_idx ON global."104_gov_commits" USING btree (committing_authority_id);


--
-- Name: gd_005_ruleset_lines_entity_1_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_ruleset_lines_entity_1_id_idx ON global."203_fin_ruleset_lines" USING btree (entity_1_id) WHERE (entity_1_id IS NOT NULL);


--
-- Name: gd_005_ruleset_lines_entity_2_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_ruleset_lines_entity_2_id_idx ON global."203_fin_ruleset_lines" USING btree (entity_2_id) WHERE (entity_2_id IS NOT NULL);


--
-- Name: gd_005_ruleset_lines_ruleset_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_ruleset_lines_ruleset_validity_idx ON global."203_fin_ruleset_lines" USING btree (ruleset_id, valid_from, valid_to);


--
-- Name: gd_006_alloc_entity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_006_alloc_entity_idx ON global."206_fin_allocation_rules" USING btree (entity_id) WHERE (entity_id IS NOT NULL);


--
-- Name: gd_006_alloc_line_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_006_alloc_line_idx ON global."206_fin_allocation_rules" USING btree (line_id);


--
-- Name: gd_006_alloc_project_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_006_alloc_project_idx ON global."206_fin_allocation_rules" USING btree (project_id) WHERE (project_id IS NOT NULL);


--
-- Name: gd_006_alloc_ruleset_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_006_alloc_ruleset_idx ON global."206_fin_allocation_rules" USING btree (ruleset_id);


--
-- Name: gd_006_status_registry_status_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_006_status_registry_status_type_idx ON global."407_ref_statuses" USING btree (status_type);


--
-- Name: gd_007_people_country_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_country_code_idx ON global."002_core_people" USING btree (country_code);


--
-- Name: gd_007_people_last_name_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_last_name_idx ON global."002_core_people" USING btree (last_name);


--
-- Name: gd_007_people_tax_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_tax_id_idx ON global."002_core_people" USING btree (tax_id);


--
-- Name: gd_008_governance_identities_created_by_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_008_governance_identities_created_by_idx ON global."101_gov_identities" USING btree (created_by_identity_id) WHERE (created_by_identity_id IS NOT NULL);


--
-- Name: gd_008_governance_identities_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_008_governance_identities_validity_idx ON global."101_gov_identities" USING btree (valid_from, valid_to);


--
-- Name: gd_009_ruleset_lines_ruleset_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_009_ruleset_lines_ruleset_id_idx ON global."203_fin_ruleset_lines" USING btree (ruleset_id);


--
-- Name: gd_009_ruleset_lines_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_009_ruleset_lines_validity_idx ON global."203_fin_ruleset_lines" USING btree (valid_from, valid_to);


--
-- Name: gd_011_holidays_country_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_011_holidays_country_idx ON global."410_cal_holidays" USING btree (country_code);


--
-- Name: gd_011_holidays_date_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_011_holidays_date_idx ON global."410_cal_holidays" USING btree (holiday_date);


--
-- Name: gd_011_holidays_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_011_holidays_type_idx ON global."410_cal_holidays" USING btree (holiday_type);


--
-- Name: gd_012_currency_registry_alpha2_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_012_currency_registry_alpha2_idx ON global."403_ref_currencies" USING btree (iso_alpha_2);


--
-- Name: gd_012_currency_registry_alpha3_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_012_currency_registry_alpha3_idx ON global."403_ref_currencies" USING btree (iso_alpha_3);


--
-- Name: gd_013_governance_identities_identity_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_identity_status_idx ON global."101_gov_identities" USING btree (identity_status);


--
-- Name: gd_013_governance_identities_identity_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_identity_type_idx ON global."101_gov_identities" USING btree (identity_type);


--
-- Name: gd_013_governance_identities_valid_from_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_valid_from_idx ON global."101_gov_identities" USING btree (valid_from);


--
-- Name: gd_013_governance_identities_valid_to_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_valid_to_idx ON global."101_gov_identities" USING btree (valid_to);


--
-- Name: gd_015_exchange_rates_pair_time_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_015_exchange_rates_pair_time_code_idx ON global."401_ref_exchange_rates" USING btree (base_currency, quote_currency, rate_timestamp, rate_code);


--
-- Name: gd_016_coa_account_name_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_016_coa_account_name_idx ON global."201_fin_coa" USING btree (account_name) WHERE (account_name IS NOT NULL);


--
-- Name: gd_016_coa_account_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_016_coa_account_type_idx ON global."201_fin_coa" USING btree (account_type) WHERE (account_type IS NOT NULL);


--
-- Name: gd_017_naming_conventions_language_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_017_naming_conventions_language_idx ON global."405_ref_names" USING btree (translation_language);


--
-- Name: gd_017_naming_conventions_object_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_017_naming_conventions_object_idx ON global."405_ref_names" USING btree (object_type, object_ref);


--
-- Name: gd_020_scenarios_base_date_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_020_scenarios_base_date_idx ON global."602_scen_scenarios" USING btree (base_date);


--
-- Name: gd_020_scenarios_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_020_scenarios_status_idx ON global."602_scen_scenarios" USING btree (scenario_status);


--
-- Name: gd_020_scenarios_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_020_scenarios_type_idx ON global."602_scen_scenarios" USING btree (scenario_type);


--
-- Name: gd_021_proposals_entity_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_entity_id_idx ON global."102_gov_proposals" USING btree (entity_id);


--
-- Name: gd_021_proposals_payload_gin_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_payload_gin_idx ON global."102_gov_proposals" USING gin (proposal_payload);


--
-- Name: gd_021_proposals_scenario_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_scenario_id_idx ON global."102_gov_proposals" USING btree (scenario_id);


--
-- Name: gd_021_proposals_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_status_idx ON global."102_gov_proposals" USING btree (proposal_status);


--
-- Name: gd_021_proposals_type_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_type_status_idx ON global."102_gov_proposals" USING btree (proposal_type, proposal_status);


--
-- Name: gd_022_delegations_delegatee_active_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_delegatee_active_idx ON global."103_gov_delegations" USING btree (delegatee_id, delegation_scope, valid_from, valid_to) WHERE (revoked_at IS NULL);


--
-- Name: gd_022_delegations_delegator_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_delegator_idx ON global."103_gov_delegations" USING btree (delegator_id);


--
-- Name: gd_022_delegations_entity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_entity_idx ON global."103_gov_delegations" USING btree (entity_id) WHERE (entity_id IS NOT NULL);


--
-- Name: gd_022_delegations_temporal_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_temporal_idx ON global."103_gov_delegations" USING btree (valid_from, valid_to);


--
-- Name: gd_024_lat_category_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_024_lat_category_idx ON global."410_ref_arrangement_types" USING btree (arrangement_category);


--
-- Name: gd_024_lat_jurisdiction_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_024_lat_jurisdiction_idx ON global."410_ref_arrangement_types" USING btree (jurisdiction_code) WHERE (jurisdiction_code IS NOT NULL);


--
-- Name: gd_025_projects_owner_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_025_projects_owner_idx ON global."003_core_projects" USING btree (project_owner_arrangement_id) WHERE (project_owner_arrangement_id IS NOT NULL);


--
-- Name: gd_025_projects_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_025_projects_validity_idx ON global."003_core_projects" USING btree (valid_from, valid_to);


--
-- Name: gd_026_tm_entity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_entity_idx ON global."501_hr_arrangements" USING btree (entity_id) WHERE (entity_id IS NOT NULL);


--
-- Name: gd_026_tm_person_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_person_idx ON global."501_hr_arrangements" USING btree (person_id);


--
-- Name: gd_026_tm_position_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_position_idx ON global."501_hr_arrangements" USING btree (position_id) WHERE (position_id IS NOT NULL);


--
-- Name: gd_026_tm_project_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_project_idx ON global."501_hr_arrangements" USING btree (project_id) WHERE (project_id IS NOT NULL);


--
-- Name: gd_026_tm_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_validity_idx ON global."501_hr_arrangements" USING btree (valid_from, valid_to);


--
-- Name: gd_027_positions_class_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_class_idx ON global."502_hr_positions" USING btree (position_class);


--
-- Name: gd_027_positions_entity_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_entity_id_idx ON global."502_hr_positions" USING btree (entity_id) WHERE (entity_id IS NOT NULL);


--
-- Name: gd_027_positions_name_entity_uq; Type: INDEX; Schema: global; Owner: postgres
--

CREATE UNIQUE INDEX gd_027_positions_name_entity_uq ON global."502_hr_positions" USING btree (position_name, position_class, entity_id) WHERE ((entity_id IS NOT NULL) AND (project_id IS NULL));


--
-- Name: gd_027_positions_name_project_uq; Type: INDEX; Schema: global; Owner: postgres
--

CREATE UNIQUE INDEX gd_027_positions_name_project_uq ON global."502_hr_positions" USING btree (position_name, position_class, project_id) WHERE (project_id IS NOT NULL);


--
-- Name: gd_027_positions_name_universal_uq; Type: INDEX; Schema: global; Owner: postgres
--

CREATE UNIQUE INDEX gd_027_positions_name_universal_uq ON global."502_hr_positions" USING btree (position_name, position_class) WHERE ((project_id IS NULL) AND (entity_id IS NULL));


--
-- Name: gd_027_positions_project_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_project_id_idx ON global."502_hr_positions" USING btree (project_id) WHERE (project_id IS NOT NULL);


--
-- Name: gd_027_positions_superior_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_superior_idx ON global."502_hr_positions" USING btree (position_superior_id) WHERE (position_superior_id IS NOT NULL);


--
-- Name: gd_027_positions_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_validity_idx ON global."502_hr_positions" USING btree (valid_from, valid_to);


--
-- Name: idx_shareholdings_entity; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX idx_shareholdings_entity ON global."105_gov_shareholdings" USING btree (entity_id, valid_from);


--
-- Name: idx_shareholdings_identity; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX idx_shareholdings_identity ON global."105_gov_shareholdings" USING btree (governance_identity_id);


--
-- Name: 001_core_entities trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."001_core_entities" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('entity_id');


--
-- Name: 002_core_people trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."002_core_people" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('person_id');


--
-- Name: 003_core_projects trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."003_core_projects" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('project_id');


--
-- Name: 101_gov_identities trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."101_gov_identities" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('governance_identity_id');


--
-- Name: 102_gov_proposals trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."102_gov_proposals" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('proposal_id');


--
-- Name: 103_gov_delegations trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."103_gov_delegations" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('delegation_id');


--
-- Name: 104_gov_commits trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."104_gov_commits" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('commit_id');


--
-- Name: 105_gov_shareholdings trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."105_gov_shareholdings" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('shareholding_id');


--
-- Name: 201_fin_coa trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."201_fin_coa" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('account_code');


--
-- Name: 202_fin_rulesets trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."202_fin_rulesets" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('ruleset_id');


--
-- Name: 203_fin_ruleset_lines trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."203_fin_ruleset_lines" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('line_id');


--
-- Name: 302_evt_primitive_transitions trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."302_evt_primitive_transitions" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('primitive_transition_id');


--
-- Name: 401_ref_exchange_rates trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."401_ref_exchange_rates" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('rate_id');


--
-- Name: 402_ref_inflation_rates trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."402_ref_inflation_rates" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('inflation_rate_id');


--
-- Name: 403_ref_currencies trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."403_ref_currencies" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('currency_id');


--
-- Name: 404_ref_rate_sources trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."404_ref_rate_sources" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('rate_code');


--
-- Name: 405_ref_names trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."405_ref_names" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('naming_id');


--
-- Name: 406_ref_pt_types trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."406_ref_pt_types" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('pt_type_code');


--
-- Name: 407_ref_statuses trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."407_ref_statuses" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('status_code');


--
-- Name: 408_ref_event_types trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."408_ref_event_types" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('event_type_code');


--
-- Name: 409_ref_coa_account_types trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."409_ref_coa_account_types" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('account_type_code');


--
-- Name: 410_cal_holidays trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."410_cal_holidays" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('holiday_id');


--
-- Name: 410_ref_arrangement_types trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."410_ref_arrangement_types" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('arrangement_type_code');


--
-- Name: 501_hr_arrangements trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."501_hr_arrangements" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('arrangement_id');


--
-- Name: 502_hr_positions trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."502_hr_positions" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('position_id');


--
-- Name: 602_scen_scenarios trg_audit; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON global."602_scen_scenarios" FOR EACH ROW EXECUTE FUNCTION audit.fn_log_mutation('scenario_id');


--
-- Name: 301_evt_events trg_generate_primitives; Type: TRIGGER; Schema: global; Owner: postgres
--

CREATE TRIGGER trg_generate_primitives AFTER INSERT OR UPDATE OF event_status ON global."301_evt_events" FOR EACH ROW EXECUTE FUNCTION global.fn_generate_primitives();


--
-- Name: 105_gov_shareholdings 105_gov_shareholdings_entity_id_fkey; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."105_gov_shareholdings"
    ADD CONSTRAINT "105_gov_shareholdings_entity_id_fkey" FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id);


--
-- Name: 105_gov_shareholdings 105_gov_shareholdings_governance_identity_id_fkey; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."105_gov_shareholdings"
    ADD CONSTRAINT "105_gov_shareholdings_governance_identity_id_fkey" FOREIGN KEY (governance_identity_id) REFERENCES global."101_gov_identities"(governance_identity_id);


--
-- Name: 203_fin_ruleset_lines 203_fin_ruleset_lines_coa_id_fkey; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."203_fin_ruleset_lines"
    ADD CONSTRAINT "203_fin_ruleset_lines_coa_id_fkey" FOREIGN KEY (coa_id) REFERENCES global."201_fin_coa"(coa_id);


--
-- Name: 302_evt_primitive_transitions 302_evt_primitive_transitions_coa_id_fkey; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."302_evt_primitive_transitions"
    ADD CONSTRAINT "302_evt_primitive_transitions_coa_id_fkey" FOREIGN KEY (coa_id) REFERENCES global."201_fin_coa"(coa_id);


--
-- Name: 602_scen_scenarios 602_scen_scenarios_entity_id_fkey; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."602_scen_scenarios"
    ADD CONSTRAINT "602_scen_scenarios_entity_id_fkey" FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id);


--
-- Name: 602_scen_scenarios 602_scen_scenarios_superseded_by_scenario_id_fkey; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."602_scen_scenarios"
    ADD CONSTRAINT "602_scen_scenarios_superseded_by_scenario_id_fkey" FOREIGN KEY (superseded_by_scenario_id) REFERENCES global."602_scen_scenarios"(scenario_id);


--
-- Name: 201_fin_coa fk_fin_coa_parent; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."201_fin_coa"
    ADD CONSTRAINT fk_fin_coa_parent FOREIGN KEY (parent_coa_id) REFERENCES global."201_fin_coa"(coa_id);


--
-- Name: 301_evt_events gd_001_events_commit_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_commit_id_fk FOREIGN KEY (commit_id) REFERENCES global."104_gov_commits"(commit_id);


--
-- Name: 301_evt_events gd_001_events_corrective_of_event_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_corrective_of_event_fk FOREIGN KEY (corrective_of_event_id) REFERENCES global."301_evt_events"(event_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 301_evt_events gd_001_events_entity_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_entity_id_fk FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 301_evt_events gd_001_events_event_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_event_type_fk FOREIGN KEY (event_type) REFERENCES global."408_ref_event_types"(event_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 301_evt_events gd_001_events_governance_scope_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_governance_scope_fk FOREIGN KEY (governance_scope_id) REFERENCES global."101_gov_identities"(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 301_evt_events gd_001_events_scenario_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."301_evt_events"
    ADD CONSTRAINT gd_001_events_scenario_id_fk FOREIGN KEY (scenario_id) REFERENCES global."602_scen_scenarios"(scenario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 302_evt_primitive_transitions gd_002_primitive_transitions_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."302_evt_primitive_transitions"
    ADD CONSTRAINT gd_002_primitive_transitions_entity_fk FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id);


--
-- Name: 302_evt_primitive_transitions gd_002_primitive_transitions_event_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."302_evt_primitive_transitions"
    ADD CONSTRAINT gd_002_primitive_transitions_event_fk FOREIGN KEY (event_id) REFERENCES global."301_evt_events"(event_id);


--
-- Name: 302_evt_primitive_transitions gd_002_primitive_transitions_scenario_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."302_evt_primitive_transitions"
    ADD CONSTRAINT gd_002_primitive_transitions_scenario_id_fk FOREIGN KEY (scenario_id) REFERENCES global."602_scen_scenarios"(scenario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 302_evt_primitive_transitions gd_002_primitive_transitions_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."302_evt_primitive_transitions"
    ADD CONSTRAINT gd_002_primitive_transitions_type_fk FOREIGN KEY (primitive_transition_type) REFERENCES global."406_ref_pt_types"(pt_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 202_fin_rulesets gd_003_ruleset_registry_governance_scope_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."202_fin_rulesets"
    ADD CONSTRAINT gd_003_ruleset_registry_governance_scope_fk FOREIGN KEY (governance_scope_id) REFERENCES global."101_gov_identities"(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 104_gov_commits gd_005_commit_records_committing_authority_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."104_gov_commits"
    ADD CONSTRAINT gd_005_commit_records_committing_authority_id_fk FOREIGN KEY (committing_authority_id) REFERENCES global."101_gov_identities"(governance_identity_id);


--
-- Name: 203_fin_ruleset_lines gd_005_ruleset_lines_entity_1_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."203_fin_ruleset_lines"
    ADD CONSTRAINT gd_005_ruleset_lines_entity_1_fk FOREIGN KEY (entity_1_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 203_fin_ruleset_lines gd_005_ruleset_lines_entity_2_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."203_fin_ruleset_lines"
    ADD CONSTRAINT gd_005_ruleset_lines_entity_2_fk FOREIGN KEY (entity_2_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 203_fin_ruleset_lines gd_005_ruleset_lines_event_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."203_fin_ruleset_lines"
    ADD CONSTRAINT gd_005_ruleset_lines_event_type_fk FOREIGN KEY (event_type) REFERENCES global."408_ref_event_types"(event_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 206_fin_allocation_rules gd_006_alloc_coa_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."206_fin_allocation_rules"
    ADD CONSTRAINT gd_006_alloc_coa_fk FOREIGN KEY (coa_id) REFERENCES global."201_fin_coa"(coa_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 206_fin_allocation_rules gd_006_alloc_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."206_fin_allocation_rules"
    ADD CONSTRAINT gd_006_alloc_entity_fk FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 206_fin_allocation_rules gd_006_alloc_line_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."206_fin_allocation_rules"
    ADD CONSTRAINT gd_006_alloc_line_fk FOREIGN KEY (line_id) REFERENCES global."203_fin_ruleset_lines"(line_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 206_fin_allocation_rules gd_006_alloc_project_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."206_fin_allocation_rules"
    ADD CONSTRAINT gd_006_alloc_project_fk FOREIGN KEY (project_id) REFERENCES global."003_core_projects"(project_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 206_fin_allocation_rules gd_006_alloc_ruleset_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."206_fin_allocation_rules"
    ADD CONSTRAINT gd_006_alloc_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES global."202_fin_rulesets"(ruleset_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 101_gov_identities gd_008_governance_identities_created_by_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."101_gov_identities"
    ADD CONSTRAINT gd_008_governance_identities_created_by_fk FOREIGN KEY (created_by_identity_id) REFERENCES global."101_gov_identities"(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 101_gov_identities gd_008_governance_identities_person_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."101_gov_identities"
    ADD CONSTRAINT gd_008_governance_identities_person_fk FOREIGN KEY (person_id) REFERENCES global."002_core_people"(person_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 203_fin_ruleset_lines gd_009_ruleset_lines_ruleset_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."203_fin_ruleset_lines"
    ADD CONSTRAINT gd_009_ruleset_lines_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES global."202_fin_rulesets"(ruleset_id);


--
-- Name: 402_ref_inflation_rates gd_014_inflation_rates_currency_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."402_ref_inflation_rates"
    ADD CONSTRAINT gd_014_inflation_rates_currency_fk FOREIGN KEY (currency_code) REFERENCES global."403_ref_currencies"(iso_alpha_3) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 402_ref_inflation_rates gd_014_inflation_rates_rate_reference_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."402_ref_inflation_rates"
    ADD CONSTRAINT gd_014_inflation_rates_rate_reference_fk FOREIGN KEY (rate_reference) REFERENCES global."404_ref_rate_sources"(rate_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 401_ref_exchange_rates gd_015_exchange_rates_base_currency_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."401_ref_exchange_rates"
    ADD CONSTRAINT gd_015_exchange_rates_base_currency_fk FOREIGN KEY (base_currency) REFERENCES global."403_ref_currencies"(iso_alpha_3) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 401_ref_exchange_rates gd_015_exchange_rates_quote_currency_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."401_ref_exchange_rates"
    ADD CONSTRAINT gd_015_exchange_rates_quote_currency_fk FOREIGN KEY (quote_currency) REFERENCES global."403_ref_currencies"(iso_alpha_3) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 401_ref_exchange_rates gd_015_exchange_rates_rate_code_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."401_ref_exchange_rates"
    ADD CONSTRAINT gd_015_exchange_rates_rate_code_fk FOREIGN KEY (rate_code) REFERENCES global."404_ref_rate_sources"(rate_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 201_fin_coa gd_016_coa_account_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."201_fin_coa"
    ADD CONSTRAINT gd_016_coa_account_type_fk FOREIGN KEY (account_type) REFERENCES global."409_ref_coa_account_types"(account_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 102_gov_proposals gd_021_proposals_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."102_gov_proposals"
    ADD CONSTRAINT gd_021_proposals_entity_fk FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 102_gov_proposals gd_021_proposals_scenario_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."102_gov_proposals"
    ADD CONSTRAINT gd_021_proposals_scenario_fk FOREIGN KEY (scenario_id) REFERENCES global."602_scen_scenarios"(scenario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 102_gov_proposals gd_021_proposals_superseded_by_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."102_gov_proposals"
    ADD CONSTRAINT gd_021_proposals_superseded_by_fk FOREIGN KEY (superseded_by) REFERENCES global."102_gov_proposals"(proposal_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 103_gov_delegations gd_022_delegations_delegatee_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."103_gov_delegations"
    ADD CONSTRAINT gd_022_delegations_delegatee_fk FOREIGN KEY (delegatee_id) REFERENCES global."101_gov_identities"(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 103_gov_delegations gd_022_delegations_delegator_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."103_gov_delegations"
    ADD CONSTRAINT gd_022_delegations_delegator_fk FOREIGN KEY (delegator_id) REFERENCES global."101_gov_identities"(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 103_gov_delegations gd_022_delegations_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."103_gov_delegations"
    ADD CONSTRAINT gd_022_delegations_entity_fk FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 501_hr_arrangements gd_026_tm_arrangement_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."501_hr_arrangements"
    ADD CONSTRAINT gd_026_tm_arrangement_type_fk FOREIGN KEY (arrangement_type_code) REFERENCES global."410_ref_arrangement_types"(arrangement_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 501_hr_arrangements gd_026_tm_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."501_hr_arrangements"
    ADD CONSTRAINT gd_026_tm_entity_fk FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 501_hr_arrangements gd_026_tm_person_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."501_hr_arrangements"
    ADD CONSTRAINT gd_026_tm_person_fk FOREIGN KEY (person_id) REFERENCES global."002_core_people"(person_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 501_hr_arrangements gd_026_tm_position_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."501_hr_arrangements"
    ADD CONSTRAINT gd_026_tm_position_fk FOREIGN KEY (position_id) REFERENCES global."502_hr_positions"(position_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 501_hr_arrangements gd_026_tm_project_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."501_hr_arrangements"
    ADD CONSTRAINT gd_026_tm_project_fk FOREIGN KEY (project_id) REFERENCES global."003_core_projects"(project_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 502_hr_positions gd_027_positions_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."502_hr_positions"
    ADD CONSTRAINT gd_027_positions_entity_fk FOREIGN KEY (entity_id) REFERENCES global."001_core_entities"(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: 502_hr_positions gd_027_positions_project_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global."502_hr_positions"
    ADD CONSTRAINT gd_027_positions_project_fk FOREIGN KEY (project_id) REFERENCES global."003_core_projects"(project_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict bDDWb3XiGeN28BMkQpPxveU3fAV9pNMarPNhlV5BZlGk0eGVTd3AcxdJSoQQ4Wq

