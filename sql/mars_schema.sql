--
-- PostgreSQL database dump
--

\restrict sHhMJZ9fkAhgtUlpUyUd0xxtYQfHMbVkustB4am6AwKiUreYTVETJBq3N6aRGP6

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
-- Name: global; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA global;


ALTER SCHEMA global OWNER TO postgres;

--
-- Name: fn_is_valid_event_status(character varying); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_valid_event_status(p_status_code character varying) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM global.gd_006_status_registry
        WHERE status_type = 'event_status'
          AND status_code = p_status_code
    );
END;
$$;


ALTER FUNCTION global.fn_is_valid_event_status(p_status_code character varying) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: gd_001_events; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_001_events (
    event_id bigint NOT NULL,
    event_type character varying(64) NOT NULL,
    source_type character varying(32) NOT NULL,
    source_ref character varying(256),
    valid_time timestamp without time zone NOT NULL,
    assertion_time timestamp without time zone NOT NULL,
    entity_id bigint NOT NULL,
    governance_scope_id bigint,
    commit_id bigint NOT NULL,
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    event_description text,
    event_status character varying(32) NOT NULL,
    CONSTRAINT gd_001_events_assertion_time_chk CHECK ((assertion_time >= '1901-01-01 00:00:00'::timestamp without time zone)),
    CONSTRAINT gd_001_events_event_status_type_chk CHECK (global.fn_is_valid_event_status(event_status)),
    CONSTRAINT gd_001_events_valid_time_chk CHECK ((valid_time >= '1901-01-01 00:00:00'::timestamp without time zone))
);


ALTER TABLE global.gd_001_events OWNER TO postgres;

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

ALTER SEQUENCE global.gd_001_events_event_id_seq OWNED BY global.gd_001_events.event_id;


