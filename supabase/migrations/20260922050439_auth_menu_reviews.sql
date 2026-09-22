CREATE SCHEMA burger_map_private;
REVOKE ALL ON SCHEMA burger_map_private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA burger_map_private TO authenticated, service_role;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nickname text NOT NULL,
  is_suspended boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_nickname_length CHECK (char_length(nickname) BETWEEN 2 AND 20),
  CONSTRAINT profiles_nickname_characters CHECK (nickname ~ '^[가-힣A-Za-z0-9_]+$'),
  CONSTRAINT profiles_nickname_reserved CHECK (
    lower(nickname) !~ '(admin|moderator|support|운영자|관리자|버거맵)'
  )
);

CREATE TABLE public.menus (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE RESTRICT,
  name text NOT NULL,
  price integer,
  category text,
  description text,
  is_signature boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT menus_name_length CHECK (name = btrim(name) AND char_length(name) BETWEEN 1 AND 100),
  CONSTRAINT menus_price_nonnegative CHECK (price IS NULL OR price >= 0),
  CONSTRAINT menus_category_length CHECK (category IS NULL OR (category = btrim(category) AND char_length(category) BETWEEN 1 AND 40)),
  CONSTRAINT menus_description_length CHECK (description IS NULL OR char_length(description) <= 1000),
  CONSTRAINT menus_display_order_nonnegative CHECK (display_order >= 0)
);
CREATE INDEX menus_store_order_idx ON public.menus (store_id, is_active, display_order, id);

CREATE TABLE public.reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL REFERENCES public.stores(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating smallint NOT NULL,
  content text NOT NULL,
  is_hidden boolean NOT NULL DEFAULT false,
  moderation_note text,
  moderated_at timestamptz,
  moderated_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reviews_one_per_store_user UNIQUE (store_id, user_id),
  CONSTRAINT reviews_rating_range CHECK (rating BETWEEN 1 AND 5),
  CONSTRAINT reviews_content_length CHECK (content = btrim(content, E' \t\r\n') AND char_length(content) BETWEEN 10 AND 2000 AND content ~ '[^[:space:]]'),
  CONSTRAINT reviews_moderation_note_length CHECK (moderation_note IS NULL OR char_length(btrim(moderation_note)) BETWEEN 1 AND 1000),
  CONSTRAINT reviews_moderated_by_length CHECK (moderated_by IS NULL OR char_length(btrim(moderated_by)) BETWEEN 1 AND 100),
  CONSTRAINT reviews_moderation_metadata_consistent CHECK ((moderation_note IS NULL AND moderated_at IS NULL AND moderated_by IS NULL) OR (moderation_note IS NOT NULL AND moderated_at IS NOT NULL AND moderated_by IS NOT NULL)),
  CONSTRAINT reviews_hidden_requires_moderation CHECK (NOT is_hidden OR moderated_at IS NOT NULL)
);
CREATE INDEX reviews_public_store_created_idx ON public.reviews (store_id, created_at DESC, id DESC) WHERE NOT is_hidden;
CREATE INDEX reviews_user_created_idx ON public.reviews (user_id, created_at DESC, id DESC);

CREATE TABLE public.review_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
  reporter_user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text NOT NULL,
  detail text,
  status text NOT NULL DEFAULT 'pending',
  resolution_note text,
  resolved_at timestamptz,
  resolved_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT review_reports_one_per_reporter UNIQUE (review_id, reporter_user_id),
  CONSTRAINT review_reports_reason_allowed CHECK (reason IN ('spam', 'harassment', 'personal_information', 'irrelevant', 'other')),
  CONSTRAINT review_reports_detail_length CHECK (detail IS NULL OR (detail = btrim(detail, E' \t\r\n') AND char_length(detail) BETWEEN 1 AND 1000)),
  CONSTRAINT review_reports_other_needs_detail CHECK (reason <> 'other' OR detail IS NOT NULL),
  CONSTRAINT review_reports_status_allowed CHECK (status IN ('pending', 'resolved', 'dismissed')),
  CONSTRAINT review_reports_resolution_note_length CHECK (resolution_note IS NULL OR char_length(btrim(resolution_note)) BETWEEN 1 AND 1000),
  CONSTRAINT review_reports_resolved_by_length CHECK (resolved_by IS NULL OR char_length(btrim(resolved_by)) BETWEEN 1 AND 100),
  CONSTRAINT review_reports_resolution_consistent CHECK ((status = 'pending' AND resolution_note IS NULL AND resolved_at IS NULL AND resolved_by IS NULL) OR (status <> 'pending' AND resolution_note IS NOT NULL AND resolved_at IS NOT NULL AND resolved_by IS NOT NULL))
);
CREATE INDEX review_reports_reporter_idx ON public.review_reports (reporter_user_id);
CREATE INDEX review_reports_queue_idx ON public.review_reports (status, created_at, id);

CREATE FUNCTION burger_map_private.can_contribute()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND coalesce(auth.jwt() ->> 'is_anonymous', 'false') = 'false'
    AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND NOT p.is_suspended);
$function$;
REVOKE ALL ON FUNCTION burger_map_private.can_contribute() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION burger_map_private.can_contribute() TO authenticated;

