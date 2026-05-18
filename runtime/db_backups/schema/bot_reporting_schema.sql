--
-- PostgreSQL database dump
--

\restrict ZtiZKIj1buVneTvPKsHvEuQMHxEJyaPYfo3trGDcfWIWR2LNK2UshLypMXxAv5i

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
-- Name: audit; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA audit;


--
-- Name: bot_instructions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bot_instructions;


--
-- Name: bot_memory; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bot_memory;


--
-- Name: bteam; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bteam;


--
-- Name: diagnostic; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA diagnostic;


--
-- Name: findo; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA findo;


--
-- Name: glob; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA glob;


--
-- Name: modelprod; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA modelprod;


--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: fn_log_change(); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.fn_log_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_row_id bigint;
    v_pk_col text;
    v_data   jsonb;
BEGIN
    -- Use OLD for DELETE, NEW for INSERT/UPDATE
    IF TG_OP = 'DELETE' THEN
        v_data := to_jsonb(OLD);
    ELSE
        v_data := to_jsonb(NEW);
    END IF;

    -- Dynamically find the primary key column name
    SELECT kcu.column_name INTO v_pk_col
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'PRIMARY KEY'
        AND tc.table_schema = TG_TABLE_SCHEMA
        AND tc.table_name  = TG_TABLE_NAME
    LIMIT 1;

    IF v_pk_col IS NOT NULL THEN
        v_row_id := (v_data->>v_pk_col)::bigint;
    ELSE
        v_row_id := -1;
    END IF;

    INSERT INTO audit.aw_001_audit_log
        (table_name, row_id, operation_type, changed_at, changed_by)
    VALUES
        (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
         v_row_id,
         TG_OP,
         now(),
         current_user);

    -- Return correct value based on operation
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


--
-- Name: fill_rate_gaps(text, text, text); Type: FUNCTION; Schema: glob; Owner: -
--

CREATE FUNCTION glob.fill_rate_gaps(p_base_currency text, p_quote_currency text, p_rate_code text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_inserted INT := 0;
    v_start_date DATE := '2021-01-01';
    v_end_date DATE := '2025-12-31';
BEGIN
    INSERT INTO glob.gd_004_exchange_rates
        (rate_date, base_currency, quote_currency, rate_value, rate_code)
    SELECT
        c.calendar_date,
        p_base_currency,
        p_quote_currency,
        COALESCE(
            -- average of prev and next if both exist
            (
                (SELECT rate_value FROM glob.gd_004_exchange_rates
                 WHERE base_currency = p_base_currency
                   AND quote_currency = p_quote_currency
                   AND rate_code = p_rate_code
                   AND rate_date < c.calendar_date
                 ORDER BY rate_date DESC LIMIT 1)
                +
                (SELECT rate_value FROM glob.gd_004_exchange_rates
                 WHERE base_currency = p_base_currency
                   AND quote_currency = p_quote_currency
                   AND rate_code = p_rate_code
                   AND rate_date > c.calendar_date
                 ORDER BY rate_date ASC LIMIT 1)
            ) / 2.0,
            -- fallback: next rate only (leading gap)
            (SELECT rate_value FROM glob.gd_004_exchange_rates
             WHERE base_currency = p_base_currency
               AND quote_currency = p_quote_currency
               AND rate_code = p_rate_code
               AND rate_date > c.calendar_date
             ORDER BY rate_date ASC LIMIT 1),
            -- fallback: prev rate only (trailing gap)
            (SELECT rate_value FROM glob.gd_004_exchange_rates
             WHERE base_currency = p_base_currency
               AND quote_currency = p_quote_currency
               AND rate_code = p_rate_code
               AND rate_date < c.calendar_date
             ORDER BY rate_date DESC LIMIT 1)
        ),
        p_rate_code
    FROM glob.gd_001_calendar c
    WHERE c.calendar_date BETWEEN v_start_date AND v_end_date
      AND NOT EXISTS (
          SELECT 1 FROM glob.gd_004_exchange_rates r
          WHERE r.base_currency = p_base_currency
            AND r.quote_currency = p_quote_currency
            AND r.rate_code = p_rate_code
            AND r.rate_date = c.calendar_date
      )
    ON CONFLICT (rate_date, base_currency, quote_currency, rate_code)
    DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: aw_001_audit_log; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.aw_001_audit_log (
    audit_id bigint NOT NULL,
    table_name text NOT NULL,
    row_id bigint NOT NULL,
    operation_type text NOT NULL,
    changed_at timestamp without time zone DEFAULT now() NOT NULL,
    changed_by text
);


--
-- Name: aw_001_audit_log_audit_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.aw_001_audit_log ALTER COLUMN audit_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME audit.aw_001_audit_log_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: instructions; Type: TABLE; Schema: bot_instructions; Owner: -
--

CREATE TABLE bot_instructions.instructions (
    id bigint NOT NULL,
    instruction_name text NOT NULL,
    always_on boolean DEFAULT false NOT NULL,
    instruction_text text NOT NULL,
    active_from date DEFAULT CURRENT_DATE NOT NULL,
    active_to date
);


--
-- Name: instructions_id_seq; Type: SEQUENCE; Schema: bot_instructions; Owner: -
--

CREATE SEQUENCE bot_instructions.instructions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: instructions_id_seq; Type: SEQUENCE OWNED BY; Schema: bot_instructions; Owner: -
--

ALTER SEQUENCE bot_instructions.instructions_id_seq OWNED BY bot_instructions.instructions.id;


--
-- Name: conversations; Type: TABLE; Schema: bot_memory; Owner: -
--

CREATE TABLE bot_memory.conversations (
    id bigint NOT NULL,
    chat_id text NOT NULL,
    role text NOT NULL,
    content text NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: conversations_id_seq; Type: SEQUENCE; Schema: bot_memory; Owner: -
--

CREATE SEQUENCE bot_memory.conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: bot_memory; Owner: -
--

ALTER SEQUENCE bot_memory.conversations_id_seq OWNED BY bot_memory.conversations.id;


--
-- Name: d_010_unit_entities; Type: TABLE; Schema: bteam; Owner: -
--

CREATE TABLE bteam.d_010_unit_entities (
    unit_entity_id bigint NOT NULL,
    entity_id text NOT NULL,
    entity_role text NOT NULL
);


--
-- Name: d_010_unit_entities_unit_entity_id_seq; Type: SEQUENCE; Schema: bteam; Owner: -
--

CREATE SEQUENCE bteam.d_010_unit_entities_unit_entity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: d_010_unit_entities_unit_entity_id_seq; Type: SEQUENCE OWNED BY; Schema: bteam; Owner: -
--

ALTER SEQUENCE bteam.d_010_unit_entities_unit_entity_id_seq OWNED BY bteam.d_010_unit_entities.unit_entity_id;


--
-- Name: e_001_events_registry; Type: TABLE; Schema: bteam; Owner: -
--

CREATE TABLE bteam.e_001_events_registry (
    event_id bigint NOT NULL,
    event_date date NOT NULL,
    entity_1_id bigint NOT NULL,
    entity_2_id bigint NOT NULL,
    amount numeric NOT NULL,
    currency_code character(3) NOT NULL,
    raw_description text,
    operation_id bigint,
    origin_object_type text NOT NULL,
    origin_object_id bigint,
    document_id bigint,
    CONSTRAINT chk_bteam_origin_object_type CHECK ((origin_object_type = ANY (ARRAY['LOGICAL_DOCUMENT_OBJECT'::text, 'RULE_APPLICATION_INSTANCE'::text])))
);


--
-- Name: e_001_events_registry_event_id_seq; Type: SEQUENCE; Schema: bteam; Owner: -
--

ALTER TABLE bteam.e_001_events_registry ALTER COLUMN event_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME bteam.e_001_events_registry_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: e_002_entries; Type: TABLE; Schema: bteam; Owner: -
--

CREATE TABLE bteam.e_002_entries (
    event_id integer NOT NULL,
    ruleset_id text NOT NULL,
    recon_date_automatic date NOT NULL,
    recon_date_reviewed date,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    entry_id character varying NOT NULL,
    amount numeric,
    currency_code text,
    recon_note character varying,
    CONSTRAINT e_002_recon_dates_status_chk CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('accepted'::character varying)::text, ('overridden'::character varying)::text])))
);


