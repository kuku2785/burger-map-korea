-- Internal menu observations; public.menus remains the approved read snapshot.
-- The composite key prevents an evidence row linking to another store's menu.
ALTER TABLE public.menus
  ADD CONSTRAINT menus_store_id_id_unique UNIQUE (store_id, id);

CREATE TABLE burger_map_private.menu_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL
    REFERENCES public.stores(id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  menu_id uuid,
  source_url text NOT NULL,
  source_type text NOT NULL,
  source_tier text NOT NULL,
  store_match_status text NOT NULL,
  observed_name text NOT NULL,
  normalized_name text NOT NULL,
  observed_price_krw integer,
  price_context text NOT NULL,
  currentness text NOT NULL,
  source_published_at timestamptz,
  retrieved_at timestamptz NOT NULL,
  signature_evidence text,
  evidence_status text NOT NULL DEFAULT 'candidate',
  approval_ref text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT menu_evidence_same_store_fk FOREIGN KEY (store_id, menu_id)
    REFERENCES public.menus(store_id, id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT menu_evidence_url_check CHECK (
    source_url = btrim(source_url) AND char_length(source_url) BETWEEN 8 AND 2048
    AND source_url ~ '^https?://[^[:space:]]+$'),
  CONSTRAINT menu_evidence_type_check CHECK (source_type IN (
    'official_website', 'official_store_page', 'official_brand_page',
    'official_social', 'official_order', 'business_profile',
    'delivery_platform', 'reservation_platform', 'kakao_place',
    'naver_place', 'third_party_review', 'blog', 'unknown')),
  CONSTRAINT menu_evidence_tier_check CHECK (source_tier IN ('A', 'B', 'C')),
  CONSTRAINT menu_evidence_match_check CHECK (store_match_status IN (
    'EXACT_MATCH', 'LIKELY_MATCH', 'AMBIGUOUS', 'MISMATCH', 'UNKNOWN')),
  CONSTRAINT menu_evidence_name_check CHECK (
    observed_name = btrim(observed_name)
    AND char_length(observed_name) BETWEEN 1 AND 200
    AND normalized_name = btrim(normalized_name)
    AND char_length(normalized_name) BETWEEN 1 AND 200),
  CONSTRAINT menu_evidence_price_check CHECK (
    observed_price_krw IS NULL OR observed_price_krw >= 0),
  CONSTRAINT menu_evidence_context_check CHECK (
    price_context IN ('dine_in', 'pickup', 'delivery', 'order_channel', 'unknown')),
  CONSTRAINT menu_evidence_currentness_check CHECK (
    currentness IN ('HIGH', 'MEDIUM', 'LOW', 'UNKNOWN')),
  CONSTRAINT menu_evidence_status_check CHECK (
    evidence_status IN ('candidate', 'approved', 'rejected', 'superseded')),
  CONSTRAINT menu_evidence_lifecycle_check CHECK (
    (evidence_status IN ('candidate', 'rejected')
      AND menu_id IS NULL AND approval_ref IS NULL)
    OR (evidence_status = 'approved'
      AND menu_id IS NOT NULL AND approval_ref IS NOT NULL)
    OR evidence_status = 'superseded'),
  CONSTRAINT menu_evidence_approval_ref_check CHECK (
    approval_ref IS NULL OR (
      approval_ref = btrim(approval_ref)
      AND char_length(approval_ref) BETWEEN 1 AND 200)),
  CONSTRAINT menu_evidence_notes_check CHECK (
    notes IS NULL OR char_length(notes) <= 1000)
);

CREATE INDEX menu_evidence_store_status_retrieved_idx
  ON burger_map_private.menu_evidence
  (store_id, evidence_status, retrieved_at DESC);
CREATE INDEX menu_evidence_menu_idx
  ON burger_map_private.menu_evidence (menu_id)
  WHERE menu_id IS NOT NULL;

ALTER TABLE burger_map_private.menu_evidence ENABLE ROW LEVEL SECURITY;
-- The parent schema already has authenticated USAGE for unrelated helpers.
-- Keep this table inaccessible to both client roles; no client RLS policy.
REVOKE ALL ON TABLE burger_map_private.menu_evidence
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE burger_map_private.menu_evidence
  TO service_role;