CREATE FUNCTION burger_map_private.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$function$;
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION burger_map_private.set_updated_at();
CREATE TRIGGER menus_set_updated_at BEFORE UPDATE ON public.menus FOR EACH ROW EXECUTE FUNCTION burger_map_private.set_updated_at();
CREATE TRIGGER reviews_set_updated_at BEFORE UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION burger_map_private.set_updated_at();
CREATE TRIGGER review_reports_set_updated_at BEFORE UPDATE ON public.review_reports FOR EACH ROW EXECUTE FUNCTION burger_map_private.set_updated_at();
REVOKE ALL ON FUNCTION burger_map_private.set_updated_at() FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menus ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.profiles, public.menus, public.reviews, public.review_reports FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT (id, nickname) ON public.profiles TO anon, authenticated;
GRANT INSERT (id, nickname) ON public.profiles TO authenticated;
GRANT UPDATE (nickname) ON public.profiles TO authenticated;
GRANT SELECT ON public.menus TO anon, authenticated;
GRANT SELECT (id, store_id, user_id, rating, content, is_hidden, created_at, updated_at) ON public.reviews TO anon, authenticated;
GRANT INSERT (store_id, rating, content) ON public.reviews TO authenticated;
GRANT UPDATE (rating, content) ON public.reviews TO authenticated;
GRANT DELETE ON public.reviews TO authenticated;
GRANT INSERT (review_id, reason, detail) ON public.review_reports TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles, public.menus, public.reviews, public.review_reports TO service_role;

CREATE POLICY menus_public_read ON public.menus FOR SELECT TO anon, authenticated USING (is_active AND EXISTS (SELECT 1 FROM public.stores s WHERE s.id = menus.store_id AND s.verification_status = 'verified' AND s.is_active = true));
CREATE POLICY reviews_public_read ON public.reviews FOR SELECT TO anon, authenticated USING (NOT is_hidden AND EXISTS (SELECT 1 FROM public.stores s WHERE s.id = reviews.store_id AND s.verification_status = 'verified' AND s.is_active = true));
CREATE POLICY reviews_owner_manage_read ON public.reviews FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY profiles_owner_read ON public.profiles FOR SELECT TO authenticated USING ((SELECT auth.uid()) = id);
CREATE POLICY profiles_public_author_read ON public.profiles FOR SELECT TO anon, authenticated USING (EXISTS (SELECT 1 FROM public.reviews r JOIN public.stores s ON s.id = r.store_id WHERE r.user_id = profiles.id AND NOT r.is_hidden AND s.verification_status = 'verified' AND s.is_active = true));
CREATE POLICY profiles_owner_insert ON public.profiles FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = id AND coalesce((SELECT auth.jwt() ->> 'is_anonymous'), 'false') = 'false');
CREATE POLICY profiles_owner_update ON public.profiles FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = id AND (SELECT burger_map_private.can_contribute())) WITH CHECK ((SELECT auth.uid()) = id AND (SELECT burger_map_private.can_contribute()));
CREATE POLICY reviews_owner_insert ON public.reviews FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id AND (SELECT burger_map_private.can_contribute()) AND NOT is_hidden AND moderation_note IS NULL AND moderated_at IS NULL AND moderated_by IS NULL AND EXISTS (SELECT 1 FROM public.stores s WHERE s.id = reviews.store_id AND s.verification_status = 'verified' AND s.is_active = true));
CREATE POLICY reviews_owner_update ON public.reviews FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id AND (SELECT burger_map_private.can_contribute()) AND EXISTS (SELECT 1 FROM public.stores s WHERE s.id = reviews.store_id AND s.verification_status = 'verified' AND s.is_active = true)) WITH CHECK ((SELECT auth.uid()) = user_id AND (SELECT burger_map_private.can_contribute()) AND EXISTS (SELECT 1 FROM public.stores s WHERE s.id = reviews.store_id AND s.verification_status = 'verified' AND s.is_active = true));
CREATE POLICY reviews_owner_delete ON public.reviews FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY review_reports_owner_insert ON public.review_reports FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = reporter_user_id AND (SELECT burger_map_private.can_contribute()) AND status = 'pending' AND resolution_note IS NULL AND resolved_at IS NULL AND resolved_by IS NULL AND EXISTS (SELECT 1 FROM public.reviews r JOIN public.stores s ON s.id = r.store_id WHERE r.id = review_reports.review_id AND NOT r.is_hidden AND r.user_id <> (SELECT auth.uid()) AND s.verification_status = 'verified' AND s.is_active = true));

CREATE VIEW public.public_reviews WITH (security_invoker = true, security_barrier = true) AS SELECT r.id, r.store_id, r.user_id, r.rating, r.content, r.created_at, r.updated_at FROM public.reviews r JOIN public.stores s ON s.id = r.store_id WHERE NOT r.is_hidden AND s.verification_status = 'verified' AND s.is_active = true;
CREATE VIEW public.store_review_stats WITH (security_invoker = true, security_barrier = true) AS SELECT s.id AS store_id, count(r.id) AS review_count, round(avg(r.rating::numeric), 1) AS average_rating FROM public.stores s LEFT JOIN public.reviews r ON r.store_id = s.id AND NOT r.is_hidden WHERE s.verification_status = 'verified' AND s.is_active = true GROUP BY s.id;
REVOKE ALL ON TABLE public.public_reviews, public.store_review_stats FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.public_reviews, public.store_review_stats TO anon, authenticated, service_role;