--
-- Name: e_002_recon_dates; Type: TABLE; Schema: bteam; Owner: -
--

CREATE TABLE bteam.e_002_recon_dates (
    event_id integer NOT NULL,
    ruleset_id text NOT NULL,
    recon_date_automatic date NOT NULL,
    recon_date_reviewed date,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    CONSTRAINT e_002_recon_dates_status_chk CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'overridden'::character varying])::text[])))
);


--
-- Name: test_data; Type: TABLE; Schema: diagnostic; Owner: -
--

CREATE TABLE diagnostic.test_data (
    message_id character varying,
    message character varying
);


--
-- Name: d_011_economic_operations; Type: TABLE; Schema: findo; Owner: -
--

CREATE TABLE findo.d_011_economic_operations (
    operation_id bigint NOT NULL,
    operation_code text NOT NULL,
    operation_name text NOT NULL
);


--
-- Name: d_011_economic_operations_operation_id_seq; Type: SEQUENCE; Schema: findo; Owner: -
--

CREATE SEQUENCE findo.d_011_economic_operations_operation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: d_011_economic_operations_operation_id_seq; Type: SEQUENCE OWNED BY; Schema: findo; Owner: -
--

ALTER SEQUENCE findo.d_011_economic_operations_operation_id_seq OWNED BY findo.d_011_economic_operations.operation_id;


--
-- Name: d_012_operation_catchstrings; Type: TABLE; Schema: findo; Owner: -
--

CREATE TABLE findo.d_012_operation_catchstrings (
    catchstring_id bigint NOT NULL,
    operation_id bigint NOT NULL,
    catchstring text NOT NULL
);


--
-- Name: d_012_operation_catchstrings_catchstring_id_seq; Type: SEQUENCE; Schema: findo; Owner: -
--

CREATE SEQUENCE findo.d_012_operation_catchstrings_catchstring_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: d_012_operation_catchstrings_catchstring_id_seq; Type: SEQUENCE OWNED BY; Schema: findo; Owner: -
--

ALTER SEQUENCE findo.d_012_operation_catchstrings_catchstring_id_seq OWNED BY findo.d_012_operation_catchstrings.catchstring_id;


--
-- Name: e_001_events_registry; Type: TABLE; Schema: findo; Owner: -
--

CREATE TABLE findo.e_001_events_registry (
    event_id bigint NOT NULL,
    event_date date NOT NULL,
    entity_1_id bigint NOT NULL,
    entity_2_id bigint NOT NULL,
    amount numeric NOT NULL,
    currency_code character(3) NOT NULL,
    raw_description text,
    operation_id bigint,
    origin_object_type text NOT NULL,
    origin_object_id bigint,
    document_id bigint,
    CONSTRAINT chk_findo_origin_object_type CHECK ((origin_object_type = ANY (ARRAY['LOGICAL_DOCUMENT_OBJECT'::text, 'RULE_APPLICATION_INSTANCE'::text])))
);


--
-- Name: e_001_events_registry_event_id_seq; Type: SEQUENCE; Schema: findo; Owner: -
--

ALTER TABLE findo.e_001_events_registry ALTER COLUMN event_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME findo.e_001_events_registry_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: e_002_entries; Type: TABLE; Schema: findo; Owner: -
--

CREATE TABLE findo.e_002_entries (
    event_id bigint CONSTRAINT e_002_recon_dates_event_id_not_null NOT NULL,
    ruleset_id text CONSTRAINT e_002_recon_dates_ruleset_id_not_null NOT NULL,
    recon_date_automatic date CONSTRAINT e_002_recon_dates_recon_date_automatic_not_null NOT NULL,
    recon_date_reviewed date,
    status character varying DEFAULT 'pending'::character varying CONSTRAINT e_002_recon_dates_status_not_null NOT NULL,
    entry_id character varying NOT NULL,
    amount numeric,
    currency_code text,
    recon_note character varying,
    CONSTRAINT e_002_recon_dates_status_chk CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'overridden'::character varying])::text[])))
);


--
-- Name: gd_001_calendar; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_001_calendar (
    calendar_date date NOT NULL,
    year integer NOT NULL,
    quarter integer NOT NULL,
    month integer NOT NULL,
    day_of_month integer NOT NULL,
    iso_week integer NOT NULL,
    iso_day_of_week integer NOT NULL
);


