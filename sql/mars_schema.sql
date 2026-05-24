--
-- PostgreSQL database dump
--

\restrict 38Z7YPgocTJw6fnP8RdqTw4fjNHzl4s9eQjtNhEisYk8UaJC3hygOXzH41Oc97S

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
-- Name: fn_is_entity_position(bigint); Type: FUNCTION; Schema: global; Owner: postgres
--

CREATE FUNCTION global.fn_is_entity_position(p_position_id bigint) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF p_position_id IS NULL THEN
        RETURN TRUE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM global.gd_027_positions
        WHERE position_id    = p_position_id
          AND position_class = 'entity_position'
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
    IF p_position_id IS NULL THEN
        RETURN TRUE;
    END IF;
    RETURN EXISTS (
        SELECT 1
        FROM global.gd_027_positions
        WHERE position_id    = p_position_id
          AND position_class = 'project_position'
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
        SELECT 1
        FROM global.gd_007_status_registry
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
        SELECT 1
        FROM global.gd_007_status_registry
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
    valid_time timestamp with time zone NOT NULL,
    assertion_time timestamp with time zone NOT NULL,
    entity_id bigint NOT NULL,
    governance_scope_id bigint,
    commit_id bigint NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    event_description text,
    event_status character varying(32) NOT NULL,
    corrective_of_event_id bigint,
    replay_sequence bigint NOT NULL,
    CONSTRAINT gd_001_events_assertion_time_chk CHECK ((assertion_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone)),
    CONSTRAINT gd_001_events_corrective_consistency_chk CHECK (((corrective_of_event_id IS NULL) OR ((corrective_of_event_id IS NOT NULL) AND ((event_type)::text = 'corrective'::text)))),
    CONSTRAINT gd_001_events_event_status_type_chk CHECK (global.fn_is_valid_event_status(event_status)),
    CONSTRAINT gd_001_events_valid_time_chk CHECK ((valid_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone))
);


ALTER TABLE global.gd_001_events OWNER TO postgres;

--
-- Name: COLUMN gd_001_events.corrective_of_event_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_001_events.corrective_of_event_id IS 'References the Event this Event additively corrects. NULL on original Events. Populated only on corrective Events. Original Events are never modified — correction linkage is carried exclusively by the corrective Event. May form a chain: each corrective Event points to its immediate predecessor in the correction history.';


--
-- Name: COLUMN gd_001_events.replay_sequence; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_001_events.replay_sequence IS 'Globally monotonic database-assigned sequence providing deterministic replay sub-ordering within and across commits. Assigned exclusively by the database — never by the application layer. Canonical replay ordering: ORDER BY commit_id, replay_sequence. Immutable after assignment.';


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
-- Name: gd_001_events_replay_sequence_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_001_events ALTER COLUMN replay_sequence ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME global.gd_001_events_replay_sequence_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_002_primitive_transitions; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_002_primitive_transitions (
    primitive_transition_id bigint NOT NULL,
    event_id bigint NOT NULL,
    entity_id bigint NOT NULL,
    account_code character varying(128) NOT NULL,
    transformation_direction character varying(32) NOT NULL,
    amount numeric(20,6) NOT NULL,
    currency_code character(3),
    valid_time timestamp with time zone NOT NULL,
    assertion_time timestamp with time zone NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    transition_description text,
    primitive_transition_type text CONSTRAINT gd_002_primitive_transitions_type_nn NOT NULL,
    CONSTRAINT gd_002_primitive_transitions_amount_chk CHECK ((amount >= (0)::numeric)),
    CONSTRAINT gd_002_primitive_transitions_assertion_time_chk CHECK ((assertion_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone)),
    CONSTRAINT gd_002_primitive_transitions_direction_chk CHECK (((transformation_direction)::text = ANY ((ARRAY['increase'::character varying, 'decrease'::character varying])::text[]))),
    CONSTRAINT gd_002_primitive_transitions_valid_time_chk CHECK ((valid_time >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone))
);


ALTER TABLE global.gd_002_primitive_transitions OWNER TO postgres;

--
-- Name: TABLE gd_002_primitive_transitions; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_002_primitive_transitions IS 'Canonical atomic state mutations participating in deterministic replay and organizational reconstruction.';


--
-- Name: COLUMN gd_002_primitive_transitions.primitive_transition_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.primitive_transition_id IS 'Stable internal identity of primitive transition.';


--
-- Name: COLUMN gd_002_primitive_transitions.event_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.event_id IS 'References originating Event producing primitive state mutation.';


--
-- Name: COLUMN gd_002_primitive_transitions.entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.entity_id IS 'Organizational entity whose state is affected by primitive transition.';


--
-- Name: COLUMN gd_002_primitive_transitions.account_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.account_code IS 'Accounting state topology element affected by primitive transition.';


--
-- Name: COLUMN gd_002_primitive_transitions.transformation_direction; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.transformation_direction IS 'Canonical polarity of primitive organizational state mutation.';


--
-- Name: COLUMN gd_002_primitive_transitions.amount; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.amount IS 'Quantitative magnitude of primitive state mutation.';


--
-- Name: COLUMN gd_002_primitive_transitions.currency_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.currency_code IS 'Currency applicable to quantitative mutation where relevant.';


--
-- Name: COLUMN gd_002_primitive_transitions.valid_time; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.valid_time IS 'Business-effective timestamp of primitive transition applicability.';


--
-- Name: COLUMN gd_002_primitive_transitions.assertion_time; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.assertion_time IS 'Timestamp at which primitive transition became known to the system.';


--
-- Name: COLUMN gd_002_primitive_transitions.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.created_by IS 'Infrastructure actor responsible for physical insertion of primitive transition.';


--
-- Name: COLUMN gd_002_primitive_transitions.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.created_at IS 'Physical insertion timestamp of primitive transition.';


--
-- Name: COLUMN gd_002_primitive_transitions.transition_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.transition_description IS 'Human-readable explanation of primitive transition semantics.';


--
-- Name: COLUMN gd_002_primitive_transitions.primitive_transition_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_002_primitive_transitions.primitive_transition_type IS 'Canonical type of this Primitive Transition. Determines replay stream participation. References gd_019_pt_types.pt_type_code.';


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

ALTER SEQUENCE global.gd_002_primitive_transitions_primitive_transition_id_seq OWNED BY global.gd_002_primitive_transitions.primitive_transition_id;


