-- 002_evidence.sql
-- A2 evidence layer: archived source documents, verbatim spans, interpreted claims,
-- and the links between them. Append-only by design.

begin;

create type source_type as enum ('sec_edgar','company_site','press_release','news',
                                 'ferc','state_filing','job_posting','project_award',
                                 'registry','other');

create type access_tier as enum ('open','licensed');

create type claim_confidence  as enum ('high','medium','low');
create type evidence_relation as enum ('supports','contradicts');

create table source_document (
  id             text        primary key,
  url            text        not null,
  source_type    source_type not null,
  publisher      text,
  title          text,
  content_type   text,
  content_sha256 text        not null,
  storage_key    text        not null,
  size_bytes     bigint,
  retrieved_at   timestamptz not null,
  retrieved_by   actor_type  not null,
  retriever_id   text,
  access_tier    access_tier not null default 'open',
  created_at     timestamptz not null default now()
);

create index idx_doc_url    on source_document (url);
create index idx_doc_sha256 on source_document (content_sha256);

create table evidence (
  id           text        primary key,
  document_id  text        not null references source_document(id),
  quote        text        not null,
  locator      jsonb,
  context      text,
  extracted_at timestamptz not null default now(),
  extractor    actor_type  not null,
  extractor_id text
);

create index idx_evidence_doc on evidence (document_id);

create table claim (
  id             text             primary key,
  entity_id      text             not null references entity(id),
  claim_type     text             not null,
  summary        text             not null,
  body           jsonb,
  event_date     date,
  asserted_at    timestamptz      not null default now(),
  interpreter    actor_type       not null,
  interpreter_id text,
  method_version text,
  confidence     claim_confidence not null default 'medium',
  superseded_by  text references claim(id),
  retracted_at   timestamptz,
  created_at     timestamptz      not null default now()
);

create index idx_claim_current on claim (entity_id)
  where superseded_by is null and retracted_at is null;
create index idx_claim_type     on claim (claim_type);
create index idx_claim_asserted on claim (asserted_at desc);

create table claim_evidence (
  claim_id    text              not null references claim(id),
  evidence_id text              not null references evidence(id),
  relation    evidence_relation not null default 'supports',
  primary key (claim_id, evidence_id)
);

create index idx_claim_evidence_ev on claim_evidence (evidence_id);

commit;