--
-- Name: gd_002_currencies; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_002_currencies (
    currency_code character(3) CONSTRAINT gd_currencies_currency_code_not_null NOT NULL,
    currency_name text,
    minor_units integer
);


--
-- Name: gd_003_entities; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_003_entities (
    entity_id bigint CONSTRAINT gd_entities_entity_id_not_null NOT NULL,
    entity_reg_number character varying CONSTRAINT gd_entities_entity_code_not_null NOT NULL,
    country_code character(2) CONSTRAINT gd_entities_country_code_not_null NOT NULL,
    legal_name text NOT NULL,
    normalized_name text,
    tax_id character varying,
    vat_id character varying,
    legal_address character varying,
    column3 character varying(50),
    CONSTRAINT gd_entities_identity_check CHECK (((vat_id IS NOT NULL) OR (tax_id IS NOT NULL) OR (normalized_name IS NOT NULL)))
);


--
-- Name: gd_004_exchange_rates; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_004_exchange_rates (
    rate_id bigint CONSTRAINT gd_exchange_rates_rate_id_not_null NOT NULL,
    rate_date date CONSTRAINT gd_exchange_rates_rate_date_not_null NOT NULL,
    base_currency character(3) CONSTRAINT gd_exchange_rates_base_currency_not_null NOT NULL,
    quote_currency character(3) CONSTRAINT gd_exchange_rates_quote_currency_not_null NOT NULL,
    rate_value numeric(18,6) CONSTRAINT gd_exchange_rates_rate_value_not_null NOT NULL,
    rate_code character varying
);


--
-- Name: COLUMN gd_004_exchange_rates.rate_id; Type: COMMENT; Schema: glob; Owner: -
--

COMMENT ON COLUMN glob.gd_004_exchange_rates.rate_id IS 'gd_004';


--
-- Name: COLUMN gd_004_exchange_rates.rate_date; Type: COMMENT; Schema: glob; Owner: -
--

COMMENT ON COLUMN glob.gd_004_exchange_rates.rate_date IS 'gd_004';


--
-- Name: COLUMN gd_004_exchange_rates.base_currency; Type: COMMENT; Schema: glob; Owner: -
--

COMMENT ON COLUMN glob.gd_004_exchange_rates.base_currency IS 'gd_004';


--
-- Name: COLUMN gd_004_exchange_rates.quote_currency; Type: COMMENT; Schema: glob; Owner: -
--

COMMENT ON COLUMN glob.gd_004_exchange_rates.quote_currency IS 'gd_004';


--
-- Name: COLUMN gd_004_exchange_rates.rate_value; Type: COMMENT; Schema: glob; Owner: -
--

COMMENT ON COLUMN glob.gd_004_exchange_rates.rate_value IS 'gd_004';


--
-- Name: gd_005_inflation_rates; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_005_inflation_rates (
    year smallint CONSTRAINT gd_inflation_rates_year_not_null NOT NULL,
    currency_code character(3) CONSTRAINT gd_inflation_rates_currency_code_not_null NOT NULL,
    inflation_rate numeric(6,4) CONSTRAINT gd_inflation_rates_inflation_rate_not_null NOT NULL
);


--
-- Name: gd_006_movable_holidays; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_006_movable_holidays (
    country_code character(2) CONSTRAINT gd_movable_holidays_country_code_not_null NOT NULL,
    holiday_name text CONSTRAINT gd_movable_holidays_holiday_name_not_null NOT NULL,
    holiday_date date CONSTRAINT gd_movable_holidays_holiday_date_not_null NOT NULL
);


--
-- Name: gd_007_people; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_007_people (
    person_id bigint CONSTRAINT gd_people_person_id_not_null NOT NULL,
    person_code text,
    first_name text CONSTRAINT gd_people_first_name_not_null NOT NULL,
    middle_name text,
    last_name text CONSTRAINT gd_people_last_name_not_null NOT NULL,
    tax_id text,
    date_of_birth date,
    country_code character(2),
    active_from date DEFAULT '1900-01-01'::date CONSTRAINT gd_people_active_from_not_null NOT NULL,
    active_to date DEFAULT '2100-12-31'::date CONSTRAINT gd_people_active_to_not_null NOT NULL
);


--
-- Name: gd_008_ruleset_registry; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_008_ruleset_registry (
    ruleset_id text CONSTRAINT gd_rulesets_ruleset_id_not_null NOT NULL,
    ruleset_name text CONSTRAINT gd_rulesets_ruleset_name_not_null NOT NULL,
    description text,
    active_from date DEFAULT '1900-01-01'::date CONSTRAINT gd_rulesets_active_from_not_null NOT NULL,
    active_to date DEFAULT '2100-12-31'::date CONSTRAINT gd_rulesets_active_to_not_null NOT NULL,
    reporting_currency character(3),
    rate_source text
);


--
-- Name: gd_009_ruleset_lines; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_009_ruleset_lines (
    line_id bigint NOT NULL,
    ruleset_id text NOT NULL,
    operation_id bigint NOT NULL,
    entity_1_id bigint NOT NULL,
    entity_2_id bigint NOT NULL,
    account_id bigint NOT NULL,
    movement text NOT NULL,
    budget_element text,
    cfs_element text,
    active_from date DEFAULT CURRENT_DATE NOT NULL,
    active_to date DEFAULT '2101-12-31'::date NOT NULL,
    entry_id character varying,
    reference text,
    CONSTRAINT gd_009_movement_check CHECK ((movement = ANY (ARRAY['DR'::text, 'CR'::text])))
);


--
-- Name: gd_009_ruleset_lines_line_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

CREATE SEQUENCE glob.gd_009_ruleset_lines_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gd_009_ruleset_lines_line_id_seq; Type: SEQUENCE OWNED BY; Schema: glob; Owner: -
--

ALTER SEQUENCE glob.gd_009_ruleset_lines_line_id_seq OWNED BY glob.gd_009_ruleset_lines.line_id;


--
-- Name: gd_010_units; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_010_units (
    unit_id bigint CONSTRAINT gd_units_unit_id_not_null NOT NULL,
    unit_code text CONSTRAINT gd_units_unit_code_not_null NOT NULL,
    unit_name text CONSTRAINT gd_units_unit_name_not_null NOT NULL
);


