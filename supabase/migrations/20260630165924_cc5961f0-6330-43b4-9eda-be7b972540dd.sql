
-- ===== 1) Column-level hardening on answer-key columns =====
-- Defense-in-depth: even if a SELECT policy is added later, these columns
-- cannot be read by anon/authenticated clients.
REVOKE SELECT (is_correct) ON public.choices FROM anon, authenticated;
REVOKE SELECT (correct_answer, solution_text, intermediate_steps)
  ON public.questions FROM anon, authenticated;

-- ===== 2) Lock down SECURITY DEFINER functions =====
-- Default: revoke EXECUTE from PUBLIC for every definer function, then
-- grant explicitly to the roles that actually need it.

-- Trigger-only / internal helpers — no client should call these.
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column()        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user()                 FROM PUBLIC, anon, authenticated;

-- RLS helper functions — only used inside policies, not from the client.
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.is_admin_or_super(uuid)           FROM PUBLIC, anon, authenticated;

-- Authenticated-only functions
REVOKE EXECUTE ON FUNCTION public.get_user_role(uuid)               FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_user_role(uuid)               TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_test_questions(uuid)          FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_test_questions(uuid)          TO authenticated;

REVOKE EXECUTE ON FUNCTION public.submit_test_attempt(uuid, jsonb, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.submit_test_attempt(uuid, jsonb, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_attempt_review(uuid)          FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_attempt_review(uuid)          TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_published_question_counts()   FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_published_question_counts()   TO authenticated;

REVOKE EXECUTE ON FUNCTION public.verify_test_access(uuid, text)    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.verify_test_access(uuid, text)    TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_test_id_by_code(text)         FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_test_id_by_code(text)         TO authenticated;

REVOKE EXECUTE ON FUNCTION public.ensure_profile(text)              FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ensure_profile(text)              TO authenticated;

REVOKE EXECUTE ON FUNCTION public.claim_super_admin()               FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.claim_super_admin()               TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_tests_admin()                 FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_tests_admin()                 TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_leaderboard(public.subject, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_leaderboard(public.subject, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_platform_stats()              FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_platform_stats()              TO authenticated;
