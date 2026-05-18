--
-- PostgreSQL database dump
--

\restrict 2OZB5SEPYKiakTtuyn1IPAhiYmriM5jeN4k3bIBKhfuFd3G5Unld8RukpBp5sF7

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
-- Name: memory; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA memory;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: facts; Type: TABLE; Schema: memory; Owner: -
--

CREATE TABLE memory.facts (
    fact_id bigint NOT NULL,
    session_id bigint,
    subject text NOT NULL,
    predicate text NOT NULL,
    object text NOT NULL,
    confidence numeric(3,2) DEFAULT 1.0,
    source text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone
);


--
-- Name: facts_fact_id_seq; Type: SEQUENCE; Schema: memory; Owner: -
--

CREATE SEQUENCE memory.facts_fact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: facts_fact_id_seq; Type: SEQUENCE OWNED BY; Schema: memory; Owner: -
--

ALTER SEQUENCE memory.facts_fact_id_seq OWNED BY memory.facts.fact_id;


--
-- Name: messages; Type: TABLE; Schema: memory; Owner: -
--

CREATE TABLE memory.messages (
    message_id bigint NOT NULL,
    session_id bigint,
    role text NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT messages_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text, 'system'::text])))
);


--
-- Name: messages_message_id_seq; Type: SEQUENCE; Schema: memory; Owner: -
--

CREATE SEQUENCE memory.messages_message_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: messages_message_id_seq; Type: SEQUENCE OWNED BY; Schema: memory; Owner: -
--

ALTER SEQUENCE memory.messages_message_id_seq OWNED BY memory.messages.message_id;


--
-- Name: sessions; Type: TABLE; Schema: memory; Owner: -
--

CREATE TABLE memory.sessions (
    session_id bigint NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    summary text,
    tags text[]
);


--
-- Name: sessions_session_id_seq; Type: SEQUENCE; Schema: memory; Owner: -
--

CREATE SEQUENCE memory.sessions_session_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_session_id_seq; Type: SEQUENCE OWNED BY; Schema: memory; Owner: -
--

ALTER SEQUENCE memory.sessions_session_id_seq OWNED BY memory.sessions.session_id;


--
-- Name: state; Type: TABLE; Schema: memory; Owner: -
--

CREATE TABLE memory.state (
    key text NOT NULL,
    value jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: facts fact_id; Type: DEFAULT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.facts ALTER COLUMN fact_id SET DEFAULT nextval('memory.facts_fact_id_seq'::regclass);


--
-- Name: messages message_id; Type: DEFAULT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.messages ALTER COLUMN message_id SET DEFAULT nextval('memory.messages_message_id_seq'::regclass);


--
-- Name: sessions session_id; Type: DEFAULT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.sessions ALTER COLUMN session_id SET DEFAULT nextval('memory.sessions_session_id_seq'::regclass);


--
-- Name: facts facts_pkey; Type: CONSTRAINT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.facts
    ADD CONSTRAINT facts_pkey PRIMARY KEY (fact_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (message_id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (session_id);


--
-- Name: state state_pkey; Type: CONSTRAINT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.state
    ADD CONSTRAINT state_pkey PRIMARY KEY (key);


--
-- Name: idx_facts_predicate; Type: INDEX; Schema: memory; Owner: -
--

CREATE INDEX idx_facts_predicate ON memory.facts USING btree (predicate);


--
-- Name: idx_facts_session; Type: INDEX; Schema: memory; Owner: -
--

CREATE INDEX idx_facts_session ON memory.facts USING btree (session_id);


--
-- Name: idx_facts_subject; Type: INDEX; Schema: memory; Owner: -
--

CREATE INDEX idx_facts_subject ON memory.facts USING btree (subject);


--
-- Name: idx_messages_session; Type: INDEX; Schema: memory; Owner: -
--

CREATE INDEX idx_messages_session ON memory.messages USING btree (session_id);


--
-- Name: facts facts_session_id_fkey; Type: FK CONSTRAINT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.facts
    ADD CONSTRAINT facts_session_id_fkey FOREIGN KEY (session_id) REFERENCES memory.sessions(session_id);


--
-- Name: messages messages_session_id_fkey; Type: FK CONSTRAINT; Schema: memory; Owner: -
--

ALTER TABLE ONLY memory.messages
    ADD CONSTRAINT messages_session_id_fkey FOREIGN KEY (session_id) REFERENCES memory.sessions(session_id);


--
-- PostgreSQL database dump complete
--

\unrestrict 2OZB5SEPYKiakTtuyn1IPAhiYmriM5jeN4k3bIBKhfuFd3G5Unld8RukpBp5sF7

