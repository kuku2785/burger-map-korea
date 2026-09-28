-- A preference may be submitted without written feedback. Non-null feedback
-- retains the original canonical trim, length, and non-whitespace contract.
ALTER TABLE public.reviews ALTER COLUMN content DROP NOT NULL;
ALTER TABLE public.reviews DROP CONSTRAINT reviews_content_length;
ALTER TABLE public.reviews ADD CONSTRAINT reviews_content_length CHECK (
  content IS NULL OR (
    content = btrim(content, E' \t\r\n')
    AND char_length(content) BETWEEN 10 AND 2000
    AND content ~ '[^[:space:]]'
  )
);