--
-- Name: gd_002_ruleset_registry; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_002_ruleset_registry (
    ruleset_id character varying(128) CONSTRAINT gd_008_ruleset_registry_ruleset_id_not_null NOT NULL,
    ruleset_name character varying(256) CONSTRAINT gd_008_ruleset_registry_ruleset_name_not_null NOT NULL,
    ruleset_type character varying(64) CONSTRAINT gd_008_ruleset_registry_ruleset_type_not_null NOT NULL,
    ruleset_description text,
    valid_from timestamp without time zone DEFAULT '1901-01-01 00:00:00'::timestamp without time zone CONSTRAINT gd_008_ruleset_registry_valid_from_not_null NOT NULL,
    valid_to timestamp without time zone DEFAULT '3001-12-31 00:00:00'::timestamp without time zone CONSTRAINT gd_008_ruleset_registry_valid_to_not_null NOT NULL,
    governance_scope_id bigint,
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() CONSTRAINT gd_008_ruleset_registry_created_at_not_null NOT NULL,
    CONSTRAINT gd_008_ruleset_registry_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_002_ruleset_registry OWNER TO postgres;

--
-- Name: TABLE gd_002_ruleset_registry; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_002_ruleset_registry IS 'Canonical registry of governance-approved Rulesets participating in deterministic reconstruction and replay.';


--
-- Name: COLUMN gd_002_ruleset_registry.ruleset_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.ruleset_id IS 'Stable canonical Ruleset identity.';


--
-- Name: COLUMN gd_002_ruleset_registry.ruleset_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.ruleset_name IS 'Human-readable Ruleset name.';


--
-- Name: COLUMN gd_002_ruleset_registry.ruleset_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.ruleset_type IS 'Canonical Ruleset classification.';


--
-- Name: COLUMN gd_002_ruleset_registry.ruleset_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.ruleset_description IS 'Human-readable Ruleset explanation and applicability notes.';


--
-- Name: COLUMN gd_002_ruleset_registry.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.valid_from IS 'Beginning of Ruleset applicability interval.';


--
-- Name: COLUMN gd_002_ruleset_registry.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.valid_to IS 'End of Ruleset applicability interval.';


--
-- Name: COLUMN gd_002_ruleset_registry.governance_scope_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.governance_scope_id IS 'Governance applicability scope participating in Ruleset authorization and replay semantics.';


--
-- Name: COLUMN gd_002_ruleset_registry.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.created_by IS 'Infrastructure actor responsible for physical Ruleset registration.';


--
-- Name: COLUMN gd_002_ruleset_registry.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_ruleset_registry.created_at IS 'Physical insertion timestamp of Ruleset registry record.';


--
-- Name: gd_003_ruleset_lines; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_003_ruleset_lines (
    line_id bigint CONSTRAINT gd_009_ruleset_lines_line_id_not_null NOT NULL,
    ruleset_id character varying(128) CONSTRAINT gd_009_ruleset_lines_ruleset_id_not_null NOT NULL,
    operation_id bigint CONSTRAINT gd_009_ruleset_lines_operation_id_not_null NOT NULL,
    entity_1_id bigint,
    entity_2_id bigint,
    account_id bigint,
    trf_direction character varying(32) CONSTRAINT gd_009_ruleset_lines_trf_direction_not_null NOT NULL,
    amount numeric(20,6),
    valid_from timestamp without time zone DEFAULT '1901-01-01 00:00:00'::timestamp without time zone CONSTRAINT gd_009_ruleset_lines_valid_from_not_null NOT NULL,
    valid_to timestamp without time zone DEFAULT '3001-12-31 00:00:00'::timestamp without time zone CONSTRAINT gd_009_ruleset_lines_valid_to_not_null NOT NULL,
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() CONSTRAINT gd_009_ruleset_lines_created_at_not_null NOT NULL,
    line_description text,
    CONSTRAINT gd_009_ruleset_lines_transformation_direction_chk CHECK (((trf_direction)::text = ANY ((ARRAY['increase'::character varying, 'decrease'::character varying, 'recognize'::character varying, 'derecognize'::character varying, 'transfer_in'::character varying, 'transfer_out'::character varying, 'debit'::character varying, 'credit'::character varying])::text[]))),
    CONSTRAINT gd_009_ruleset_lines_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_003_ruleset_lines OWNER TO postgres;

--
-- Name: gd_015_exchange_rates; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_015_exchange_rates (
    rate_id bigint CONSTRAINT gd_004_exchange_rates_rate_id_not_null NOT NULL,
    rate_timestamp timestamp without time zone CONSTRAINT gd_004_exchange_rates_rate_timestamp_not_null NOT NULL,
    base_currency character(3) CONSTRAINT gd_004_exchange_rates_base_currency_not_null NOT NULL,
    quote_currency character(3) CONSTRAINT gd_004_exchange_rates_quote_currency_not_null NOT NULL,
    exchange_rate numeric(18,6) CONSTRAINT gd_004_exchange_rates_exchange_rate_not_null NOT NULL,
    rate_code character varying(64),
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() CONSTRAINT gd_004_exchange_rates_created_at_not_null NOT NULL
);


ALTER TABLE global.gd_015_exchange_rates OWNER TO postgres;

--
-- Name: TABLE gd_015_exchange_rates; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_015_exchange_rates IS 'Canonical exchange rate registry participating in deterministic replay and financial reconstruction.';


--
-- Name: COLUMN gd_015_exchange_rates.rate_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.rate_id IS 'Stable internal identity of exchange rate record.';


--
-- Name: COLUMN gd_015_exchange_rates.rate_timestamp; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.rate_timestamp IS 'Timestamp at which exchange rate becomes applicable for replay and interpretation.';


--
-- Name: COLUMN gd_015_exchange_rates.base_currency; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.base_currency IS 'Source currency participating in exchange rate transformation.';


--
-- Name: COLUMN gd_015_exchange_rates.quote_currency; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.quote_currency IS 'Target currency participating in exchange rate transformation.';


--
-- Name: COLUMN gd_015_exchange_rates.exchange_rate; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.exchange_rate IS 'Deterministic conversion ratio between base and quote currency.';


--
-- Name: COLUMN gd_015_exchange_rates.rate_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.rate_code IS 'Canonical exchange rate source or methodology identifier.';


--
-- Name: COLUMN gd_015_exchange_rates.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.created_by IS 'Infrastructure actor responsible for physical insertion of exchange rate record.';


--
-- Name: COLUMN gd_015_exchange_rates.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_015_exchange_rates.created_at IS 'Physical insertion timestamp of exchange rate record.';


--
-- Name: gd_004_exchange_rates_rate_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_004_exchange_rates_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_004_exchange_rates_rate_id_seq OWNER TO postgres;

--
-- Name: gd_004_exchange_rates_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_004_exchange_rates_rate_id_seq OWNED BY global.gd_015_exchange_rates.rate_id;


--
-- Name: gd_005_commit_records; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_005_commit_records (
    commit_id bigint NOT NULL,
    commit_timestamp timestamp without time zone NOT NULL,
    committing_authority_id bigint NOT NULL,
    commit_type character varying(64) NOT NULL,
    commit_reason text,
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    commit_status character varying(32) NOT NULL,
    CONSTRAINT gd_005_commit_records_commit_timestamp_chk CHECK ((commit_timestamp >= '1901-01-01 00:00:00'::timestamp without time zone))
);


ALTER TABLE global.gd_005_commit_records OWNER TO postgres;

--
-- Name: gd_005_commit_records_commit_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_005_commit_records_commit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_005_commit_records_commit_id_seq OWNER TO postgres;

--
-- Name: gd_005_commit_records_commit_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_005_commit_records_commit_id_seq OWNED BY global.gd_005_commit_records.commit_id;


--
-- Name: gd_014_inflation_rates; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_014_inflation_rates (
    inflation_rate_id bigint CONSTRAINT gd_005_inflation_rates_inflation_rate_id_not_null NOT NULL,
    applicable_year integer CONSTRAINT gd_005_inflation_rates_applicable_year_not_null NOT NULL,
    currency_code character(3) CONSTRAINT gd_005_inflation_rates_currency_code_not_null NOT NULL,
    inflation_rate numeric(10,6) CONSTRAINT gd_005_inflation_rates_inflation_rate_not_null NOT NULL,
    inflation_source character varying(128),
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() CONSTRAINT gd_005_inflation_rates_created_at_not_null NOT NULL
);


ALTER TABLE global.gd_014_inflation_rates OWNER TO postgres;

--
-- Name: TABLE gd_014_inflation_rates; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_014_inflation_rates IS 'Canonical inflation rate registry participating in deterministic economic reconstruction and replay interpretation.';


--
-- Name: COLUMN gd_014_inflation_rates.inflation_rate_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.inflation_rate_id IS 'Stable internal identity of inflation rate record.';


--
-- Name: COLUMN gd_014_inflation_rates.applicable_year; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.applicable_year IS 'Calendar year during which inflation rate is applicable.';


--
-- Name: COLUMN gd_014_inflation_rates.currency_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.currency_code IS 'Currency to which inflation rate applies.';


--
-- Name: COLUMN gd_014_inflation_rates.inflation_rate; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.inflation_rate IS 'Deterministic inflation coefficient applicable during replay interpretation.';


--
-- Name: COLUMN gd_014_inflation_rates.inflation_source; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.inflation_source IS 'Canonical source or methodology identifier of inflation rate.';


--
-- Name: COLUMN gd_014_inflation_rates.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.created_by IS 'Infrastructure actor responsible for physical insertion of inflation rate record.';


--
-- Name: COLUMN gd_014_inflation_rates.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.created_at IS 'Physical insertion timestamp of inflation rate record.';


--
-- Name: gd_005_inflation_rates_inflation_rate_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_005_inflation_rates_inflation_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_005_inflation_rates_inflation_rate_id_seq OWNER TO postgres;

--
-- Name: gd_005_inflation_rates_inflation_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_005_inflation_rates_inflation_rate_id_seq OWNED BY global.gd_014_inflation_rates.inflation_rate_id;


--
-- Name: gd_006_status_registry; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_006_status_registry (
    status_code character varying(32) CONSTRAINT gd_006_event_status_registry_event_status_code_not_null NOT NULL,
    status_name character varying(128) CONSTRAINT gd_006_event_status_registry_event_status_name_not_null NOT NULL,
    status_description text,
    is_authoritative_replay_eligible boolean DEFAULT false CONSTRAINT gd_006_event_status_registr_is_authoritative_replay_el_not_null NOT NULL,
    is_terminal boolean DEFAULT false CONSTRAINT gd_006_event_status_registry_is_terminal_not_null NOT NULL,
    created_at timestamp without time zone DEFAULT now() CONSTRAINT gd_006_event_status_registry_created_at_not_null NOT NULL,
    status_type character varying(64) DEFAULT 'event_status'::character varying NOT NULL
);


ALTER TABLE global.gd_006_status_registry OWNER TO postgres;

--
-- Name: gd_007_governance_identities; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_007_governance_identities (
    governance_identity_id bigint CONSTRAINT gd_013_governance_identities_governance_identity_id_not_null NOT NULL,
    identity_type character varying(64) CONSTRAINT gd_013_governance_identities_identity_type_not_null NOT NULL,
    identity_name character varying(256) CONSTRAINT gd_013_governance_identities_identity_name_not_null NOT NULL,
    identity_code character varying(128) CONSTRAINT gd_013_governance_identities_identity_code_not_null NOT NULL,
    valid_from timestamp without time zone DEFAULT '1901-01-01 00:00:00'::timestamp without time zone CONSTRAINT gd_013_governance_identities_valid_from_not_null NOT NULL,
    valid_to timestamp without time zone DEFAULT '3001-12-31 00:00:00'::timestamp without time zone CONSTRAINT gd_013_governance_identities_valid_to_not_null NOT NULL,
    identity_status character varying(32) CONSTRAINT gd_013_governance_identities_identity_status_not_null NOT NULL,
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() CONSTRAINT gd_013_governance_identities_created_at_not_null NOT NULL,
    identity_description text,
    CONSTRAINT gd_013_governance_identities_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_007_governance_identities OWNER TO postgres;

--
-- Name: gd_016_people; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_016_people (
    person_id bigint CONSTRAINT gd_007_people_person_id_not_null NOT NULL,
    person_code character varying(128),
    first_name character varying(128) CONSTRAINT gd_007_people_first_name_not_null NOT NULL,
    middle_name character varying(128),
    last_name character varying(128) CONSTRAINT gd_007_people_last_name_not_null NOT NULL,
    tax_id character varying(128),
    date_of_birth date,
    country_code character(2),
    valid_from timestamp without time zone DEFAULT '1901-01-01 00:00:00'::timestamp without time zone CONSTRAINT gd_007_people_valid_from_not_null NOT NULL,
    valid_to timestamp without time zone DEFAULT '3001-12-31 00:00:00'::timestamp without time zone CONSTRAINT gd_007_people_valid_to_not_null NOT NULL,
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() CONSTRAINT gd_007_people_created_at_not_null NOT NULL,
    CONSTRAINT gd_007_people_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_016_people OWNER TO postgres;

--
-- Name: TABLE gd_016_people; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_016_people IS 'Canonical registry of real-world persons participating in organizational reconstruction and governance relations.';


--
-- Name: COLUMN gd_016_people.person_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.person_id IS 'Stable internal identity of person record.';


--
-- Name: COLUMN gd_016_people.person_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.person_code IS 'Canonical external or organizational identifier of person.';


--
-- Name: COLUMN gd_016_people.first_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.first_name IS 'Registered first name of person.';


--
-- Name: COLUMN gd_016_people.middle_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.middle_name IS 'Registered middle name of person.';


--
-- Name: COLUMN gd_016_people.last_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.last_name IS 'Registered last name of person.';


--
-- Name: COLUMN gd_016_people.tax_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.tax_id IS 'Jurisdictional taxpayer or national identification reference of person.';


--
-- Name: COLUMN gd_016_people.date_of_birth; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.date_of_birth IS 'Declared date of birth of person.';


--
-- Name: COLUMN gd_016_people.country_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.country_code IS 'Canonical country code associated with person record.';


--
-- Name: COLUMN gd_016_people.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.valid_from IS 'Beginning of person record applicability interval.';


--
-- Name: COLUMN gd_016_people.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.valid_to IS 'End of person record applicability interval.';


--
-- Name: COLUMN gd_016_people.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.created_by IS 'Infrastructure actor responsible for physical insertion of person record.';


--
-- Name: COLUMN gd_016_people.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_people.created_at IS 'Physical insertion timestamp of person record.';


--
-- Name: gd_007_people_person_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_007_people_person_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_007_people_person_id_seq OWNER TO postgres;

--
-- Name: gd_007_people_person_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_007_people_person_id_seq OWNED BY global.gd_016_people.person_id;


--
-- Name: gd_009_ruleset_lines_line_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_009_ruleset_lines_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_009_ruleset_lines_line_id_seq OWNER TO postgres;

--
-- Name: gd_009_ruleset_lines_line_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_009_ruleset_lines_line_id_seq OWNED BY global.gd_003_ruleset_lines.line_id;


--
-- Name: gd_011_exrate_codes; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_011_exrate_codes (
    rate_code character varying(64) NOT NULL,
    rate_name character varying(256) NOT NULL,
    provider character varying(256),
    description text,
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE global.gd_011_exrate_codes OWNER TO postgres;

--
-- Name: TABLE gd_011_exrate_codes; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_011_exrate_codes IS 'Canonical registry of exchange rate source and methodology identifiers used in deterministic replay and financial reconstruction.';


--
-- Name: COLUMN gd_011_exrate_codes.rate_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_exrate_codes.rate_code IS 'Stable canonical identifier of exchange rate source or methodology.';


--
-- Name: COLUMN gd_011_exrate_codes.rate_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_exrate_codes.rate_name IS 'Human-readable name of exchange rate source or methodology.';


--
-- Name: COLUMN gd_011_exrate_codes.provider; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_exrate_codes.provider IS 'Organization or infrastructure provider supplying exchange rate data.';


--
-- Name: COLUMN gd_011_exrate_codes.description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_exrate_codes.description IS 'Human-readable explanation of exchange rate source semantics and applicability.';


--
-- Name: COLUMN gd_011_exrate_codes.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_exrate_codes.created_by IS 'Infrastructure actor responsible for physical insertion of exchange rate code record.';


--
-- Name: COLUMN gd_011_exrate_codes.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_exrate_codes.created_at IS 'Physical insertion timestamp of exchange rate code record.';


--
-- Name: gd_013_governance_identities_governance_identity_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

CREATE SEQUENCE global.gd_013_governance_identities_governance_identity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE global.gd_013_governance_identities_governance_identity_id_seq OWNER TO postgres;

--
-- Name: gd_013_governance_identities_governance_identity_id_seq; Type: SEQUENCE OWNED BY; Schema: global; Owner: postgres
--

ALTER SEQUENCE global.gd_013_governance_identities_governance_identity_id_seq OWNED BY global.gd_007_governance_identities.governance_identity_id;


--
-- Name: gd_017_naming_conventions; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_017_naming_conventions (
    naming_id bigint NOT NULL,
    object_type character varying(128) NOT NULL,
    object_id bigint NOT NULL,
    canonical_name character varying(256) NOT NULL,
    translation_language character(2) NOT NULL,
    translated_name character varying(256) NOT NULL,
    translation_context character varying(128),
    created_by character varying(128),
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE global.gd_017_naming_conventions OWNER TO postgres;

--
-- Name: TABLE gd_017_naming_conventions; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_017_naming_conventions IS 'Canonical multilingual naming registry used for disclosure, reporting, localization and governance-readable reconstruction.';


--
-- Name: COLUMN gd_017_naming_conventions.naming_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.naming_id IS 'Stable internal identity of naming convention record.';


--
-- Name: COLUMN gd_017_naming_conventions.object_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.object_type IS 'Canonical classification of organizational object receiving translated naming semantics.';


--
-- Name: COLUMN gd_017_naming_conventions.object_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.object_id IS 'Identifier of organizational object receiving translated naming semantics.';


--
-- Name: COLUMN gd_017_naming_conventions.canonical_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.canonical_name IS 'Primary canonical organizational name of object.';


--
-- Name: COLUMN gd_017_naming_conventions.translation_language; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.translation_language IS 'Language code of translated naming representation.';


--
-- Name: COLUMN gd_017_naming_conventions.translated_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.translated_name IS 'Localized or translated organizational naming representation.';


--
-- Name: COLUMN gd_017_naming_conventions.translation_context; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.translation_context IS 'Optional disclosure, legal or reporting context governing translation applicability.';


--
-- Name: COLUMN gd_017_naming_conventions.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.created_by IS 'Infrastructure actor responsible for physical insertion of naming convention record.';


--
-- Name: COLUMN gd_017_naming_conventions.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.created_at IS 'Physical insertion timestamp of naming convention record.';


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

ALTER SEQUENCE global.gd_017_naming_conventions_naming_id_seq OWNED BY global.gd_017_naming_conventions.naming_id;


--
-- Name: gd_001_events event_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events ALTER COLUMN event_id SET DEFAULT nextval('global.gd_001_events_event_id_seq'::regclass);


--
-- Name: gd_003_ruleset_lines line_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_003_ruleset_lines ALTER COLUMN line_id SET DEFAULT nextval('global.gd_009_ruleset_lines_line_id_seq'::regclass);


--
-- Name: gd_005_commit_records commit_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_commit_records ALTER COLUMN commit_id SET DEFAULT nextval('global.gd_005_commit_records_commit_id_seq'::regclass);


--
-- Name: gd_007_governance_identities governance_identity_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_007_governance_identities ALTER COLUMN governance_identity_id SET DEFAULT nextval('global.gd_013_governance_identities_governance_identity_id_seq'::regclass);


--
-- Name: gd_014_inflation_rates inflation_rate_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_014_inflation_rates ALTER COLUMN inflation_rate_id SET DEFAULT nextval('global.gd_005_inflation_rates_inflation_rate_id_seq'::regclass);


--
-- Name: gd_015_exchange_rates rate_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_015_exchange_rates ALTER COLUMN rate_id SET DEFAULT nextval('global.gd_004_exchange_rates_rate_id_seq'::regclass);


--
-- Name: gd_016_people person_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_016_people ALTER COLUMN person_id SET DEFAULT nextval('global.gd_007_people_person_id_seq'::regclass);


--
-- Name: gd_017_naming_conventions naming_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_017_naming_conventions ALTER COLUMN naming_id SET DEFAULT nextval('global.gd_017_naming_conventions_naming_id_seq'::regclass);


--
-- Name: gd_001_events gd_001_events_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_pk PRIMARY KEY (event_id);


--
-- Name: gd_015_exchange_rates gd_004_exchange_rates_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_015_exchange_rates
    ADD CONSTRAINT gd_004_exchange_rates_pk PRIMARY KEY (rate_id);


--
-- Name: gd_015_exchange_rates gd_004_exchange_rates_unique_rate; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_015_exchange_rates
    ADD CONSTRAINT gd_004_exchange_rates_unique_rate UNIQUE (rate_timestamp, base_currency, quote_currency, rate_code);


--
-- Name: gd_005_commit_records gd_005_commit_records_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_commit_records
    ADD CONSTRAINT gd_005_commit_records_pk PRIMARY KEY (commit_id);


--
-- Name: gd_014_inflation_rates gd_005_inflation_rates_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_014_inflation_rates
    ADD CONSTRAINT gd_005_inflation_rates_pk PRIMARY KEY (inflation_rate_id);


--
-- Name: gd_014_inflation_rates gd_005_inflation_rates_unique; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_014_inflation_rates
    ADD CONSTRAINT gd_005_inflation_rates_unique UNIQUE (applicable_year, currency_code, inflation_source);


--
-- Name: gd_006_status_registry gd_006_status_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_006_status_registry
    ADD CONSTRAINT gd_006_status_registry_pk PRIMARY KEY (status_type, status_code);


--
-- Name: gd_006_status_registry gd_006_status_registry_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_006_status_registry
    ADD CONSTRAINT gd_006_status_registry_uq UNIQUE (status_type, status_code);


--
-- Name: gd_016_people gd_007_people_person_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_016_people
    ADD CONSTRAINT gd_007_people_person_code_uq UNIQUE (person_code);


--
-- Name: gd_016_people gd_007_people_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_016_people
    ADD CONSTRAINT gd_007_people_pk PRIMARY KEY (person_id);


--
-- Name: gd_002_ruleset_registry gd_008_ruleset_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_002_ruleset_registry
    ADD CONSTRAINT gd_008_ruleset_registry_pk PRIMARY KEY (ruleset_id);


--
-- Name: gd_003_ruleset_lines gd_009_ruleset_lines_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_003_ruleset_lines
    ADD CONSTRAINT gd_009_ruleset_lines_pk PRIMARY KEY (line_id);


--
-- Name: gd_011_exrate_codes gd_011_exrate_codes_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_011_exrate_codes
    ADD CONSTRAINT gd_011_exrate_codes_pk PRIMARY KEY (rate_code);


--
-- Name: gd_007_governance_identities gd_013_governance_identities_identity_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_007_governance_identities
    ADD CONSTRAINT gd_013_governance_identities_identity_code_uq UNIQUE (identity_code);


--
-- Name: gd_007_governance_identities gd_013_governance_identities_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_007_governance_identities
    ADD CONSTRAINT gd_013_governance_identities_pk PRIMARY KEY (governance_identity_id);


--
-- Name: gd_017_naming_conventions gd_017_naming_conventions_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_017_naming_conventions
    ADD CONSTRAINT gd_017_naming_conventions_pk PRIMARY KEY (naming_id);


--
-- Name: gd_017_naming_conventions gd_017_naming_conventions_unique; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_017_naming_conventions
    ADD CONSTRAINT gd_017_naming_conventions_unique UNIQUE (object_type, object_id, translation_language);


--
-- Name: gd_001_events_assertion_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_assertion_time_idx ON global.gd_001_events USING btree (assertion_time);


--
-- Name: gd_001_events_commit_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_commit_id_idx ON global.gd_001_events USING btree (commit_id);


--
-- Name: gd_001_events_entity_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_entity_id_idx ON global.gd_001_events USING btree (entity_id);


--
-- Name: gd_001_events_event_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_event_status_idx ON global.gd_001_events USING btree (event_status);


--
-- Name: gd_001_events_event_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_event_type_idx ON global.gd_001_events USING btree (event_type);


--
-- Name: gd_001_events_valid_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_valid_time_idx ON global.gd_001_events USING btree (valid_time);


--
-- Name: gd_004_exchange_rates_currency_pair_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_004_exchange_rates_currency_pair_idx ON global.gd_015_exchange_rates USING btree (base_currency, quote_currency);


--
-- Name: gd_004_exchange_rates_rate_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_004_exchange_rates_rate_code_idx ON global.gd_015_exchange_rates USING btree (rate_code);


--
-- Name: gd_004_exchange_rates_timestamp_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_004_exchange_rates_timestamp_idx ON global.gd_015_exchange_rates USING btree (rate_timestamp);


--
-- Name: gd_005_commit_records_commit_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_status_idx ON global.gd_005_commit_records USING btree (commit_status);


--
-- Name: gd_005_commit_records_commit_timestamp_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_timestamp_idx ON global.gd_005_commit_records USING btree (commit_timestamp);


--
-- Name: gd_005_commit_records_commit_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_type_idx ON global.gd_005_commit_records USING btree (commit_type);


--
-- Name: gd_005_commit_records_committing_authority_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_committing_authority_id_idx ON global.gd_005_commit_records USING btree (committing_authority_id);


--
-- Name: gd_005_inflation_rates_currency_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_inflation_rates_currency_idx ON global.gd_014_inflation_rates USING btree (currency_code);


--
-- Name: gd_005_inflation_rates_year_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_inflation_rates_year_idx ON global.gd_014_inflation_rates USING btree (applicable_year);


--
-- Name: gd_006_status_registry_status_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_006_status_registry_status_type_idx ON global.gd_006_status_registry USING btree (status_type);


--
-- Name: gd_007_people_country_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_country_code_idx ON global.gd_016_people USING btree (country_code);


--
-- Name: gd_007_people_last_name_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_last_name_idx ON global.gd_016_people USING btree (last_name);


--
-- Name: gd_007_people_tax_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_tax_id_idx ON global.gd_016_people USING btree (tax_id);


--
-- Name: gd_009_ruleset_lines_operation_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_009_ruleset_lines_operation_id_idx ON global.gd_003_ruleset_lines USING btree (operation_id);


--
-- Name: gd_009_ruleset_lines_ruleset_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_009_ruleset_lines_ruleset_id_idx ON global.gd_003_ruleset_lines USING btree (ruleset_id);


--
-- Name: gd_009_ruleset_lines_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_009_ruleset_lines_validity_idx ON global.gd_003_ruleset_lines USING btree (valid_from, valid_to);


--
-- Name: gd_011_exrate_codes_provider_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_011_exrate_codes_provider_idx ON global.gd_011_exrate_codes USING btree (provider);


--
-- Name: gd_013_governance_identities_identity_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_identity_status_idx ON global.gd_007_governance_identities USING btree (identity_status);


--
-- Name: gd_013_governance_identities_identity_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_identity_type_idx ON global.gd_007_governance_identities USING btree (identity_type);


--
-- Name: gd_013_governance_identities_valid_from_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_valid_from_idx ON global.gd_007_governance_identities USING btree (valid_from);


--
-- Name: gd_013_governance_identities_valid_to_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_valid_to_idx ON global.gd_007_governance_identities USING btree (valid_to);


--
-- Name: gd_017_naming_conventions_language_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_017_naming_conventions_language_idx ON global.gd_017_naming_conventions USING btree (translation_language);


--
-- Name: gd_017_naming_conventions_object_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_017_naming_conventions_object_idx ON global.gd_017_naming_conventions USING btree (object_type, object_id);


--
-- Name: gd_001_events gd_001_events_commit_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_commit_id_fk FOREIGN KEY (commit_id) REFERENCES global.gd_005_commit_records(commit_id);


--
-- Name: gd_005_commit_records gd_005_commit_records_committing_authority_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_commit_records
    ADD CONSTRAINT gd_005_commit_records_committing_authority_id_fk FOREIGN KEY (committing_authority_id) REFERENCES global.gd_007_governance_identities(governance_identity_id);


--
-- Name: gd_003_ruleset_lines gd_009_ruleset_lines_ruleset_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_003_ruleset_lines
    ADD CONSTRAINT gd_009_ruleset_lines_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES global.gd_002_ruleset_registry(ruleset_id);


--
-- PostgreSQL database dump complete
--

\unrestrict sHhMJZ9fkAhgtUlpUyUd0xxtYQfHMbVkustB4am6AwKiUreYTVETJBq3N6aRGP6