--
-- Name: gd_011_holidays; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_011_holidays (
    holiday_id bigint NOT NULL,
    country_code character(2) NOT NULL,
    holiday_name text NOT NULL,
    holiday_date date NOT NULL
);


--
-- Name: gd_011_holidays_holiday_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

ALTER TABLE glob.gd_011_holidays ALTER COLUMN holiday_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME glob.gd_011_holidays_holiday_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_012_entity_calendar_overrides; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_012_entity_calendar_overrides (
    entity_id bigint NOT NULL,
    calendar_date date NOT NULL,
    date_class text NOT NULL,
    reason text
);


--
-- Name: gd_013_country_calendar; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_013_country_calendar (
    country_code character(2) NOT NULL,
    calendar_date date NOT NULL,
    date_class text NOT NULL
);


--
-- Name: gd_014_rate_codes; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_014_rate_codes (
    rate_code text NOT NULL,
    rate_name text NOT NULL,
    provider text,
    description text
);


--
-- Name: gd_015_documents; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_015_documents (
    document_id bigint NOT NULL,
    document_type text,
    document_date date,
    face_id text,
    file_name text,
    registered_at timestamp without time zone DEFAULT now()
);


--
-- Name: gd_015_documents_document_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

ALTER TABLE glob.gd_015_documents ALTER COLUMN document_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME glob.gd_015_documents_document_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_016_coa; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_016_coa (
    account_code text NOT NULL,
    ruleset_id text NOT NULL,
    parent_account_code text,
    active_from date DEFAULT CURRENT_DATE NOT NULL,
    active_to date DEFAULT '2101-12-31'::date NOT NULL,
    account_name character varying,
    parent_account_id character varying(50)
);


--
-- Name: gd_017_naming_conventions; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_017_naming_conventions (
    naming_id bigint NOT NULL,
    table_name text NOT NULL,
    element_id bigint NOT NULL,
    eng_name text NOT NULL,
    translation_lang text NOT NULL,
    translated_name text NOT NULL
);


--
-- Name: gd_017_naming_conventions_naming_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

CREATE SEQUENCE glob.gd_017_naming_conventions_naming_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gd_017_naming_conventions_naming_id_seq; Type: SEQUENCE OWNED BY; Schema: glob; Owner: -
--

ALTER SEQUENCE glob.gd_017_naming_conventions_naming_id_seq OWNED BY glob.gd_017_naming_conventions.naming_id;


--
-- Name: gd_018_policies; Type: TABLE; Schema: glob; Owner: -
--

CREATE TABLE glob.gd_018_policies (
    policy_id character varying NOT NULL,
    element_id character varying NOT NULL,
    element_substance text,
    external_reference text,
    effective_from date,
    effective_to date
);


--
-- Name: gd_entities_entity_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

ALTER TABLE glob.gd_003_entities ALTER COLUMN entity_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME glob.gd_entities_entity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_exchange_rates_rate_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

ALTER TABLE glob.gd_004_exchange_rates ALTER COLUMN rate_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME glob.gd_exchange_rates_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_people_person_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

ALTER TABLE glob.gd_007_people ALTER COLUMN person_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME glob.gd_people_person_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_units_unit_id_seq; Type: SEQUENCE; Schema: glob; Owner: -
--

ALTER TABLE glob.gd_010_units ALTER COLUMN unit_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME glob.gd_units_unit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gv_001_entity_calendar; Type: VIEW; Schema: glob; Owner: -
--

CREATE VIEW glob.gv_001_entity_calendar AS
 SELECT e.entity_id,
    d.calendar_date,
    COALESCE(o.date_class, c.date_class) AS date_class
   FROM (((glob.gd_003_entities e
     JOIN glob.gd_001_calendar d ON (true))
     JOIN glob.gd_013_country_calendar c ON (((c.country_code = e.country_code) AND (c.calendar_date = d.calendar_date))))
     LEFT JOIN glob.gd_012_entity_calendar_overrides o ON (((o.entity_id = e.entity_id) AND (o.calendar_date = d.calendar_date))));


--
-- Name: e_001_events_registry; Type: TABLE; Schema: modelprod; Owner: -
--

CREATE TABLE modelprod.e_001_events_registry (
    event_id bigint NOT NULL,
    event_date date NOT NULL,
    entity_1_id bigint NOT NULL,
    entity_2_id bigint NOT NULL,
    amount numeric NOT NULL,
    currency_code character(3) NOT NULL,
    raw_description text,
    operation_id bigint,
    origin_object_type text NOT NULL,
    origin_object_id bigint,
    document_id bigint,
    CONSTRAINT chk_modelprod_origin_object_type CHECK ((origin_object_type = ANY (ARRAY['LOGICAL_DOCUMENT_OBJECT'::text, 'RULE_APPLICATION_INSTANCE'::text])))
);


--
-- Name: gv_002_total_events_registry; Type: VIEW; Schema: glob; Owner: -
--

CREATE VIEW glob.gv_002_total_events_registry AS
 SELECT 1 AS schema_code,
    ((1 * '1000000000000'::bigint) + e.event_id) AS global_event_id,
    e.event_id,
    e.event_date,
    e.entity_1_id,
    e.entity_2_id,
    e.amount,
    e.currency_code,
    e.raw_description,
    e.operation_id,
    e.origin_object_type,
    e.origin_object_id,
    e.document_id
   FROM bteam.e_001_events_registry e
UNION ALL
 SELECT 2 AS schema_code,
    ((2 * '1000000000000'::bigint) + e.event_id) AS global_event_id,
    e.event_id,
    e.event_date,
    e.entity_1_id,
    e.entity_2_id,
    e.amount,
    e.currency_code,
    e.raw_description,
    e.operation_id,
    e.origin_object_type,
    e.origin_object_id,
    e.document_id
   FROM findo.e_001_events_registry e
UNION ALL
 SELECT 3 AS schema_code,
    ((3 * '1000000000000'::bigint) + e.event_id) AS global_event_id,
    e.event_id,
    e.event_date,
    e.entity_1_id,
    e.entity_2_id,
    e.amount,
    e.currency_code,
    e.raw_description,
    e.operation_id,
    e.origin_object_type,
    e.origin_object_id,
    e.document_id
   FROM modelprod.e_001_events_registry e;