--
-- Name: gd_003_ruleset_registry; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_003_ruleset_registry (
    ruleset_id character varying(128) CONSTRAINT gd_008_ruleset_registry_ruleset_id_not_null NOT NULL,
    ruleset_name character varying(256) CONSTRAINT gd_008_ruleset_registry_ruleset_name_not_null NOT NULL,
    ruleset_type character varying(64) CONSTRAINT gd_008_ruleset_registry_ruleset_type_not_null NOT NULL,
    ruleset_description text,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_008_ruleset_registry_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_008_ruleset_registry_valid_to_not_null NOT NULL,
    governance_scope_id bigint,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_008_ruleset_registry_created_at_not_null NOT NULL,
    CONSTRAINT gd_008_ruleset_registry_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_003_ruleset_registry OWNER TO postgres;

--
-- Name: TABLE gd_003_ruleset_registry; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_003_ruleset_registry IS 'Canonical registry of governance-approved Rulesets participating in deterministic reconstruction and replay.';


--
-- Name: COLUMN gd_003_ruleset_registry.ruleset_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.ruleset_id IS 'Stable canonical Ruleset identity.';


--
-- Name: COLUMN gd_003_ruleset_registry.ruleset_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.ruleset_name IS 'Human-readable Ruleset name.';


--
-- Name: COLUMN gd_003_ruleset_registry.ruleset_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.ruleset_type IS 'Canonical Ruleset classification.';


--
-- Name: COLUMN gd_003_ruleset_registry.ruleset_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.ruleset_description IS 'Human-readable Ruleset explanation and applicability notes.';


--
-- Name: COLUMN gd_003_ruleset_registry.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.valid_from IS 'Beginning of Ruleset applicability interval.';


--
-- Name: COLUMN gd_003_ruleset_registry.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.valid_to IS 'End of Ruleset applicability interval.';


--
-- Name: COLUMN gd_003_ruleset_registry.governance_scope_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.governance_scope_id IS 'Governance applicability scope participating in Ruleset authorization and replay semantics.';


--
-- Name: COLUMN gd_003_ruleset_registry.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.created_by IS 'Infrastructure actor responsible for physical Ruleset registration.';


--
-- Name: COLUMN gd_003_ruleset_registry.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_003_ruleset_registry.created_at IS 'Physical insertion timestamp of Ruleset registry record.';


--
-- Name: gd_004_entities; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_004_entities (
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
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_003_entities_created_at_not_null NOT NULL,
    CONSTRAINT gd_003_entities_identity_chk CHECK (((vat_id IS NOT NULL) OR (tax_id IS NOT NULL) OR (normalized_name IS NOT NULL))),
    CONSTRAINT gd_003_entities_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_004_entities OWNER TO postgres;

--
-- Name: TABLE gd_004_entities; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_004_entities IS 'Canonical registry of organizational entities participating in deterministic replay, governance reconstruction and operational interpretation.';


--
-- Name: COLUMN gd_004_entities.entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.entity_id IS 'Stable internal identity of organizational entity.';


--
-- Name: COLUMN gd_004_entities.entity_reg_number; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.entity_reg_number IS 'Canonical registration identifier assigned to organizational entity.';


--
-- Name: COLUMN gd_004_entities.country_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.country_code IS 'Jurisdictional country code associated with organizational entity registration.';


--
-- Name: COLUMN gd_004_entities.legal_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.legal_name IS 'Official legal designation of organizational entity.';


--
-- Name: COLUMN gd_004_entities.normalized_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.normalized_name IS 'Normalized searchable representation of organizational entity name used for deterministic matching and deduplication.';


--
-- Name: COLUMN gd_004_entities.tax_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.tax_id IS 'Jurisdictional taxpayer identification reference of organizational entity.';


--
-- Name: COLUMN gd_004_entities.vat_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.vat_id IS 'Jurisdictional VAT registration reference of organizational entity.';


--
-- Name: COLUMN gd_004_entities.legal_address; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.legal_address IS 'Registered legal address of organizational entity.';


--
-- Name: COLUMN gd_004_entities.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.valid_from IS 'Beginning of organizational entity applicability interval.';


--
-- Name: COLUMN gd_004_entities.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.valid_to IS 'End of organizational entity applicability interval.';


--
-- Name: COLUMN gd_004_entities.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.created_by IS 'Infrastructure actor responsible for physical insertion of entity record.';


--
-- Name: COLUMN gd_004_entities.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_004_entities.created_at IS 'Physical insertion timestamp of entity record.';


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

ALTER SEQUENCE global.gd_004_entities_entity_id_seq OWNED BY global.gd_004_entities.entity_id;


--
-- Name: gd_005_ruleset_lines; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_005_ruleset_lines (
    line_id bigint CONSTRAINT gd_009_ruleset_lines_line_id_not_null NOT NULL,
    ruleset_id character varying(128) CONSTRAINT gd_009_ruleset_lines_ruleset_id_not_null NOT NULL,
    entity_1_id bigint,
    entity_2_id bigint,
    trf_direction character varying(32) CONSTRAINT gd_009_ruleset_lines_trf_direction_not_null NOT NULL,
    amount numeric(20,6),
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_009_ruleset_lines_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_009_ruleset_lines_valid_to_not_null NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_009_ruleset_lines_created_at_not_null NOT NULL,
    line_description text,
    account_code character varying(128),
    CONSTRAINT gd_009_ruleset_lines_transformation_direction_chk CHECK (((trf_direction)::text = ANY ((ARRAY['increase'::character varying, 'decrease'::character varying, 'recognize'::character varying, 'derecognize'::character varying, 'transfer_in'::character varying, 'transfer_out'::character varying, 'debit'::character varying, 'credit'::character varying])::text[]))),
    CONSTRAINT gd_009_ruleset_lines_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_005_ruleset_lines OWNER TO postgres;

--
-- Name: COLUMN gd_005_ruleset_lines.entity_1_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_005_ruleset_lines.entity_1_id IS 'Primary organizational entity this Ruleset line applies to. Nullable — not all Ruleset lines are entity-scoped. References gd_004_entities.entity_id.';


--
-- Name: COLUMN gd_005_ruleset_lines.entity_2_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_005_ruleset_lines.entity_2_id IS 'Secondary organizational entity this Ruleset line applies to. Used for inter-entity rules such as intercompany transfers. Nullable. References gd_004_entities.entity_id.';


--
-- Name: COLUMN gd_005_ruleset_lines.account_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_005_ruleset_lines.account_code IS 'Chart of Accounts identifier this Ruleset line applies to. Nullable — not all Ruleset lines are account-scoped. References gd_016_coa.account_code.';


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

ALTER SEQUENCE global.gd_005_ruleset_lines_line_id_seq OWNED BY global.gd_005_ruleset_lines.line_id;


--
-- Name: gd_006_commit_records; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_006_commit_records (
    commit_id bigint CONSTRAINT gd_005_commit_records_commit_id_not_null NOT NULL,
    commit_timestamp timestamp with time zone CONSTRAINT gd_005_commit_records_commit_timestamp_not_null NOT NULL,
    committing_authority_id bigint CONSTRAINT gd_005_commit_records_committing_authority_id_not_null NOT NULL,
    commit_type character varying(64) CONSTRAINT gd_005_commit_records_commit_type_not_null NOT NULL,
    commit_reason text,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_005_commit_records_created_at_not_null NOT NULL,
    commit_status character varying(32) CONSTRAINT gd_005_commit_records_commit_status_not_null NOT NULL,
    CONSTRAINT gd_006_commit_records_commit_status_chk CHECK (global.fn_is_valid_commit_status(commit_status)),
    CONSTRAINT gd_006_commit_records_commit_timestamp_chk CHECK ((commit_timestamp >= '1901-01-01 02:02:04+02:02:04'::timestamp with time zone))
);


ALTER TABLE global.gd_006_commit_records OWNER TO postgres;

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

ALTER SEQUENCE global.gd_006_commit_records_commit_id_seq OWNED BY global.gd_006_commit_records.commit_id;


--
-- Name: gd_007_status_registry; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_007_status_registry (
    status_code character varying(32) CONSTRAINT gd_006_event_status_registry_event_status_code_not_null NOT NULL,
    status_name character varying(128) CONSTRAINT gd_006_event_status_registry_event_status_name_not_null NOT NULL,
    status_description text,
    is_authoritative_replay_eligible boolean DEFAULT false CONSTRAINT gd_006_event_status_registr_is_authoritative_replay_el_not_null NOT NULL,
    is_terminal boolean DEFAULT false CONSTRAINT gd_006_event_status_registry_is_terminal_not_null NOT NULL,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_006_event_status_registry_created_at_not_null NOT NULL,
    status_type character varying(64) DEFAULT 'event_status'::character varying CONSTRAINT gd_006_status_registry_status_type_not_null NOT NULL
);


ALTER TABLE global.gd_007_status_registry OWNER TO postgres;

--
-- Name: gd_008_governance_identities; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_008_governance_identities (
    governance_identity_id bigint CONSTRAINT gd_013_governance_identities_governance_identity_id_not_null NOT NULL,
    identity_type character varying(64) CONSTRAINT gd_013_governance_identities_identity_type_not_null NOT NULL,
    identity_name character varying(256) CONSTRAINT gd_013_governance_identities_identity_name_not_null NOT NULL,
    identity_code character varying(128) CONSTRAINT gd_013_governance_identities_identity_code_not_null NOT NULL,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_013_governance_identities_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_013_governance_identities_valid_to_not_null NOT NULL,
    identity_status character varying(32) CONSTRAINT gd_013_governance_identities_identity_status_not_null NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_013_governance_identities_created_at_not_null NOT NULL,
    identity_description text,
    CONSTRAINT gd_013_governance_identities_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_008_governance_identities OWNER TO postgres;

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

ALTER SEQUENCE global.gd_008_governance_identities_governance_identity_id_seq OWNED BY global.gd_008_governance_identities.governance_identity_id;


--
-- Name: gd_011_holidays; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_011_holidays (
    holiday_id bigint NOT NULL,
    country_code character(2) NOT NULL,
    holiday_name character varying(256) NOT NULL,
    holiday_type character varying(64) NOT NULL,
    holiday_date date NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE global.gd_011_holidays OWNER TO postgres;

--
-- Name: TABLE gd_011_holidays; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_011_holidays IS 'Canonical registry of jurisdictional and organizational holidays participating in deterministic replay, scheduling and governance timing semantics.';


--
-- Name: COLUMN gd_011_holidays.holiday_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_holidays.holiday_id IS 'Stable internal identity of holiday record.';


--
-- Name: COLUMN gd_011_holidays.country_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_holidays.country_code IS 'Jurisdictional country code associated with holiday applicability.';


--
-- Name: COLUMN gd_011_holidays.holiday_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_holidays.holiday_name IS 'Human-readable designation of holiday.';


--
-- Name: COLUMN gd_011_holidays.holiday_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_holidays.holiday_type IS 'Canonical classification of holiday applicability and governance semantics.';


--
-- Name: COLUMN gd_011_holidays.holiday_date; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_holidays.holiday_date IS 'Calendar date on which holiday becomes applicable.';


--
-- Name: COLUMN gd_011_holidays.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_holidays.created_by IS 'Infrastructure actor responsible for physical insertion of holiday record.';


--
-- Name: COLUMN gd_011_holidays.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_011_holidays.created_at IS 'Physical insertion timestamp of holiday record.';


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

ALTER SEQUENCE global.gd_011_holidays_holiday_id_seq OWNED BY global.gd_011_holidays.holiday_id;


--
-- Name: gd_012_currency_registry; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_012_currency_registry (
    currency_id bigint NOT NULL,
    currency_name character varying(128) NOT NULL,
    iso_alpha_2 character(2),
    iso_alpha_3 character(3) NOT NULL,
    currency_symbol character varying(16),
    issuing_jurisdiction character varying(128),
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gd_012_currency_registry_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_012_currency_registry OWNER TO postgres;

--
-- Name: TABLE gd_012_currency_registry; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_012_currency_registry IS 'Canonical registry of currencies participating in deterministic replay, valuation and financial reconstruction.';


--
-- Name: COLUMN gd_012_currency_registry.currency_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.currency_id IS 'Stable internal identity of currency record.';


--
-- Name: COLUMN gd_012_currency_registry.currency_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.currency_name IS 'Human-readable canonical currency name.';


--
-- Name: COLUMN gd_012_currency_registry.iso_alpha_2; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.iso_alpha_2 IS 'Two-letter canonical currency abbreviation where applicable.';


--
-- Name: COLUMN gd_012_currency_registry.iso_alpha_3; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.iso_alpha_3 IS 'Three-letter ISO currency code used in replay and reporting semantics.';


--
-- Name: COLUMN gd_012_currency_registry.currency_symbol; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.currency_symbol IS 'Human-readable symbol representing currency in disclosure and reporting contexts.';


--
-- Name: COLUMN gd_012_currency_registry.issuing_jurisdiction; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.issuing_jurisdiction IS 'Jurisdiction or authority associated with currency issuance.';


--
-- Name: COLUMN gd_012_currency_registry.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.valid_from IS 'Beginning of currency applicability interval.';


--
-- Name: COLUMN gd_012_currency_registry.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.valid_to IS 'End of currency applicability interval.';


--
-- Name: COLUMN gd_012_currency_registry.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.created_by IS 'Infrastructure actor responsible for physical insertion of currency record.';


--
-- Name: COLUMN gd_012_currency_registry.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_012_currency_registry.created_at IS 'Physical insertion timestamp of currency record.';


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

ALTER SEQUENCE global.gd_012_currency_registry_currency_id_seq OWNED BY global.gd_012_currency_registry.currency_id;


--
-- Name: gd_013_people; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_013_people (
    person_id bigint CONSTRAINT gd_007_people_person_id_not_null NOT NULL,
    person_code character varying(128),
    first_name character varying(128) CONSTRAINT gd_007_people_first_name_not_null NOT NULL,
    middle_name character varying(128),
    last_name character varying(128) CONSTRAINT gd_007_people_last_name_not_null NOT NULL,
    tax_id character varying(128),
    date_of_birth date,
    country_code character(2),
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_007_people_valid_from_not_null NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_007_people_valid_to_not_null NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_007_people_created_at_not_null NOT NULL,
    CONSTRAINT gd_007_people_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_013_people OWNER TO postgres;

--
-- Name: TABLE gd_013_people; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_013_people IS 'Canonical registry of real-world persons participating in organizational reconstruction and governance relations.';


--
-- Name: COLUMN gd_013_people.person_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.person_id IS 'Stable internal identity of person record.';


--
-- Name: COLUMN gd_013_people.person_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.person_code IS 'Canonical external or organizational identifier of person.';


--
-- Name: COLUMN gd_013_people.first_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.first_name IS 'Registered first name of person.';


--
-- Name: COLUMN gd_013_people.middle_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.middle_name IS 'Registered middle name of person.';


--
-- Name: COLUMN gd_013_people.last_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.last_name IS 'Registered last name of person.';


--
-- Name: COLUMN gd_013_people.tax_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.tax_id IS 'Jurisdictional taxpayer or national identification reference of person.';


--
-- Name: COLUMN gd_013_people.date_of_birth; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.date_of_birth IS 'Declared date of birth of person.';


--
-- Name: COLUMN gd_013_people.country_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.country_code IS 'Canonical country code associated with person record.';


--
-- Name: COLUMN gd_013_people.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.valid_from IS 'Beginning of person record applicability interval.';


--
-- Name: COLUMN gd_013_people.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.valid_to IS 'End of person record applicability interval.';


--
-- Name: COLUMN gd_013_people.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.created_by IS 'Infrastructure actor responsible for physical insertion of person record.';


--
-- Name: COLUMN gd_013_people.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_013_people.created_at IS 'Physical insertion timestamp of person record.';


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

ALTER SEQUENCE global.gd_013_people_person_id_seq OWNED BY global.gd_013_people.person_id;


--
-- Name: gd_014_inflation_rates; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_014_inflation_rates (
    inflation_rate_id bigint CONSTRAINT gd_014_inflation_rates_inflation_rate_id_nn NOT NULL,
    applicable_year integer CONSTRAINT gd_014_inflation_rates_applicable_year_nn NOT NULL,
    currency_code character(3) CONSTRAINT gd_014_inflation_rates_currency_code_nn NOT NULL,
    inflation_rate numeric(10,6) CONSTRAINT gd_014_inflation_rates_inflation_rate_nn NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_014_inflation_rates_created_at_nn NOT NULL,
    rate_reference character varying(128),
    CONSTRAINT gd_014_inflation_rates_rate_range_chk CHECK (((inflation_rate >= ('-100'::integer)::numeric) AND (inflation_rate <= (1000000)::numeric))),
    CONSTRAINT gd_014_inflation_rates_year_chk CHECK (((applicable_year >= 1900) AND (applicable_year <= 3000)))
);


ALTER TABLE global.gd_014_inflation_rates OWNER TO postgres;

--
-- Name: COLUMN gd_014_inflation_rates.rate_reference; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_014_inflation_rates.rate_reference IS 'Canonical identifier of the data source used to establish this rate. References gd_018_rate_codes. Nullable pending governance consensus on acceptable source registry for historical rows.';


--
-- Name: gd_014_inflation_rates_inflation_rate_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_014_inflation_rates ALTER COLUMN inflation_rate_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_014_inflation_rates_inflation_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_015_exchange_rates; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_015_exchange_rates (
    rate_id bigint CONSTRAINT gd_004_exchange_rates_rate_id_not_null NOT NULL,
    rate_timestamp timestamp with time zone CONSTRAINT gd_004_exchange_rates_rate_timestamp_not_null NOT NULL,
    base_currency character(3) CONSTRAINT gd_004_exchange_rates_base_currency_not_null NOT NULL,
    quote_currency character(3) CONSTRAINT gd_004_exchange_rates_quote_currency_not_null NOT NULL,
    exchange_rate numeric(18,6) CONSTRAINT gd_004_exchange_rates_exchange_rate_not_null NOT NULL,
    rate_code character varying(64)
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

ALTER SEQUENCE global.gd_015_exchange_rates_rate_id_seq OWNED BY global.gd_015_exchange_rates.rate_id;


--
-- Name: gd_016_coa; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_016_coa (
    account_code character varying(128) NOT NULL,
    ruleset_id character varying(128) NOT NULL,
    parent_account_code character varying(128),
    account_name character varying(256) NOT NULL,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone NOT NULL,
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gd_016_coa_valid_range_chk CHECK ((valid_to >= valid_from))
);


ALTER TABLE global.gd_016_coa OWNER TO postgres;

--
-- Name: TABLE gd_016_coa; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_016_coa IS 'Canonical accounting state topology participating in deterministic replay and accounting reconstruction.';


--
-- Name: COLUMN gd_016_coa.account_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.account_code IS 'Stable canonical accounting topology identifier.';


--
-- Name: COLUMN gd_016_coa.ruleset_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.ruleset_id IS 'Ruleset governing accounting interpretation applicability of account.';


--
-- Name: COLUMN gd_016_coa.parent_account_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.parent_account_code IS 'Parent accounting topology element used for hierarchical reconstruction and aggregation.';


--
-- Name: COLUMN gd_016_coa.account_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.account_name IS 'Human-readable accounting topology designation.';


--
-- Name: COLUMN gd_016_coa.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.valid_from IS 'Beginning of accounting topology applicability interval.';


--
-- Name: COLUMN gd_016_coa.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.valid_to IS 'End of accounting topology applicability interval.';


--
-- Name: COLUMN gd_016_coa.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.created_by IS 'Infrastructure actor responsible for physical insertion of accounting topology record.';


--
-- Name: COLUMN gd_016_coa.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_016_coa.created_at IS 'Physical insertion timestamp of accounting topology record.';


--
-- Name: gd_017_naming_conventions; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_017_naming_conventions (
    naming_id bigint NOT NULL,
    object_type character varying(128) NOT NULL,
    object_ref text CONSTRAINT gd_017_naming_conventions_object_id_not_null NOT NULL,
    canonical_name character varying(256) NOT NULL,
    translation_language character(2) NOT NULL,
    translated_name character varying(256) NOT NULL,
    translation_context character varying(128),
    created_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL
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
-- Name: COLUMN gd_017_naming_conventions.object_ref; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_017_naming_conventions.object_ref IS 'Primary key value of the referenced object, stored as text. Holds stringified integer PKs (e.g. ''42'') for bigint-keyed tables and varchar PKs as-is (e.g. ''ACC-001-CASH'') for text-keyed tables such as gd_016_coa. Interpreted in conjunction with object_type. No FK enforcement — polymorphic references cannot be constrained at the database level.';


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
-- Name: gd_018_rate_codes; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_018_rate_codes (
    rate_code text NOT NULL,
    rate_name text NOT NULL,
    rate_type text NOT NULL,
    provider text,
    description text
);


ALTER TABLE global.gd_018_rate_codes OWNER TO postgres;

--
-- Name: gd_019_pt_types; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_019_pt_types (
    pt_type_code text CONSTRAINT gd_019_pt_types_pt_type_code_nn NOT NULL,
    pt_type_name text CONSTRAINT gd_019_pt_types_pt_type_name_nn NOT NULL,
    description text
);


ALTER TABLE global.gd_019_pt_types OWNER TO postgres;

--
-- Name: TABLE gd_019_pt_types; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_019_pt_types IS 'Canonical registry of Primitive Transition types as defined in Doc 19. Determines which reconstruction stream a Primitive Transition participates in.';


--
-- Name: COLUMN gd_019_pt_types.pt_type_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_019_pt_types.pt_type_code IS 'Stable short identifier referenced by gd_002_primitive_transitions.primitive_transition_type.';


--
-- Name: COLUMN gd_019_pt_types.pt_type_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_019_pt_types.pt_type_name IS 'Full canonical name of the Primitive Transition type.';


--
-- Name: COLUMN gd_019_pt_types.description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_019_pt_types.description IS 'Scope of mutations belonging to this type and their replay participation semantics.';


--
-- Name: gd_020_scenarios; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_020_scenarios (
    scenario_id bigint CONSTRAINT gd_020_scenarios_scenario_id_nn NOT NULL,
    scenario_name text CONSTRAINT gd_020_scenarios_scenario_name_nn NOT NULL,
    scenario_description text,
    base_date date CONSTRAINT gd_020_scenarios_base_date_nn NOT NULL,
    created_by text,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_020_scenarios_created_at_nn NOT NULL
);


ALTER TABLE global.gd_020_scenarios OWNER TO postgres;

--
-- Name: TABLE gd_020_scenarios; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_020_scenarios IS 'Header registry of named future projection scenarios. A Scenario is a branch of hypothetical future reality anchored at base_date. All values before base_date are authoritative and immutable. Hypothetical future values in variable tables are tagged with scenario_id.';


--
-- Name: COLUMN gd_020_scenarios.scenario_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_020_scenarios.scenario_id IS 'Stable surrogate identity of the scenario. Referenced as scenario_id in all scenario-tagged variable rows.';


--
-- Name: COLUMN gd_020_scenarios.scenario_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_020_scenarios.scenario_name IS 'Short unique human-readable name identifying this scenario.';


--
-- Name: COLUMN gd_020_scenarios.scenario_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_020_scenarios.scenario_description IS 'Narrative description of the assumptions adopted in this scenario.';


--
-- Name: COLUMN gd_020_scenarios.base_date; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_020_scenarios.base_date IS 'Temporal anchor from which this scenario projects forward. All hypothetical values tagged to this scenario must have applicable periods strictly after base_date.';


--
-- Name: COLUMN gd_020_scenarios.created_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_020_scenarios.created_by IS 'Actor who defined this scenario.';


--
-- Name: COLUMN gd_020_scenarios.created_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_020_scenarios.created_at IS 'Physical insertion timestamp of this scenario header.';


--
-- Name: gd_020_scenarios_scenario_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_020_scenarios ALTER COLUMN scenario_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_020_scenarios_scenario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_021_proposals; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_021_proposals (
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
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_021_proposals_created_at_nn NOT NULL,
    CONSTRAINT gd_021_proposals_proposal_status_chk CHECK ((proposal_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'superseded'::text, 'archived'::text]))),
    CONSTRAINT gd_021_proposals_proposal_type_chk CHECK ((proposal_type = ANY (ARRAY['corrective'::text, 'governance'::text, 'disclosure'::text, 'analytical'::text, 'operational'::text]))),
    CONSTRAINT gd_021_proposals_review_consistency_chk CHECK ((((reviewed_by IS NULL) AND (reviewed_at IS NULL)) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL)))),
    CONSTRAINT gd_021_proposals_source_type_chk CHECK ((source_type = ANY (ARRAY['ai_analysis'::text, 'anomaly_detection'::text, 'replay_analysis'::text, 'scenario_analysis'::text, 'governance_escalation'::text, 'disclosure_review'::text, 'manual'::text])))
);


ALTER TABLE global.gd_021_proposals OWNER TO postgres;

--
-- Name: TABLE gd_021_proposals; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_021_proposals IS 'Canonical landing zone for governance-reviewable candidate organizational mutations. Non-authoritative until governance-recognized authoritative commit occurs. Interim structure: proposal_payload is JSONB pending stabilization of per-category typed schemas.';


--
-- Name: COLUMN gd_021_proposals.proposal_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.proposal_type IS 'Category of mutation being proposed. Governs interpretation of proposal_payload.';


--
-- Name: COLUMN gd_021_proposals.proposal_status; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.proposal_status IS 'Lifecycle state. Proposals move from pending → approved/rejected/superseded.';


--
-- Name: COLUMN gd_021_proposals.source_type; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.source_type IS 'What produced this proposal — AI pipeline, escalation, manual, etc.';


--
-- Name: COLUMN gd_021_proposals.source_ref; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.source_ref IS 'Free-text reference to the specific source artifact or process run.';


--
-- Name: COLUMN gd_021_proposals.entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.entity_id IS 'Organizational entity this proposal concerns. Nullable — not all proposals are entity-scoped.';


--
-- Name: COLUMN gd_021_proposals.scenario_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.scenario_id IS 'Scenario context when proposal derives from scenario projection analysis.';


--
-- Name: COLUMN gd_021_proposals.proposal_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.proposal_description IS 'Human-readable statement of what is being proposed and the basis for it.';


--
-- Name: COLUMN gd_021_proposals.proposal_payload; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.proposal_payload IS 'Structured mutation details. Shape varies by proposal_type. Interim JSONB — to be replaced by typed per-category structures once payload schemas are confirmed stable.';


--
-- Name: COLUMN gd_021_proposals.generated_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.generated_by IS 'Identity of the actor or system that generated this proposal.';


--
-- Name: COLUMN gd_021_proposals.reviewed_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.reviewed_by IS 'Governance identity that reviewed this proposal. Null until reviewed.';


--
-- Name: COLUMN gd_021_proposals.reviewed_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.reviewed_at IS 'Timestamp of governance review. Null until reviewed.';


--
-- Name: COLUMN gd_021_proposals.review_notes; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.review_notes IS 'Reviewer commentary — rationale for approval, rejection, or conditions.';


--
-- Name: COLUMN gd_021_proposals.superseded_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_021_proposals.superseded_by IS 'References the proposal that supersedes this one. Superseded proposals remain reconstructable per additive correction doctrine.';


--
-- Name: gd_021_proposals_proposal_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_021_proposals ALTER COLUMN proposal_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_021_proposals_proposal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_022_delegations; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_022_delegations (
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
    created_by text,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_022_delegations_created_at_nn NOT NULL,
    CONSTRAINT gd_022_delegations_revocation_consistency_chk CHECK ((((revoked_at IS NULL) AND (revoked_by IS NULL)) OR ((revoked_at IS NOT NULL) AND (revoked_by IS NOT NULL)))),
    CONSTRAINT gd_022_delegations_revocation_temporal_chk CHECK (((revoked_at IS NULL) OR (revoked_at >= valid_from))),
    CONSTRAINT gd_022_delegations_scope_chk CHECK ((delegation_scope = ANY (ARRAY['authoritative_commit'::text, 'replay_execution'::text, 'disclosure_authorization'::text, 'delegation_issuance'::text, 'escalation_handling'::text, 'scenario_execution'::text]))),
    CONSTRAINT gd_022_delegations_self_delegation_chk CHECK ((delegator_id <> delegatee_id)),
    CONSTRAINT gd_022_delegations_temporal_chk CHECK ((valid_from < valid_to))
);


ALTER TABLE global.gd_022_delegations OWNER TO postgres;

--
-- Name: TABLE gd_022_delegations; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_022_delegations IS 'Canonical registry of governance delegations per Doc 21 §6. Delegation represents bounded governance-authorized transfer of limited authority scope. Delegations are explicit, revocable, temporally scoped, reconstructable, and non-inheritable. Expired and revoked delegations are never deleted — historical reconstructability must be preserved.';


--
-- Name: COLUMN gd_022_delegations.delegator_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.delegator_id IS 'Governance identity issuing the delegation. Must hold the authority being delegated at time of issuance.';


--
-- Name: COLUMN gd_022_delegations.delegatee_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.delegatee_id IS 'Governance identity receiving the delegation. Cannot be the same as delegator_id.';


--
-- Name: COLUMN gd_022_delegations.delegation_scope; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.delegation_scope IS 'Bounded authority category being transferred. Constrained to the six authorization categories defined in Doc 21 §5.1. Scope remains explicitly bounded — delegation does not grant unrestricted authority.';


--
-- Name: COLUMN gd_022_delegations.entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.entity_id IS 'Organizational entity this delegation is scoped to. NULL denotes an organisation-wide delegation not bounded to a single entity.';


--
-- Name: COLUMN gd_022_delegations.valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.valid_from IS 'Timestamp from which the delegation becomes effective.';


--
-- Name: COLUMN gd_022_delegations.valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.valid_to IS 'Timestamp at which the delegation expires. Defaults to effectively unbounded (3001-12-31). Expiry does not destroy historical reconstructability.';


--
-- Name: COLUMN gd_022_delegations.revoked_at; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.revoked_at IS 'Timestamp of explicit revocation. NULL while delegation is active. Revocation is recorded additively — the row is never deleted.';


--
-- Name: COLUMN gd_022_delegations.revoked_by; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.revoked_by IS 'Identity that performed the revocation. Must be populated together with revoked_at.';


--
-- Name: COLUMN gd_022_delegations.delegation_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_022_delegations.delegation_description IS 'Human-readable statement of scope boundaries, conditions, and governance context of this delegation.';


--
-- Name: gd_022_delegations_delegation_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_022_delegations ALTER COLUMN delegation_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_022_delegations_delegation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_023_event_types; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_023_event_types (
    event_type_code text CONSTRAINT gd_023_event_types_code_nn NOT NULL,
    event_type_name text CONSTRAINT gd_023_event_types_name_nn NOT NULL,
    description text
);


ALTER TABLE global.gd_023_event_types OWNER TO postgres;

--
-- Name: TABLE gd_023_event_types; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_023_event_types IS 'Canonical registry of Event types as defined in Doc 19 §5. Referenced by gd_001_events.event_type. Extending the type set requires only an INSERT — no DDL on gd_001_events.';


--
-- Name: COLUMN gd_023_event_types.event_type_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_023_event_types.event_type_code IS 'Stable short identifier referenced by gd_001_events.event_type.';


--
-- Name: COLUMN gd_023_event_types.event_type_name; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_023_event_types.event_type_name IS 'Full canonical name of the Event type per Doc 19.';


--
-- Name: COLUMN gd_023_event_types.description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_023_event_types.description IS 'Scope of Events belonging to this type and their replay participation semantics.';


--
-- Name: gd_024_legal_arrangement_types; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_024_legal_arrangement_types (
    arrangement_type_code text CONSTRAINT gd_024_lat_code_nn NOT NULL,
    arrangement_type_name text CONSTRAINT gd_024_lat_name_nn NOT NULL,
    arrangement_category text CONSTRAINT gd_024_lat_category_nn NOT NULL,
    jurisdiction_code character(2),
    description text,
    CONSTRAINT gd_024_lat_category_chk CHECK ((arrangement_category = ANY (ARRAY['employment'::text, 'fop'::text, 'civil_contract'::text, 'secondment'::text, 'management_contract'::text, 'advisory'::text, 'internship'::text])))
);


ALTER TABLE global.gd_024_legal_arrangement_types OWNER TO postgres;

--
-- Name: TABLE gd_024_legal_arrangement_types; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_024_legal_arrangement_types IS 'Registry of legal arrangement types governing human engagement. arrangement_category determines financial reconstruction semantics (payroll obligations, tax treatment, social contributions).';


--
-- Name: COLUMN gd_024_legal_arrangement_types.arrangement_type_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_024_legal_arrangement_types.arrangement_type_code IS 'Stable short identifier referenced by gd_026_teammembers.';


--
-- Name: COLUMN gd_024_legal_arrangement_types.arrangement_category; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_024_legal_arrangement_types.arrangement_category IS 'Broad category governing financial and governance reconstruction semantics.';


--
-- Name: COLUMN gd_024_legal_arrangement_types.jurisdiction_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_024_legal_arrangement_types.jurisdiction_code IS 'ISO 3166-1 alpha-2 country code of the governing legal jurisdiction. Null for jurisdiction-agnostic types (secondment, advisory).';


--
-- Name: gd_025_projects; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_025_projects (
    project_id bigint CONSTRAINT gd_025_projects_project_id_nn NOT NULL,
    project_code text CONSTRAINT gd_025_projects_project_code_nn NOT NULL,
    project_name text CONSTRAINT gd_025_projects_project_name_nn NOT NULL,
    entity_id bigint,
    project_owner_id bigint,
    description text,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_025_projects_valid_from_nn NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_025_projects_valid_to_nn NOT NULL,
    created_by text,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_025_projects_created_at_nn NOT NULL,
    CONSTRAINT gd_025_projects_temporal_chk CHECK ((valid_from < valid_to))
);


ALTER TABLE global.gd_025_projects OWNER TO postgres;

--
-- Name: TABLE gd_025_projects; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_025_projects IS 'Project registry. Each row represents a named organizational project. Referenced by gd_026_teammembers for project allocation tracking.';


--
-- Name: COLUMN gd_025_projects.project_code; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_025_projects.project_code IS 'Short stable human-readable code (e.g. ''Astra'', ''Delta'').';


--
-- Name: COLUMN gd_025_projects.entity_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_025_projects.entity_id IS 'Entity that owns or runs this project. Nullable for cross-entity projects.';


--
-- Name: COLUMN gd_025_projects.project_owner_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_025_projects.project_owner_id IS 'Person responsible for this project. FK to gd_013_people — ownership is a person-level attribute, not tied to a specific arrangement.';


--
-- Name: gd_025_projects_project_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_025_projects ALTER COLUMN project_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_025_projects_project_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_026_teammembers; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_026_teammembers (
    arrangement_id bigint CONSTRAINT gd_026_tm_arrangement_id_nn NOT NULL,
    person_id bigint CONSTRAINT gd_026_tm_person_id_nn NOT NULL,
    entity_id bigint CONSTRAINT gd_026_tm_entity_id_nn NOT NULL,
    arrangement_type_code text CONSTRAINT gd_026_tm_type_nn NOT NULL,
    arrangement_valid_from timestamp with time zone CONSTRAINT gd_026_tm_arr_from_nn NOT NULL,
    arrangement_valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_026_tm_arr_to_nn NOT NULL,
    project_id bigint,
    time_allocation numeric(5,4) DEFAULT 1.0 CONSTRAINT gd_026_tm_time_alloc_nn NOT NULL,
    project_valid_from timestamp with time zone,
    project_valid_to timestamp with time zone,
    pay_currency character(3),
    pay_unit text,
    pay_amount numeric(20,6),
    created_by text,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_026_tm_created_at_nn NOT NULL,
    entity_position_id bigint,
    project_position_id bigint,
    CONSTRAINT gd_026_tm_arrangement_temporal_chk CHECK ((arrangement_valid_from < arrangement_valid_to)),
    CONSTRAINT gd_026_tm_entity_position_class_chk CHECK (global.fn_is_entity_position(entity_position_id)),
    CONSTRAINT gd_026_tm_pay_amount_chk CHECK (((pay_amount IS NULL) OR (pay_amount >= (0)::numeric))),
    CONSTRAINT gd_026_tm_pay_unit_chk CHECK ((pay_unit = ANY (ARRAY['hour'::text, 'day'::text, 'month'::text, 'year'::text, 'delivery'::text]))),
    CONSTRAINT gd_026_tm_payment_consistency_chk CHECK ((((pay_currency IS NULL) AND (pay_unit IS NULL) AND (pay_amount IS NULL)) OR ((pay_currency IS NOT NULL) AND (pay_unit IS NOT NULL) AND (pay_amount IS NOT NULL)))),
    CONSTRAINT gd_026_tm_project_consistency_chk CHECK ((((project_id IS NULL) AND (project_valid_from IS NULL) AND (project_valid_to IS NULL)) OR ((project_id IS NOT NULL) AND (project_valid_from IS NOT NULL) AND (project_valid_to IS NOT NULL)))),
    CONSTRAINT gd_026_tm_project_position_class_chk CHECK (global.fn_is_project_position(project_position_id)),
    CONSTRAINT gd_026_tm_project_within_arrangement_chk CHECK (((project_valid_from IS NULL) OR ((project_valid_from >= arrangement_valid_from) AND (project_valid_to <= arrangement_valid_to) AND (project_valid_from < project_valid_to)))),
    CONSTRAINT gd_026_tm_time_allocation_chk CHECK (((time_allocation > (0)::numeric) AND (time_allocation <= 1.0)))
);


ALTER TABLE global.gd_026_teammembers OWNER TO postgres;

--
-- Name: TABLE gd_026_teammembers; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_026_teammembers IS 'Team member engagement registry. Each row represents one distinct combination of person × entity × legal arrangement type × project × payment terms with its own validity period. Two date ranges: arrangement_valid_from/to (legal contract envelope) and project_valid_from/to (project allocation within that envelope). A person split across two projects has two rows — one per allocation.';


--
-- Name: COLUMN gd_026_teammembers.arrangement_valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.arrangement_valid_from IS 'Start of the legal arrangement (contract effective date).';


--
-- Name: COLUMN gd_026_teammembers.arrangement_valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.arrangement_valid_to IS 'End of the legal arrangement. Defaults to effectively unbounded.';


--
-- Name: COLUMN gd_026_teammembers.time_allocation; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.time_allocation IS 'Fraction of working time allocated to this project under this arrangement. 1.0000 = full time. 0.5000 = half time. Must be > 0 and <= 1.0.';


--
-- Name: COLUMN gd_026_teammembers.project_valid_from; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.project_valid_from IS 'Start of project allocation. Must be >= arrangement_valid_from. Null when arrangement exists without project assignment.';


--
-- Name: COLUMN gd_026_teammembers.project_valid_to; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.project_valid_to IS 'End of project allocation. Must be <= arrangement_valid_to.';


--
-- Name: COLUMN gd_026_teammembers.pay_unit; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.pay_unit IS 'Unit against which pay_amount is expressed: hour, day, month, year, or delivery (per result/deliverable).';


--
-- Name: COLUMN gd_026_teammembers.pay_amount; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.pay_amount IS 'Gross amount per pay_unit in pay_currency.';


--
-- Name: COLUMN gd_026_teammembers.entity_position_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.entity_position_id IS 'Formal position of this person within the legal entity. Must reference a position with class = ''entity_position''. Used in tax reporting, statutory filings, and signing authority. Nullable — not all arrangements require a formal entity position.';


--
-- Name: COLUMN gd_026_teammembers.project_position_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_026_teammembers.project_position_id IS 'Operational position of this person within the project. Must reference a position with class = ''project_position''. Governs decision authority and role within project delivery scope. Nullable — a person may hold an entity arrangement without project assignment.';


--
-- Name: gd_026_teammembers_arrangement_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_026_teammembers ALTER COLUMN arrangement_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_026_teammembers_arrangement_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_027_positions; Type: TABLE; Schema: global; Owner: postgres
--

CREATE TABLE global.gd_027_positions (
    position_id bigint CONSTRAINT gd_027_positions_id_nn NOT NULL,
    position_class text CONSTRAINT gd_027_positions_class_nn NOT NULL,
    position_name text CONSTRAINT gd_027_positions_name_nn NOT NULL,
    position_superior_id bigint,
    position_description text,
    valid_from timestamp with time zone DEFAULT '1901-01-01 02:02:04+02:02:04'::timestamp with time zone CONSTRAINT gd_027_positions_valid_from_nn NOT NULL,
    valid_to timestamp with time zone DEFAULT '3001-12-31 02:00:00+02'::timestamp with time zone CONSTRAINT gd_027_positions_valid_to_nn NOT NULL,
    created_by text,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT gd_027_positions_created_at_nn NOT NULL,
    CONSTRAINT gd_027_positions_class_chk CHECK ((position_class = ANY (ARRAY['entity_position'::text, 'project_position'::text]))),
    CONSTRAINT gd_027_positions_no_self_superior_chk CHECK (((position_superior_id IS NULL) OR (position_superior_id <> position_id))),
    CONSTRAINT gd_027_positions_temporal_chk CHECK ((valid_from < valid_to))
);


ALTER TABLE global.gd_027_positions OWNER TO postgres;

--
-- Name: TABLE gd_027_positions; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON TABLE global.gd_027_positions IS 'Canonical position registry supporting two independent hierarchies: entity_position (formal statutory org structure) and project_position (project delivery structure). Hierarchy enforced within class only — cross-class superior references are prevented by the composite FK on (position_superior_id, position_class). Recursive CTE traversal produces full org/project tree from this table.';


--
-- Name: COLUMN gd_027_positions.position_class; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_027_positions.position_class IS 'entity_position: formal role within legal entity — appears on statutory filings. project_position: operational role within a project delivery context.';


--
-- Name: COLUMN gd_027_positions.position_superior_id; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_027_positions.position_superior_id IS 'Immediate superior position within the same class. NULL denotes a root node (top of hierarchy). Composite FK enforces same-class constraint — cross-class reference fails at insert.';


--
-- Name: COLUMN gd_027_positions.position_description; Type: COMMENT; Schema: global; Owner: postgres
--

COMMENT ON COLUMN global.gd_027_positions.position_description IS 'Scope, responsibilities, and authority boundaries of this position.';


--
-- Name: gd_027_positions_position_id_seq; Type: SEQUENCE; Schema: global; Owner: postgres
--

ALTER TABLE global.gd_027_positions ALTER COLUMN position_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME global.gd_027_positions_position_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: gd_001_events event_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events ALTER COLUMN event_id SET DEFAULT nextval('global.gd_001_events_event_id_seq'::regclass);


--
-- Name: gd_002_primitive_transitions primitive_transition_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_002_primitive_transitions ALTER COLUMN primitive_transition_id SET DEFAULT nextval('global.gd_002_primitive_transitions_primitive_transition_id_seq'::regclass);


--
-- Name: gd_004_entities entity_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_004_entities ALTER COLUMN entity_id SET DEFAULT nextval('global.gd_004_entities_entity_id_seq'::regclass);


--
-- Name: gd_005_ruleset_lines line_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_ruleset_lines ALTER COLUMN line_id SET DEFAULT nextval('global.gd_005_ruleset_lines_line_id_seq'::regclass);


--
-- Name: gd_006_commit_records commit_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_006_commit_records ALTER COLUMN commit_id SET DEFAULT nextval('global.gd_006_commit_records_commit_id_seq'::regclass);


--
-- Name: gd_008_governance_identities governance_identity_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_008_governance_identities ALTER COLUMN governance_identity_id SET DEFAULT nextval('global.gd_008_governance_identities_governance_identity_id_seq'::regclass);


--
-- Name: gd_011_holidays holiday_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_011_holidays ALTER COLUMN holiday_id SET DEFAULT nextval('global.gd_011_holidays_holiday_id_seq'::regclass);


--
-- Name: gd_012_currency_registry currency_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_012_currency_registry ALTER COLUMN currency_id SET DEFAULT nextval('global.gd_012_currency_registry_currency_id_seq'::regclass);


--
-- Name: gd_013_people person_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_013_people ALTER COLUMN person_id SET DEFAULT nextval('global.gd_013_people_person_id_seq'::regclass);


--
-- Name: gd_015_exchange_rates rate_id; Type: DEFAULT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_015_exchange_rates ALTER COLUMN rate_id SET DEFAULT nextval('global.gd_015_exchange_rates_rate_id_seq'::regclass);


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
-- Name: gd_001_events gd_001_events_replay_sequence_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_replay_sequence_uq UNIQUE (replay_sequence);


--
-- Name: gd_002_primitive_transitions gd_002_primitive_transitions_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_002_primitive_transitions
    ADD CONSTRAINT gd_002_primitive_transitions_pk PRIMARY KEY (primitive_transition_id);


--
-- Name: gd_004_entities gd_003_entities_entity_reg_number_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_004_entities
    ADD CONSTRAINT gd_003_entities_entity_reg_number_uq UNIQUE (entity_reg_number);


--
-- Name: gd_004_entities gd_003_entities_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_004_entities
    ADD CONSTRAINT gd_003_entities_pk PRIMARY KEY (entity_id);


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
-- Name: gd_006_commit_records gd_005_commit_records_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_006_commit_records
    ADD CONSTRAINT gd_005_commit_records_pk PRIMARY KEY (commit_id);


--
-- Name: gd_007_status_registry gd_006_status_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_007_status_registry
    ADD CONSTRAINT gd_006_status_registry_pk PRIMARY KEY (status_type, status_code);


--
-- Name: gd_013_people gd_007_people_person_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_013_people
    ADD CONSTRAINT gd_007_people_person_code_uq UNIQUE (person_code);


--
-- Name: gd_013_people gd_007_people_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_013_people
    ADD CONSTRAINT gd_007_people_pk PRIMARY KEY (person_id);


--
-- Name: gd_003_ruleset_registry gd_008_ruleset_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_003_ruleset_registry
    ADD CONSTRAINT gd_008_ruleset_registry_pk PRIMARY KEY (ruleset_id);


--
-- Name: gd_005_ruleset_lines gd_009_ruleset_lines_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_ruleset_lines
    ADD CONSTRAINT gd_009_ruleset_lines_pk PRIMARY KEY (line_id);


--
-- Name: gd_011_holidays gd_011_holidays_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_011_holidays
    ADD CONSTRAINT gd_011_holidays_pk PRIMARY KEY (holiday_id);


--
-- Name: gd_011_holidays gd_011_holidays_unique; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_011_holidays
    ADD CONSTRAINT gd_011_holidays_unique UNIQUE (country_code, holiday_date, holiday_type);


--
-- Name: gd_012_currency_registry gd_012_currency_registry_iso_alpha_3_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_012_currency_registry
    ADD CONSTRAINT gd_012_currency_registry_iso_alpha_3_uq UNIQUE (iso_alpha_3);


--
-- Name: gd_012_currency_registry gd_012_currency_registry_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_012_currency_registry
    ADD CONSTRAINT gd_012_currency_registry_pk PRIMARY KEY (currency_id);


--
-- Name: gd_008_governance_identities gd_013_governance_identities_identity_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_008_governance_identities
    ADD CONSTRAINT gd_013_governance_identities_identity_code_uq UNIQUE (identity_code);


--
-- Name: gd_008_governance_identities gd_013_governance_identities_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_008_governance_identities
    ADD CONSTRAINT gd_013_governance_identities_pk PRIMARY KEY (governance_identity_id);


--
-- Name: gd_018_rate_codes gd_014_rate_codes_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_018_rate_codes
    ADD CONSTRAINT gd_014_rate_codes_pkey PRIMARY KEY (rate_code);


--
-- Name: gd_016_coa gd_016_coa_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_016_coa
    ADD CONSTRAINT gd_016_coa_pk PRIMARY KEY (account_code);


--
-- Name: gd_017_naming_conventions gd_017_naming_conventions_pk; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_017_naming_conventions
    ADD CONSTRAINT gd_017_naming_conventions_pk PRIMARY KEY (naming_id);


--
-- Name: gd_017_naming_conventions gd_017_naming_conventions_unique; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_017_naming_conventions
    ADD CONSTRAINT gd_017_naming_conventions_unique UNIQUE (object_type, object_ref, translation_language);


--
-- Name: gd_019_pt_types gd_019_pt_types_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_019_pt_types
    ADD CONSTRAINT gd_019_pt_types_pkey PRIMARY KEY (pt_type_code);


--
-- Name: gd_020_scenarios gd_020_scenarios_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_020_scenarios
    ADD CONSTRAINT gd_020_scenarios_pkey PRIMARY KEY (scenario_id);


--
-- Name: gd_020_scenarios gd_020_scenarios_scenario_name_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_020_scenarios
    ADD CONSTRAINT gd_020_scenarios_scenario_name_uq UNIQUE (scenario_name);


--
-- Name: gd_021_proposals gd_021_proposals_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_021_proposals
    ADD CONSTRAINT gd_021_proposals_pkey PRIMARY KEY (proposal_id);


--
-- Name: gd_022_delegations gd_022_delegations_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_022_delegations
    ADD CONSTRAINT gd_022_delegations_pkey PRIMARY KEY (delegation_id);


--
-- Name: gd_023_event_types gd_023_event_types_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_023_event_types
    ADD CONSTRAINT gd_023_event_types_pkey PRIMARY KEY (event_type_code);


--
-- Name: gd_024_legal_arrangement_types gd_024_legal_arrangement_types_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_024_legal_arrangement_types
    ADD CONSTRAINT gd_024_legal_arrangement_types_pkey PRIMARY KEY (arrangement_type_code);


--
-- Name: gd_025_projects gd_025_projects_code_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_025_projects
    ADD CONSTRAINT gd_025_projects_code_uq UNIQUE (project_code);


--
-- Name: gd_025_projects gd_025_projects_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_025_projects
    ADD CONSTRAINT gd_025_projects_pkey PRIMARY KEY (project_id);


--
-- Name: gd_026_teammembers gd_026_teammembers_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_teammembers_pkey PRIMARY KEY (arrangement_id);


--
-- Name: gd_027_positions gd_027_positions_id_class_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_027_positions
    ADD CONSTRAINT gd_027_positions_id_class_uq UNIQUE (position_id, position_class);


--
-- Name: gd_027_positions gd_027_positions_name_class_uq; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_027_positions
    ADD CONSTRAINT gd_027_positions_name_class_uq UNIQUE (position_name, position_class);


--
-- Name: gd_027_positions gd_027_positions_pkey; Type: CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_027_positions
    ADD CONSTRAINT gd_027_positions_pkey PRIMARY KEY (position_id);


--
-- Name: gd_001_events_assertion_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_assertion_time_idx ON global.gd_001_events USING btree (assertion_time);


--
-- Name: gd_001_events_commit_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_commit_id_idx ON global.gd_001_events USING btree (commit_id);


--
-- Name: gd_001_events_commit_replay_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_commit_replay_idx ON global.gd_001_events USING btree (commit_id, replay_sequence);


--
-- Name: gd_001_events_corrective_of_event_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_corrective_of_event_id_idx ON global.gd_001_events USING btree (corrective_of_event_id) WHERE (corrective_of_event_id IS NOT NULL);


--
-- Name: gd_001_events_entity_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_entity_id_idx ON global.gd_001_events USING btree (entity_id);


--
-- Name: gd_001_events_entity_status_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_entity_status_time_idx ON global.gd_001_events USING btree (entity_id, event_status, valid_time);


--
-- Name: gd_001_events_entity_time_committed_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_entity_time_committed_idx ON global.gd_001_events USING btree (entity_id, valid_time) WHERE ((event_status)::text = 'committed'::text);


--
-- Name: gd_001_events_event_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_event_status_idx ON global.gd_001_events USING btree (event_status);


--
-- Name: gd_001_events_event_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_event_type_idx ON global.gd_001_events USING btree (event_type);


--
-- Name: gd_001_events_replay_sequence_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_replay_sequence_idx ON global.gd_001_events USING btree (replay_sequence);


--
-- Name: gd_001_events_valid_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_001_events_valid_time_idx ON global.gd_001_events USING btree (valid_time);


--
-- Name: gd_002_primitive_transitions_account_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_account_idx ON global.gd_002_primitive_transitions USING btree (account_code);


--
-- Name: gd_002_primitive_transitions_description_trgm_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_description_trgm_idx ON global.gd_002_primitive_transitions USING gin (transition_description public.gin_trgm_ops) WHERE (transition_description IS NOT NULL);


--
-- Name: gd_002_primitive_transitions_entity_account_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_entity_account_time_idx ON global.gd_002_primitive_transitions USING btree (entity_id, account_code, valid_time);


--
-- Name: gd_002_primitive_transitions_entity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_entity_idx ON global.gd_002_primitive_transitions USING btree (entity_id);


--
-- Name: gd_002_primitive_transitions_event_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_event_idx ON global.gd_002_primitive_transitions USING btree (event_id);


--
-- Name: gd_002_primitive_transitions_valid_time_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_002_primitive_transitions_valid_time_idx ON global.gd_002_primitive_transitions USING btree (valid_time);


--
-- Name: gd_003_entities_country_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_country_code_idx ON global.gd_004_entities USING btree (country_code);


--
-- Name: gd_003_entities_name_trgm_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_name_trgm_idx ON global.gd_004_entities USING gin (normalized_name public.gin_trgm_ops);


--
-- Name: gd_003_entities_tax_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_tax_id_idx ON global.gd_004_entities USING btree (tax_id);


--
-- Name: gd_003_entities_vat_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_003_entities_vat_id_idx ON global.gd_004_entities USING btree (vat_id);


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

CREATE INDEX gd_005_commit_records_commit_status_idx ON global.gd_006_commit_records USING btree (commit_status);


--
-- Name: gd_005_commit_records_commit_timestamp_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_timestamp_idx ON global.gd_006_commit_records USING btree (commit_timestamp);


--
-- Name: gd_005_commit_records_commit_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_commit_type_idx ON global.gd_006_commit_records USING btree (commit_type);


--
-- Name: gd_005_commit_records_committing_authority_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_commit_records_committing_authority_id_idx ON global.gd_006_commit_records USING btree (committing_authority_id);


--
-- Name: gd_005_ruleset_lines_account_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_ruleset_lines_account_code_idx ON global.gd_005_ruleset_lines USING btree (account_code) WHERE (account_code IS NOT NULL);


--
-- Name: gd_005_ruleset_lines_entity_1_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_ruleset_lines_entity_1_id_idx ON global.gd_005_ruleset_lines USING btree (entity_1_id) WHERE (entity_1_id IS NOT NULL);


--
-- Name: gd_005_ruleset_lines_entity_2_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_ruleset_lines_entity_2_id_idx ON global.gd_005_ruleset_lines USING btree (entity_2_id) WHERE (entity_2_id IS NOT NULL);


--
-- Name: gd_005_ruleset_lines_ruleset_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_005_ruleset_lines_ruleset_validity_idx ON global.gd_005_ruleset_lines USING btree (ruleset_id, valid_from, valid_to);


--
-- Name: gd_006_status_registry_status_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_006_status_registry_status_type_idx ON global.gd_007_status_registry USING btree (status_type);


--
-- Name: gd_007_people_country_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_country_code_idx ON global.gd_013_people USING btree (country_code);


--
-- Name: gd_007_people_last_name_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_last_name_idx ON global.gd_013_people USING btree (last_name);


--
-- Name: gd_007_people_tax_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_007_people_tax_id_idx ON global.gd_013_people USING btree (tax_id);


--
-- Name: gd_008_governance_identities_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_008_governance_identities_validity_idx ON global.gd_008_governance_identities USING btree (valid_from, valid_to);


--
-- Name: gd_009_ruleset_lines_ruleset_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_009_ruleset_lines_ruleset_id_idx ON global.gd_005_ruleset_lines USING btree (ruleset_id);


--
-- Name: gd_009_ruleset_lines_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_009_ruleset_lines_validity_idx ON global.gd_005_ruleset_lines USING btree (valid_from, valid_to);


--
-- Name: gd_011_holidays_country_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_011_holidays_country_idx ON global.gd_011_holidays USING btree (country_code);


--
-- Name: gd_011_holidays_date_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_011_holidays_date_idx ON global.gd_011_holidays USING btree (holiday_date);


--
-- Name: gd_011_holidays_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_011_holidays_type_idx ON global.gd_011_holidays USING btree (holiday_type);


--
-- Name: gd_012_currency_registry_alpha2_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_012_currency_registry_alpha2_idx ON global.gd_012_currency_registry USING btree (iso_alpha_2);


--
-- Name: gd_012_currency_registry_alpha3_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_012_currency_registry_alpha3_idx ON global.gd_012_currency_registry USING btree (iso_alpha_3);


--
-- Name: gd_013_governance_identities_identity_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_identity_status_idx ON global.gd_008_governance_identities USING btree (identity_status);


--
-- Name: gd_013_governance_identities_identity_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_identity_type_idx ON global.gd_008_governance_identities USING btree (identity_type);


--
-- Name: gd_013_governance_identities_valid_from_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_valid_from_idx ON global.gd_008_governance_identities USING btree (valid_from);


--
-- Name: gd_013_governance_identities_valid_to_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_013_governance_identities_valid_to_idx ON global.gd_008_governance_identities USING btree (valid_to);


--
-- Name: gd_015_exchange_rates_pair_time_code_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_015_exchange_rates_pair_time_code_idx ON global.gd_015_exchange_rates USING btree (base_currency, quote_currency, rate_timestamp, rate_code);


--
-- Name: gd_016_coa_account_name_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_016_coa_account_name_idx ON global.gd_016_coa USING btree (account_name);


--
-- Name: gd_016_coa_parent_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_016_coa_parent_idx ON global.gd_016_coa USING btree (parent_account_code);


--
-- Name: gd_016_coa_ruleset_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_016_coa_ruleset_idx ON global.gd_016_coa USING btree (ruleset_id);


--
-- Name: gd_017_naming_conventions_language_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_017_naming_conventions_language_idx ON global.gd_017_naming_conventions USING btree (translation_language);


--
-- Name: gd_017_naming_conventions_object_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_017_naming_conventions_object_idx ON global.gd_017_naming_conventions USING btree (object_type, object_ref);


--
-- Name: gd_020_scenarios_base_date_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_020_scenarios_base_date_idx ON global.gd_020_scenarios USING btree (base_date);


--
-- Name: gd_021_proposals_created_at_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_created_at_idx ON global.gd_021_proposals USING btree (created_at);


--
-- Name: gd_021_proposals_entity_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_entity_id_idx ON global.gd_021_proposals USING btree (entity_id);


--
-- Name: gd_021_proposals_payload_gin_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_payload_gin_idx ON global.gd_021_proposals USING gin (proposal_payload);


--
-- Name: gd_021_proposals_scenario_id_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_scenario_id_idx ON global.gd_021_proposals USING btree (scenario_id);


--
-- Name: gd_021_proposals_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_status_idx ON global.gd_021_proposals USING btree (proposal_status);


--
-- Name: gd_021_proposals_type_status_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_021_proposals_type_status_idx ON global.gd_021_proposals USING btree (proposal_type, proposal_status);


--
-- Name: gd_022_delegations_delegatee_active_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_delegatee_active_idx ON global.gd_022_delegations USING btree (delegatee_id, delegation_scope, valid_from, valid_to) WHERE (revoked_at IS NULL);


--
-- Name: gd_022_delegations_delegator_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_delegator_idx ON global.gd_022_delegations USING btree (delegator_id);


--
-- Name: gd_022_delegations_entity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_entity_idx ON global.gd_022_delegations USING btree (entity_id) WHERE (entity_id IS NOT NULL);


--
-- Name: gd_022_delegations_temporal_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_022_delegations_temporal_idx ON global.gd_022_delegations USING btree (valid_from, valid_to);


--
-- Name: gd_024_lat_category_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_024_lat_category_idx ON global.gd_024_legal_arrangement_types USING btree (arrangement_category);


--
-- Name: gd_024_lat_jurisdiction_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_024_lat_jurisdiction_idx ON global.gd_024_legal_arrangement_types USING btree (jurisdiction_code) WHERE (jurisdiction_code IS NOT NULL);


--
-- Name: gd_025_projects_entity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_025_projects_entity_idx ON global.gd_025_projects USING btree (entity_id) WHERE (entity_id IS NOT NULL);


--
-- Name: gd_025_projects_owner_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_025_projects_owner_idx ON global.gd_025_projects USING btree (project_owner_id) WHERE (project_owner_id IS NOT NULL);


--
-- Name: gd_025_projects_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_025_projects_validity_idx ON global.gd_025_projects USING btree (valid_from, valid_to);


--
-- Name: gd_026_tm_currency_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_currency_idx ON global.gd_026_teammembers USING btree (pay_currency) WHERE (pay_currency IS NOT NULL);


--
-- Name: gd_026_tm_entity_arr_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_entity_arr_validity_idx ON global.gd_026_teammembers USING btree (entity_id, arrangement_valid_from, arrangement_valid_to);


--
-- Name: gd_026_tm_entity_position_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_entity_position_idx ON global.gd_026_teammembers USING btree (entity_position_id) WHERE (entity_position_id IS NOT NULL);


--
-- Name: gd_026_tm_person_arr_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_person_arr_validity_idx ON global.gd_026_teammembers USING btree (person_id, arrangement_valid_from, arrangement_valid_to);


--
-- Name: gd_026_tm_project_position_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_project_position_idx ON global.gd_026_teammembers USING btree (project_position_id) WHERE (project_position_id IS NOT NULL);


--
-- Name: gd_026_tm_project_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_project_validity_idx ON global.gd_026_teammembers USING btree (project_id, project_valid_from, project_valid_to) WHERE (project_id IS NOT NULL);


--
-- Name: gd_026_tm_type_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_026_tm_type_idx ON global.gd_026_teammembers USING btree (arrangement_type_code);


--
-- Name: gd_027_positions_class_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_class_idx ON global.gd_027_positions USING btree (position_class);


--
-- Name: gd_027_positions_superior_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_superior_idx ON global.gd_027_positions USING btree (position_superior_id) WHERE (position_superior_id IS NOT NULL);


--
-- Name: gd_027_positions_validity_idx; Type: INDEX; Schema: global; Owner: postgres
--

CREATE INDEX gd_027_positions_validity_idx ON global.gd_027_positions USING btree (valid_from, valid_to);


--
-- Name: gd_001_events gd_001_events_commit_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_commit_id_fk FOREIGN KEY (commit_id) REFERENCES global.gd_006_commit_records(commit_id);


--
-- Name: gd_001_events gd_001_events_corrective_of_event_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_corrective_of_event_fk FOREIGN KEY (corrective_of_event_id) REFERENCES global.gd_001_events(event_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_001_events gd_001_events_entity_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_entity_id_fk FOREIGN KEY (entity_id) REFERENCES global.gd_004_entities(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_001_events gd_001_events_event_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_event_type_fk FOREIGN KEY (event_type) REFERENCES global.gd_023_event_types(event_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_001_events gd_001_events_governance_scope_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_001_events
    ADD CONSTRAINT gd_001_events_governance_scope_fk FOREIGN KEY (governance_scope_id) REFERENCES global.gd_008_governance_identities(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_002_primitive_transitions gd_002_primitive_transitions_account_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_002_primitive_transitions
    ADD CONSTRAINT gd_002_primitive_transitions_account_fk FOREIGN KEY (account_code) REFERENCES global.gd_016_coa(account_code);


--
-- Name: gd_002_primitive_transitions gd_002_primitive_transitions_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_002_primitive_transitions
    ADD CONSTRAINT gd_002_primitive_transitions_entity_fk FOREIGN KEY (entity_id) REFERENCES global.gd_004_entities(entity_id);


--
-- Name: gd_002_primitive_transitions gd_002_primitive_transitions_event_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_002_primitive_transitions
    ADD CONSTRAINT gd_002_primitive_transitions_event_fk FOREIGN KEY (event_id) REFERENCES global.gd_001_events(event_id);


--
-- Name: gd_002_primitive_transitions gd_002_primitive_transitions_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_002_primitive_transitions
    ADD CONSTRAINT gd_002_primitive_transitions_type_fk FOREIGN KEY (primitive_transition_type) REFERENCES global.gd_019_pt_types(pt_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_003_ruleset_registry gd_003_ruleset_registry_governance_scope_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_003_ruleset_registry
    ADD CONSTRAINT gd_003_ruleset_registry_governance_scope_fk FOREIGN KEY (governance_scope_id) REFERENCES global.gd_008_governance_identities(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_006_commit_records gd_005_commit_records_committing_authority_id_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_006_commit_records
    ADD CONSTRAINT gd_005_commit_records_committing_authority_id_fk FOREIGN KEY (committing_authority_id) REFERENCES global.gd_008_governance_identities(governance_identity_id);


--
-- Name: gd_005_ruleset_lines gd_005_ruleset_lines_account_code_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_ruleset_lines
    ADD CONSTRAINT gd_005_ruleset_lines_account_code_fk FOREIGN KEY (account_code) REFERENCES global.gd_016_coa(account_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_005_ruleset_lines gd_005_ruleset_lines_entity_1_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_ruleset_lines
    ADD CONSTRAINT gd_005_ruleset_lines_entity_1_fk FOREIGN KEY (entity_1_id) REFERENCES global.gd_004_entities(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_005_ruleset_lines gd_005_ruleset_lines_entity_2_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_ruleset_lines
    ADD CONSTRAINT gd_005_ruleset_lines_entity_2_fk FOREIGN KEY (entity_2_id) REFERENCES global.gd_004_entities(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_005_ruleset_lines gd_009_ruleset_lines_ruleset_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_005_ruleset_lines
    ADD CONSTRAINT gd_009_ruleset_lines_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES global.gd_003_ruleset_registry(ruleset_id);


--
-- Name: gd_014_inflation_rates gd_014_inflation_rates_currency_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_014_inflation_rates
    ADD CONSTRAINT gd_014_inflation_rates_currency_fk FOREIGN KEY (currency_code) REFERENCES global.gd_012_currency_registry(iso_alpha_3) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_014_inflation_rates gd_014_inflation_rates_rate_reference_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_014_inflation_rates
    ADD CONSTRAINT gd_014_inflation_rates_rate_reference_fk FOREIGN KEY (rate_reference) REFERENCES global.gd_018_rate_codes(rate_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_015_exchange_rates gd_015_exchange_rates_base_currency_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_015_exchange_rates
    ADD CONSTRAINT gd_015_exchange_rates_base_currency_fk FOREIGN KEY (base_currency) REFERENCES global.gd_012_currency_registry(iso_alpha_3) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_015_exchange_rates gd_015_exchange_rates_quote_currency_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_015_exchange_rates
    ADD CONSTRAINT gd_015_exchange_rates_quote_currency_fk FOREIGN KEY (quote_currency) REFERENCES global.gd_012_currency_registry(iso_alpha_3) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_015_exchange_rates gd_015_exchange_rates_rate_code_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_015_exchange_rates
    ADD CONSTRAINT gd_015_exchange_rates_rate_code_fk FOREIGN KEY (rate_code) REFERENCES global.gd_018_rate_codes(rate_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_016_coa gd_016_coa_parent_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_016_coa
    ADD CONSTRAINT gd_016_coa_parent_fk FOREIGN KEY (parent_account_code) REFERENCES global.gd_016_coa(account_code);


--
-- Name: gd_016_coa gd_016_coa_ruleset_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_016_coa
    ADD CONSTRAINT gd_016_coa_ruleset_fk FOREIGN KEY (ruleset_id) REFERENCES global.gd_003_ruleset_registry(ruleset_id);


--
-- Name: gd_021_proposals gd_021_proposals_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_021_proposals
    ADD CONSTRAINT gd_021_proposals_entity_fk FOREIGN KEY (entity_id) REFERENCES global.gd_004_entities(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_021_proposals gd_021_proposals_scenario_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_021_proposals
    ADD CONSTRAINT gd_021_proposals_scenario_fk FOREIGN KEY (scenario_id) REFERENCES global.gd_020_scenarios(scenario_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_021_proposals gd_021_proposals_superseded_by_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_021_proposals
    ADD CONSTRAINT gd_021_proposals_superseded_by_fk FOREIGN KEY (superseded_by) REFERENCES global.gd_021_proposals(proposal_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_022_delegations gd_022_delegations_delegatee_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_022_delegations
    ADD CONSTRAINT gd_022_delegations_delegatee_fk FOREIGN KEY (delegatee_id) REFERENCES global.gd_008_governance_identities(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_022_delegations gd_022_delegations_delegator_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_022_delegations
    ADD CONSTRAINT gd_022_delegations_delegator_fk FOREIGN KEY (delegator_id) REFERENCES global.gd_008_governance_identities(governance_identity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_022_delegations gd_022_delegations_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_022_delegations
    ADD CONSTRAINT gd_022_delegations_entity_fk FOREIGN KEY (entity_id) REFERENCES global.gd_004_entities(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_025_projects gd_025_projects_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_025_projects
    ADD CONSTRAINT gd_025_projects_entity_fk FOREIGN KEY (entity_id) REFERENCES global.gd_004_entities(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_025_projects gd_025_projects_owner_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_025_projects
    ADD CONSTRAINT gd_025_projects_owner_fk FOREIGN KEY (project_owner_id) REFERENCES global.gd_013_people(person_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_026_teammembers gd_026_tm_arrangement_type_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_tm_arrangement_type_fk FOREIGN KEY (arrangement_type_code) REFERENCES global.gd_024_legal_arrangement_types(arrangement_type_code) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_026_teammembers gd_026_tm_currency_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_tm_currency_fk FOREIGN KEY (pay_currency) REFERENCES global.gd_012_currency_registry(iso_alpha_3) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_026_teammembers gd_026_tm_entity_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_tm_entity_fk FOREIGN KEY (entity_id) REFERENCES global.gd_004_entities(entity_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_026_teammembers gd_026_tm_entity_position_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_tm_entity_position_fk FOREIGN KEY (entity_position_id) REFERENCES global.gd_027_positions(position_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_026_teammembers gd_026_tm_person_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_tm_person_fk FOREIGN KEY (person_id) REFERENCES global.gd_013_people(person_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_026_teammembers gd_026_tm_project_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_tm_project_fk FOREIGN KEY (project_id) REFERENCES global.gd_025_projects(project_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_026_teammembers gd_026_tm_project_position_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_026_teammembers
    ADD CONSTRAINT gd_026_tm_project_position_fk FOREIGN KEY (project_position_id) REFERENCES global.gd_027_positions(position_id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: gd_027_positions gd_027_positions_superior_fk; Type: FK CONSTRAINT; Schema: global; Owner: postgres
--

ALTER TABLE ONLY global.gd_027_positions
    ADD CONSTRAINT gd_027_positions_superior_fk FOREIGN KEY (position_superior_id, position_class) REFERENCES global.gd_027_positions(position_id, position_class) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict 38Z7YPgocTJw6fnP8RdqTw4fjNHzl4s9eQjtNhEisYk8UaJC3hygOXzH41Oc97S

