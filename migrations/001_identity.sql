-- 001_identity.sql
-- A1 identity layer: canonical entity records, aliases, external identifiers,
-- ownership edges, and the append-only change log.
-- Spec: ampergy-entity-model.md (A1.1, FINAL)

begin;

-- ---------------------------------------------------------------- types

create type entity_kind   as enum ('organization');  -- extensible: person, project, asset
create type entity_status as enum ('active','inactive','merged','dissolved','unknown');
create type org_type      as enum ('operating','holding','municipal','cooperative',
                                   'government','fund','other');
create type alias_type    as enum ('legal_name','former_name','trading_name',
                                   'dba','short_name','other');
create type id_type       as enum ('cik','lei','ticker','duns','ein',
                                   'ferc_cid','eia_id','other');
create type rel_type      as enum ('direct_parent');
create type actor_type    as enum ('human','model','system');

-- ---------------------------------------------------------------- entity

create table entity (
  id             text primary key,                    -- ent_<ULID>
  kind           entity_kind   not null default 'organization',
  canonical_name text          not null,              -- current legal name, denormalized for display
  org_type       org_type,                            -- structural type only; market roles live in taxonomy
  jurisdiction   text,                                -- ISO 3166, e.g. 'US-TX'
  status         entity_status not null default 'active',
  merged_into    text references entity(id),
  version        integer       not null default 1,    -- bumped by every change-log append
  created_at     timestamptz   not null default now(),
  updated_at     timestamptz   not null default now(),
  check (status <> 'merged' or merged_into is not null)
);

create index idx_entity_name   on entity (canonical_name);
create index idx_entity_status on entity (status) where status = 'active';

-- ---------------------------------------------------------------- aliases

create table entity_alias (
  id          text        primary key,                -- al_<ULID>
  entity_id   text        not null references entity(id),
  alias       text        not null,                   -- as written in the source
  alias_norm  text        not null,                   -- lowercased, punctuation and suffix stripped
  alias_type  alias_type  not null,
  is_current  boolean     not null default true,
  valid_from  date,
  valid_to    date,
  evidence_id text,                                   -- fk to evidence(id) once 002 lands
  created_at  timestamptz not null default now(),
  unique (entity_id, alias_norm, alias_type)
);

create index idx_alias_norm on entity_alias (alias_norm);

-- ---------------------------------------------------------------- identifiers

create table entity_identifier (
  id          text        primary key,                -- xid_<ULID>
  entity_id   text        not null references entity(id),
  id_type     id_type     not null,
  id_value    text        not null,
  id_extra    text,                                   -- e.g. exchange for a ticker
  is_current  boolean     not null default true,
  valid_from  date,
  valid_to    date,
  evidence_id text,
  created_at  timestamptz not null default now()
);

-- an identifier points at only one entity *currently*; history may repeat (tickers get recycled)
create unique index uq_identifier_current
  on entity_identifier (id_type, id_value) where is_current;

-- ---------------------------------------------------------------- relationships

create table entity_relationship (
  id            text         primary key,             -- rel_<ULID>
  parent_id     text         not null references entity(id),
  child_id      text         not null references entity(id),
  rel_type      rel_type     not null default 'direct_parent',
  ownership_pct numeric(5,2),
  is_current    boolean      not null default true,
  valid_from    date,
  valid_to      date,
  evidence_id   text,
  created_at    timestamptz  not null default now(),
  check (parent_id <> child_id)
);

create unique index uq_rel_current
  on entity_relationship (parent_id, child_id, rel_type) where is_current;
create index idx_rel_child on entity_relationship (child_id) where is_current;

-- ---------------------------------------------------------------- change log

create table entity_change (
  id          text        primary key,                -- chg_<ULID>
  entity_id   text        not null references entity(id),
  changed_at  timestamptz not null default now(),
  actor_type  actor_type  not null,
  actor_id    text,
  field       text        not null,                   -- e.g. 'entity.status', 'alias.added'
  old_value   jsonb,
  new_value   jsonb,
  reason      text,
  evidence_id text
);

create index idx_change_entity on entity_change (entity_id, changed_at desc);

-- append-only is enforced by privilege grant, not by constraint:
-- the application role receives INSERT and SELECT, never UPDATE or DELETE.
-- Grants live in 003_grants.sql once the app role exists.

commit;