--
-- Name: d_011_economic_operations; Type: TABLE; Schema: modelprod; Owner: -
--

CREATE TABLE modelprod.d_011_economic_operations (
    operation_id bigint NOT NULL,
    operation_code text NOT NULL,
    operation_name text NOT NULL
);


--
-- Name: d_011_economic_operations_operation_id_seq; Type: SEQUENCE; Schema: modelprod; Owner: -
--

CREATE SEQUENCE modelprod.d_011_economic_operations_operation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: d_011_economic_operations_operation_id_seq; Type: SEQUENCE OWNED BY; Schema: modelprod; Owner: -
--

ALTER SEQUENCE modelprod.d_011_economic_operations_operation_id_seq OWNED BY modelprod.d_011_economic_operations.operation_id;


--
-- Name: d_012_operation_catchstrings; Type: TABLE; Schema: modelprod; Owner: -
--

CREATE TABLE modelprod.d_012_operation_catchstrings (
    catchstring_id bigint NOT NULL,
    operation_id bigint NOT NULL,
    catchstring text NOT NULL
);


--
-- Name: d_012_operation_catchstrings_catchstring_id_seq; Type: SEQUENCE; Schema: modelprod; Owner: -
--

CREATE SEQUENCE modelprod.d_012_operation_catchstrings_catchstring_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: d_012_operation_catchstrings_catchstring_id_seq; Type: SEQUENCE OWNED BY; Schema: modelprod; Owner: -
--

ALTER SEQUENCE modelprod.d_012_operation_catchstrings_catchstring_id_seq OWNED BY modelprod.d_012_operation_catchstrings.catchstring_id;


--
-- Name: e_001_events_registry_event_id_seq; Type: SEQUENCE; Schema: modelprod; Owner: -
--

ALTER TABLE modelprod.e_001_events_registry ALTER COLUMN event_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME modelprod.e_001_events_registry_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: e_002_entries; Type: TABLE; Schema: modelprod; Owner: -
--

CREATE TABLE modelprod.e_002_entries (
    event_id integer NOT NULL,
    ruleset_id text NOT NULL,
    recon_date_automatic date NOT NULL,
    recon_date_reviewed date,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    entry_id character varying NOT NULL,
    amount numeric,
    currency_code text,
    recon_note character varying,
    CONSTRAINT e_002_recon_dates_status_chk CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('accepted'::character varying)::text, ('overridden'::character varying)::text])))
);


--
-- Name: e_002_recon_dates; Type: TABLE; Schema: modelprod; Owner: -
--

CREATE TABLE modelprod.e_002_recon_dates (
    event_id integer NOT NULL,
    ruleset_id text NOT NULL,
    recon_date_automatic date NOT NULL,
    recon_date_reviewed date,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    CONSTRAINT e_002_recon_dates_status_chk CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'overridden'::character varying])::text[])))
);


--
-- Name: bot_test; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bot_test (
    id integer NOT NULL,
    msg text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: bot_test_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bot_test_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bot_test_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bot_test_id_seq OWNED BY public.bot_test.id;


--
-- Name: instructions id; Type: DEFAULT; Schema: bot_instructions; Owner: -
--

ALTER TABLE ONLY bot_instructions.instructions ALTER COLUMN id SET DEFAULT nextval('bot_instructions.instructions_id_seq'::regclass);


--
-- Name: conversations id; Type: DEFAULT; Schema: bot_memory; Owner: -
--

ALTER TABLE ONLY bot_memory.conversations ALTER COLUMN id SET DEFAULT nextval('bot_memory.conversations_id_seq'::regclass);


--
-- Name: d_010_unit_entities unit_entity_id; Type: DEFAULT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.d_010_unit_entities ALTER COLUMN unit_entity_id SET DEFAULT nextval('bteam.d_010_unit_entities_unit_entity_id_seq'::regclass);


--
-- Name: d_011_economic_operations operation_id; Type: DEFAULT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.d_011_economic_operations ALTER COLUMN operation_id SET DEFAULT nextval('findo.d_011_economic_operations_operation_id_seq'::regclass);


--
-- Name: d_012_operation_catchstrings catchstring_id; Type: DEFAULT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.d_012_operation_catchstrings ALTER COLUMN catchstring_id SET DEFAULT nextval('findo.d_012_operation_catchstrings_catchstring_id_seq'::regclass);


--
-- Name: gd_009_ruleset_lines line_id; Type: DEFAULT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_009_ruleset_lines ALTER COLUMN line_id SET DEFAULT nextval('glob.gd_009_ruleset_lines_line_id_seq'::regclass);


--
-- Name: gd_017_naming_conventions naming_id; Type: DEFAULT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_017_naming_conventions ALTER COLUMN naming_id SET DEFAULT nextval('glob.gd_017_naming_conventions_naming_id_seq'::regclass);


--
-- Name: d_011_economic_operations operation_id; Type: DEFAULT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.d_011_economic_operations ALTER COLUMN operation_id SET DEFAULT nextval('modelprod.d_011_economic_operations_operation_id_seq'::regclass);


--
-- Name: d_012_operation_catchstrings catchstring_id; Type: DEFAULT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.d_012_operation_catchstrings ALTER COLUMN catchstring_id SET DEFAULT nextval('modelprod.d_012_operation_catchstrings_catchstring_id_seq'::regclass);


--
-- Name: bot_test id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_test ALTER COLUMN id SET DEFAULT nextval('public.bot_test_id_seq'::regclass);


--
-- Name: aw_001_audit_log aw_001_audit_log_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.aw_001_audit_log
    ADD CONSTRAINT aw_001_audit_log_pkey PRIMARY KEY (audit_id);


--
-- Name: instructions instructions_pkey; Type: CONSTRAINT; Schema: bot_instructions; Owner: -
--

ALTER TABLE ONLY bot_instructions.instructions
    ADD CONSTRAINT instructions_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: bot_memory; Owner: -
--

ALTER TABLE ONLY bot_memory.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: d_010_unit_entities d_010_unit_entities_pkey; Type: CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.d_010_unit_entities
    ADD CONSTRAINT d_010_unit_entities_pkey PRIMARY KEY (unit_entity_id);


--
-- Name: e_001_events_registry e_001_events_registry_pkey; Type: CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_001_events_registry
    ADD CONSTRAINT e_001_events_registry_pkey PRIMARY KEY (event_id);


--
-- Name: e_002_entries e_002_entries_pkey; Type: CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_002_entries
    ADD CONSTRAINT e_002_entries_pkey PRIMARY KEY (entry_id, ruleset_id);


--
-- Name: e_002_recon_dates e_002_recon_dates_pkey; Type: CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_002_recon_dates
    ADD CONSTRAINT e_002_recon_dates_pkey PRIMARY KEY (event_id, ruleset_id);


--
-- Name: d_011_economic_operations d_011_economic_operations_pkey; Type: CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.d_011_economic_operations
    ADD CONSTRAINT d_011_economic_operations_pkey PRIMARY KEY (operation_id);


--
-- Name: d_012_operation_catchstrings d_012_operation_catchstrings_pkey; Type: CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.d_012_operation_catchstrings
    ADD CONSTRAINT d_012_operation_catchstrings_pkey PRIMARY KEY (catchstring_id);


--
-- Name: e_001_events_registry e_001_events_registry_pkey; Type: CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_001_events_registry
    ADD CONSTRAINT e_001_events_registry_pkey PRIMARY KEY (event_id);


--
-- Name: e_002_entries e_002_entries_pkey; Type: CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_002_entries
    ADD CONSTRAINT e_002_entries_pkey PRIMARY KEY (entry_id, ruleset_id);


--
-- Name: gd_001_calendar gd_001_calendar_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_001_calendar
    ADD CONSTRAINT gd_001_calendar_pkey PRIMARY KEY (calendar_date);


--
-- Name: gd_009_ruleset_lines gd_009_ruleset_lines_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_009_ruleset_lines
    ADD CONSTRAINT gd_009_ruleset_lines_pkey PRIMARY KEY (line_id);


--
-- Name: gd_011_holidays gd_011_holidays_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_011_holidays
    ADD CONSTRAINT gd_011_holidays_pkey PRIMARY KEY (holiday_id);


--
-- Name: gd_012_entity_calendar_overrides gd_012_entity_calendar_overrides_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_012_entity_calendar_overrides
    ADD CONSTRAINT gd_012_entity_calendar_overrides_pkey PRIMARY KEY (entity_id, calendar_date);


--
-- Name: gd_013_country_calendar gd_013_country_calendar_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_013_country_calendar
    ADD CONSTRAINT gd_013_country_calendar_pkey PRIMARY KEY (country_code, calendar_date);


--
-- Name: gd_014_rate_codes gd_014_rate_codes_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_014_rate_codes
    ADD CONSTRAINT gd_014_rate_codes_pkey PRIMARY KEY (rate_code);


--
-- Name: gd_015_documents gd_015_documents_pk; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_015_documents
    ADD CONSTRAINT gd_015_documents_pk PRIMARY KEY (document_id);


--
-- Name: gd_016_coa gd_016_coa_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_016_coa
    ADD CONSTRAINT gd_016_coa_pkey PRIMARY KEY (account_code);


--
-- Name: gd_017_naming_conventions gd_017_naming_conventions_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_017_naming_conventions
    ADD CONSTRAINT gd_017_naming_conventions_pkey PRIMARY KEY (naming_id);


--
-- Name: gd_017_naming_conventions gd_017_unique_translation; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_017_naming_conventions
    ADD CONSTRAINT gd_017_unique_translation UNIQUE (table_name, element_id, translation_lang);


--
-- Name: gd_018_policies gd_018_policies_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_018_policies
    ADD CONSTRAINT gd_018_policies_pkey PRIMARY KEY (element_id);


--
-- Name: gd_002_currencies gd_currencies_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_002_currencies
    ADD CONSTRAINT gd_currencies_pkey PRIMARY KEY (currency_code);


--
-- Name: gd_003_entities gd_entities_entity_code_key; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_003_entities
    ADD CONSTRAINT gd_entities_entity_code_key UNIQUE (entity_reg_number);


--
-- Name: gd_003_entities gd_entities_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_003_entities
    ADD CONSTRAINT gd_entities_pkey PRIMARY KEY (entity_id);


--
-- Name: gd_004_exchange_rates gd_exchange_rates_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_004_exchange_rates
    ADD CONSTRAINT gd_exchange_rates_pkey PRIMARY KEY (rate_id);


--
-- Name: gd_004_exchange_rates gd_exchange_rates_unique_rate; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_004_exchange_rates
    ADD CONSTRAINT gd_exchange_rates_unique_rate UNIQUE (rate_date, base_currency, quote_currency, rate_code);


--
-- Name: gd_005_inflation_rates gd_inflation_rates_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_005_inflation_rates
    ADD CONSTRAINT gd_inflation_rates_pkey PRIMARY KEY (year, currency_code);


--
-- Name: gd_006_movable_holidays gd_movable_holidays_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_006_movable_holidays
    ADD CONSTRAINT gd_movable_holidays_pkey PRIMARY KEY (country_code, holiday_date);


--
-- Name: gd_007_people gd_people_person_code_key; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_007_people
    ADD CONSTRAINT gd_people_person_code_key UNIQUE (person_code);


--
-- Name: gd_007_people gd_people_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_007_people
    ADD CONSTRAINT gd_people_pkey PRIMARY KEY (person_id);


--
-- Name: gd_008_ruleset_registry gd_rulesets_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_008_ruleset_registry
    ADD CONSTRAINT gd_rulesets_pkey PRIMARY KEY (ruleset_id);


--
-- Name: gd_010_units gd_units_pkey; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_010_units
    ADD CONSTRAINT gd_units_pkey PRIMARY KEY (unit_id);


--
-- Name: gd_010_units gd_units_unit_code_key; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_010_units
    ADD CONSTRAINT gd_units_unit_code_key UNIQUE (unit_code);


--
-- Name: gd_011_holidays unique_country_holiday; Type: CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_011_holidays
    ADD CONSTRAINT unique_country_holiday UNIQUE (country_code, holiday_date);


--
-- Name: d_011_economic_operations d_011_economic_operations_pkey; Type: CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.d_011_economic_operations
    ADD CONSTRAINT d_011_economic_operations_pkey PRIMARY KEY (operation_id);


--
-- Name: d_012_operation_catchstrings d_012_operation_catchstrings_pkey; Type: CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.d_012_operation_catchstrings
    ADD CONSTRAINT d_012_operation_catchstrings_pkey PRIMARY KEY (catchstring_id);


--
-- Name: e_001_events_registry e_001_events_registry_pkey; Type: CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_001_events_registry
    ADD CONSTRAINT e_001_events_registry_pkey PRIMARY KEY (event_id);


--
-- Name: e_002_entries e_002_entries_pkey; Type: CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_002_entries
    ADD CONSTRAINT e_002_entries_pkey PRIMARY KEY (entry_id, ruleset_id);


--
-- Name: e_002_recon_dates e_002_recon_dates_pkey; Type: CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_002_recon_dates
    ADD CONSTRAINT e_002_recon_dates_pkey PRIMARY KEY (event_id, ruleset_id);


--
-- Name: bot_test bot_test_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_test
    ADD CONSTRAINT bot_test_pkey PRIMARY KEY (id);


--
-- Name: idx_conversations_chat_id; Type: INDEX; Schema: bot_memory; Owner: -
--

CREATE INDEX idx_conversations_chat_id ON bot_memory.conversations USING btree (chat_id);


--
-- Name: idx_conversations_created_at; Type: INDEX; Schema: bot_memory; Owner: -
--

CREATE INDEX idx_conversations_created_at ON bot_memory.conversations USING btree (created_at);


--
-- Name: idx_bteam_event_date; Type: INDEX; Schema: bteam; Owner: -
--

CREATE INDEX idx_bteam_event_date ON bteam.e_001_events_registry USING btree (event_date);


--
-- Name: idx_bteam_operation; Type: INDEX; Schema: bteam; Owner: -
--

CREATE INDEX idx_bteam_operation ON bteam.e_001_events_registry USING btree (operation_id);


--
-- Name: idx_findo_event_date; Type: INDEX; Schema: findo; Owner: -
--

CREATE INDEX idx_findo_event_date ON findo.e_001_events_registry USING btree (event_date);


--
-- Name: idx_findo_operation; Type: INDEX; Schema: findo; Owner: -
--

CREATE INDEX idx_findo_operation ON findo.e_001_events_registry USING btree (operation_id);


--
-- Name: idx_entities_name_trgm; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_entities_name_trgm ON glob.gd_003_entities USING gin (normalized_name public.gin_trgm_ops);


--
-- Name: idx_entities_tax; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_entities_tax ON glob.gd_003_entities USING btree (tax_id);


--
-- Name: idx_entities_vat; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_entities_vat ON glob.gd_003_entities USING btree (vat_id);


--
-- Name: idx_gd_009_dates; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_gd_009_dates ON glob.gd_009_ruleset_lines USING btree (active_from, active_to);


--
-- Name: idx_gd_009_trigger; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_gd_009_trigger ON glob.gd_009_ruleset_lines USING btree (operation_id, entity_1_id, entity_2_id, ruleset_id);


--
-- Name: idx_gd_016_coa_parent; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_gd_016_coa_parent ON glob.gd_016_coa USING btree (parent_account_code);


--
-- Name: idx_gd_016_coa_ruleset; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_gd_016_coa_ruleset ON glob.gd_016_coa USING btree (ruleset_id);


--
-- Name: idx_gd_017_element; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_gd_017_element ON glob.gd_017_naming_conventions USING btree (table_name, element_id);


--
-- Name: idx_gd_017_lang; Type: INDEX; Schema: glob; Owner: -
--

CREATE INDEX idx_gd_017_lang ON glob.gd_017_naming_conventions USING btree (translation_lang);


--
-- Name: idx_modelprod_event_date; Type: INDEX; Schema: modelprod; Owner: -
--

CREATE INDEX idx_modelprod_event_date ON modelprod.e_001_events_registry USING btree (event_date);


--
-- Name: idx_modelprod_operation; Type: INDEX; Schema: modelprod; Owner: -
--

CREATE INDEX idx_modelprod_operation ON modelprod.e_001_events_registry USING btree (operation_id);


--
-- Name: gd_002_currencies trg_audit_gd_002_currencies; Type: TRIGGER; Schema: glob; Owner: -
--

CREATE TRIGGER trg_audit_gd_002_currencies AFTER INSERT OR DELETE OR UPDATE ON glob.gd_002_currencies FOR EACH ROW EXECUTE FUNCTION audit.fn_log_change();


--
-- Name: gd_003_entities trg_audit_gd_003_entities; Type: TRIGGER; Schema: glob; Owner: -
--

CREATE TRIGGER trg_audit_gd_003_entities AFTER INSERT OR DELETE OR UPDATE ON glob.gd_003_entities FOR EACH ROW EXECUTE FUNCTION audit.fn_log_change();


--
-- Name: gd_007_people trg_audit_gd_people; Type: TRIGGER; Schema: glob; Owner: -
--

CREATE TRIGGER trg_audit_gd_people AFTER INSERT OR DELETE OR UPDATE ON glob.gd_007_people FOR EACH ROW EXECUTE FUNCTION audit.fn_log_change();


--
-- Name: e_002_entries e_002_recon_dates_event_fk; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_002_entries
    ADD CONSTRAINT e_002_recon_dates_event_fk FOREIGN KEY (event_id) REFERENCES bteam.e_001_events_registry(event_id);


--
-- Name: e_002_recon_dates e_002_recon_dates_event_fk; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_002_recon_dates
    ADD CONSTRAINT e_002_recon_dates_event_fk FOREIGN KEY (event_id) REFERENCES bteam.e_001_events_registry(event_id);


--
-- Name: e_002_entries e_002_recon_dates_ruleset_fk; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_002_entries
    ADD CONSTRAINT e_002_recon_dates_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES glob.gd_008_ruleset_registry(ruleset_id);


--
-- Name: e_002_recon_dates e_002_recon_dates_ruleset_fk; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_002_recon_dates
    ADD CONSTRAINT e_002_recon_dates_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES glob.gd_008_ruleset_registry(ruleset_id);


--
-- Name: e_001_events_registry fk_bteam_event_currency; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_001_events_registry
    ADD CONSTRAINT fk_bteam_event_currency FOREIGN KEY (currency_code) REFERENCES glob.gd_002_currencies(currency_code);


--
-- Name: e_001_events_registry fk_bteam_event_entity_1; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_001_events_registry
    ADD CONSTRAINT fk_bteam_event_entity_1 FOREIGN KEY (entity_1_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: e_001_events_registry fk_bteam_event_entity_2; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_001_events_registry
    ADD CONSTRAINT fk_bteam_event_entity_2 FOREIGN KEY (entity_2_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: e_001_events_registry fk_bteam_event_operation; Type: FK CONSTRAINT; Schema: bteam; Owner: -
--

ALTER TABLE ONLY bteam.e_001_events_registry
    ADD CONSTRAINT fk_bteam_event_operation FOREIGN KEY (operation_id) REFERENCES findo.d_011_economic_operations(operation_id);


--
-- Name: e_002_entries e_002_recon_dates_event_fk; Type: FK CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_002_entries
    ADD CONSTRAINT e_002_recon_dates_event_fk FOREIGN KEY (event_id) REFERENCES findo.e_001_events_registry(event_id);


--
-- Name: e_002_entries e_002_recon_dates_ruleset_fk; Type: FK CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_002_entries
    ADD CONSTRAINT e_002_recon_dates_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES glob.gd_008_ruleset_registry(ruleset_id);


--
-- Name: e_001_events_registry fk_findo_event_currency; Type: FK CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_001_events_registry
    ADD CONSTRAINT fk_findo_event_currency FOREIGN KEY (currency_code) REFERENCES glob.gd_002_currencies(currency_code);


--
-- Name: e_001_events_registry fk_findo_event_entity_1; Type: FK CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_001_events_registry
    ADD CONSTRAINT fk_findo_event_entity_1 FOREIGN KEY (entity_1_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: e_001_events_registry fk_findo_event_entity_2; Type: FK CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_001_events_registry
    ADD CONSTRAINT fk_findo_event_entity_2 FOREIGN KEY (entity_2_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: e_001_events_registry fk_findo_event_operation; Type: FK CONSTRAINT; Schema: findo; Owner: -
--

ALTER TABLE ONLY findo.e_001_events_registry
    ADD CONSTRAINT fk_findo_event_operation FOREIGN KEY (operation_id) REFERENCES findo.d_011_economic_operations(operation_id);


--
-- Name: gd_004_exchange_rates fk_fx_rate_code; Type: FK CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_004_exchange_rates
    ADD CONSTRAINT fk_fx_rate_code FOREIGN KEY (rate_code) REFERENCES glob.gd_014_rate_codes(rate_code);


--
-- Name: gd_008_ruleset_registry gd_008_ruleset_registry_rate_source_fkey; Type: FK CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_008_ruleset_registry
    ADD CONSTRAINT gd_008_ruleset_registry_rate_source_fkey FOREIGN KEY (rate_source) REFERENCES glob.gd_014_rate_codes(rate_code);


--
-- Name: gd_008_ruleset_registry gd_008_ruleset_registry_reporting_currency_fkey; Type: FK CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_008_ruleset_registry
    ADD CONSTRAINT gd_008_ruleset_registry_reporting_currency_fkey FOREIGN KEY (reporting_currency) REFERENCES glob.gd_002_currencies(currency_code);


--
-- Name: gd_009_ruleset_lines gd_009_entity1_fk; Type: FK CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_009_ruleset_lines
    ADD CONSTRAINT gd_009_entity1_fk FOREIGN KEY (entity_1_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: gd_009_ruleset_lines gd_009_entity2_fk; Type: FK CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_009_ruleset_lines
    ADD CONSTRAINT gd_009_entity2_fk FOREIGN KEY (entity_2_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: gd_009_ruleset_lines gd_009_ruleset_fk; Type: FK CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_009_ruleset_lines
    ADD CONSTRAINT gd_009_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES glob.gd_008_ruleset_registry(ruleset_id);


--
-- Name: gd_016_coa gd_016_coa_ruleset_fk; Type: FK CONSTRAINT; Schema: glob; Owner: -
--

ALTER TABLE ONLY glob.gd_016_coa
    ADD CONSTRAINT gd_016_coa_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES glob.gd_008_ruleset_registry(ruleset_id);


--
-- Name: e_002_entries e_002_recon_dates_event_fk; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_002_entries
    ADD CONSTRAINT e_002_recon_dates_event_fk FOREIGN KEY (event_id) REFERENCES modelprod.e_001_events_registry(event_id);


--
-- Name: e_002_recon_dates e_002_recon_dates_event_fk; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_002_recon_dates
    ADD CONSTRAINT e_002_recon_dates_event_fk FOREIGN KEY (event_id) REFERENCES modelprod.e_001_events_registry(event_id);


--
-- Name: e_002_entries e_002_recon_dates_ruleset_fk; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_002_entries
    ADD CONSTRAINT e_002_recon_dates_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES glob.gd_008_ruleset_registry(ruleset_id);


--
-- Name: e_002_recon_dates e_002_recon_dates_ruleset_fk; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_002_recon_dates
    ADD CONSTRAINT e_002_recon_dates_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES glob.gd_008_ruleset_registry(ruleset_id);


--
-- Name: e_001_events_registry fk_modelprod_event_currency; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_001_events_registry
    ADD CONSTRAINT fk_modelprod_event_currency FOREIGN KEY (currency_code) REFERENCES glob.gd_002_currencies(currency_code);


--
-- Name: e_001_events_registry fk_modelprod_event_entity_1; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_001_events_registry
    ADD CONSTRAINT fk_modelprod_event_entity_1 FOREIGN KEY (entity_1_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: e_001_events_registry fk_modelprod_event_entity_2; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_001_events_registry
    ADD CONSTRAINT fk_modelprod_event_entity_2 FOREIGN KEY (entity_2_id) REFERENCES glob.gd_003_entities(entity_id);


--
-- Name: e_001_events_registry fk_modelprod_event_operation; Type: FK CONSTRAINT; Schema: modelprod; Owner: -
--

ALTER TABLE ONLY modelprod.e_001_events_registry
    ADD CONSTRAINT fk_modelprod_event_operation FOREIGN KEY (operation_id) REFERENCES modelprod.d_011_economic_operations(operation_id);


--
-- PostgreSQL database dump complete
--

\unrestrict ZtiZKIj1buVneTvPKsHvEuQMHxEJyaPYfo3trGDcfWIWR2LNK2UshLypMXxAv5i

