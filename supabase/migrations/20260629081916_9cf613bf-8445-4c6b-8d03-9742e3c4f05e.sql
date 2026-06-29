-- ============================================================
-- MATH GO: Full schema + 5 variant data
-- ============================================================

-- Enums
CREATE TYPE public.app_role AS ENUM ('super_admin', 'admin', 'user');
CREATE TYPE public.subject AS ENUM ('math', 'physics', 'english', 'history', 'russian', 'uzbek', 'chemistry', 'biology', 'informatics');

-- updated_at helper
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- profiles
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  avatar_url text,
  is_blocked boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- user_roles
CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL DEFAULT 'user',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- role helpers
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;
CREATE OR REPLACE FUNCTION public.is_admin_or_super(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role IN ('super_admin','admin'))
$$;
CREATE OR REPLACE FUNCTION public.get_user_role(_user_id uuid)
RETURNS public.app_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=_user_id AND role='super_admin') THEN 'super_admin'::public.app_role
    WHEN EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=_user_id AND role='admin') THEN 'admin'::public.app_role
    ELSE 'user'::public.app_role END;
$$;

-- profiles policies
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid()=user_id);
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT TO authenticated USING (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid()=user_id) WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Super admins can update all profiles" ON public.profiles FOR UPDATE TO authenticated USING (public.has_role(auth.uid(),'super_admin')) WITH CHECK (public.has_role(auth.uid(),'super_admin'));

-- user_roles policies
CREATE POLICY "Users can view their own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid()=user_id);
CREATE POLICY "Admins can view all roles" ON public.user_roles FOR SELECT TO authenticated USING (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Users can create their own user role" ON public.user_roles FOR INSERT TO authenticated WITH CHECK (auth.uid()=user_id AND role='user');
CREATE POLICY "Super admins can manage all roles" ON public.user_roles FOR ALL TO authenticated USING (public.has_role(auth.uid(),'super_admin')) WITH CHECK (public.has_role(auth.uid(),'super_admin'));

-- tests
CREATE TABLE public.tests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text,
  subject public.subject NOT NULL,
  duration_minutes integer NOT NULL DEFAULT 30,
  is_published boolean NOT NULL DEFAULT false,
  access_code text,
  is_locked boolean GENERATED ALWAYS AS (access_code IS NOT NULL AND access_code <> '') STORED,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.tests TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.tests TO authenticated;
GRANT ALL ON public.tests TO service_role;
REVOKE SELECT (access_code) ON public.tests FROM anon, authenticated;
ALTER TABLE public.tests ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_tests_access_code ON public.tests(access_code) WHERE access_code IS NOT NULL;

-- questions
CREATE TABLE public.questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  question_text text NOT NULL,
  topic text,
  topic_order integer,
  order_index integer NOT NULL DEFAULT 0,
  solution_text text,
  intermediate_steps jsonb NOT NULL DEFAULT '[]'::jsonb,
  correct_answer text,
  source text DEFAULT 'book' CHECK (source IN ('book','ai','manual')),
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.questions TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.questions TO authenticated;
GRANT ALL ON public.questions TO service_role;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_questions_test_order ON public.questions(test_id, order_index);
CREATE INDEX idx_questions_topic_order ON public.questions(test_id, topic_order);

-- choices
CREATE TABLE public.choices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
  choice_text text NOT NULL,
  is_correct boolean NOT NULL DEFAULT false,
  order_index integer NOT NULL DEFAULT 0
);
GRANT SELECT ON public.choices TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.choices TO authenticated;
GRANT ALL ON public.choices TO service_role;
ALTER TABLE public.choices ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_choices_question_order ON public.choices(question_id, order_index);

-- test_attempts
CREATE TABLE public.test_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  test_id uuid NOT NULL REFERENCES public.tests(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  score integer,
  total_questions integer,
  time_spent_seconds integer,
  percentage numeric GENERATED ALWAYS AS (CASE WHEN total_questions IS NULL OR total_questions=0 OR score IS NULL THEN NULL ELSE round(((score::numeric/total_questions::numeric)*100),2) END) STORED,
  grade text GENERATED ALWAYS AS (CASE
    WHEN total_questions IS NULL OR total_questions=0 OR score IS NULL THEN NULL
    WHEN ((score::numeric/total_questions::numeric)*100)>=95 THEN 'A+'
    WHEN ((score::numeric/total_questions::numeric)*100)>=85 THEN 'A'
    WHEN ((score::numeric/total_questions::numeric)*100)>=75 THEN 'B+'
    WHEN ((score::numeric/total_questions::numeric)*100)>=65 THEN 'B'
    WHEN ((score::numeric/total_questions::numeric)*100)>=50 THEN 'C+'
    ELSE 'C' END) STORED
);
GRANT SELECT, INSERT, UPDATE ON public.test_attempts TO authenticated;
GRANT ALL ON public.test_attempts TO service_role;
ALTER TABLE public.test_attempts ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_test_attempts_user_completed ON public.test_attempts(user_id, completed_at DESC);

-- user_answers
CREATE TABLE public.user_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attempt_id uuid NOT NULL REFERENCES public.test_attempts(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
  selected_choice_id uuid REFERENCES public.choices(id) ON DELETE SET NULL,
  text_answer text,
  is_correct boolean,
  UNIQUE (attempt_id, question_id)
);
GRANT SELECT, INSERT ON public.user_answers TO authenticated;
GRANT ALL ON public.user_answers TO service_role;
ALTER TABLE public.user_answers ENABLE ROW LEVEL SECURITY;

-- tests policies
CREATE POLICY "Anyone can view published tests" ON public.tests FOR SELECT TO public USING (is_published=true);
CREATE POLICY "Admins can view all tests" ON public.tests FOR SELECT TO authenticated USING (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Admins can insert tests" ON public.tests FOR INSERT TO authenticated WITH CHECK (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Admins can update tests" ON public.tests FOR UPDATE TO authenticated USING (public.is_admin_or_super(auth.uid())) WITH CHECK (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Admins can delete tests" ON public.tests FOR DELETE TO authenticated USING (public.is_admin_or_super(auth.uid()));

-- questions policies (no public SELECT on choices to hide correct flag; use RPC)
CREATE POLICY "Admins can view all questions" ON public.questions FOR SELECT TO authenticated USING (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Admins can manage questions" ON public.questions FOR ALL TO authenticated USING (public.is_admin_or_super(auth.uid())) WITH CHECK (public.is_admin_or_super(auth.uid()));

-- choices policies
CREATE POLICY "Admins can view all choices" ON public.choices FOR SELECT TO authenticated USING (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Admins can manage choices" ON public.choices FOR ALL TO authenticated USING (public.is_admin_or_super(auth.uid())) WITH CHECK (public.is_admin_or_super(auth.uid()));

-- test_attempts policies
CREATE POLICY "Users can view their own attempts" ON public.test_attempts FOR SELECT TO authenticated USING (auth.uid()=user_id);
CREATE POLICY "Admins can view all attempts" ON public.test_attempts FOR SELECT TO authenticated USING (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Authenticated users can create attempts" ON public.test_attempts FOR INSERT TO authenticated WITH CHECK (auth.uid()=user_id);

-- user_answers policies
CREATE POLICY "Users can view their own answers" ON public.user_answers FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM public.test_attempts ta WHERE ta.id=user_answers.attempt_id AND ta.user_id=auth.uid()));
CREATE POLICY "Admins can view all answers" ON public.user_answers FOR SELECT TO authenticated USING (public.is_admin_or_super(auth.uid()));
CREATE POLICY "Users can insert their own answers" ON public.user_answers FOR INSERT TO authenticated WITH CHECK (EXISTS(SELECT 1 FROM public.test_attempts ta WHERE ta.id=user_answers.attempt_id AND ta.user_id=auth.uid()));

-- Triggers
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_tests_updated_at BEFORE UPDATE ON public.tests FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- new user trigger
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (user_id, full_name) VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email)) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'user') ON CONFLICT DO NOTHING;
  RETURN NEW;
END; $$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ensure_profile / claim_super_admin
CREATE OR REPLACE FUNCTION public.ensure_profile(_full_name text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RETURN; END IF;
  INSERT INTO public.profiles (user_id, full_name) VALUES (uid, COALESCE(NULLIF(_full_name,''),'Foydalanuvchi')) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'user') ON CONFLICT (user_id, role) DO NOTHING;
END; $$;
GRANT EXECUTE ON FUNCTION public.ensure_profile(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_super_admin() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  IF lower((auth.jwt()->>'email'))='admin2o1o@jbn.jbn' THEN
    INSERT INTO public.profiles (user_id, full_name) VALUES (auth.uid(),'Super Admin')
      ON CONFLICT (user_id) DO UPDATE SET full_name=COALESCE(NULLIF(public.profiles.full_name,''),'Super Admin'), updated_at=now();
    INSERT INTO public.user_roles (user_id, role) VALUES (auth.uid(),'super_admin') ON CONFLICT (user_id, role) DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id=auth.uid() AND role='user';
    RETURN true;
  END IF;
  RETURN false;
END; $$;
GRANT EXECUTE ON FUNCTION public.claim_super_admin() TO authenticated;

-- get_test_questions
CREATE OR REPLACE FUNCTION public.get_test_questions(p_test_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(qrow ORDER BY qrow->>'order_index'), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'id', q.id, 'question_text', q.question_text, 'topic', q.topic,
      'order_index', q.order_index,
      'is_input', NOT EXISTS (SELECT 1 FROM public.choices c WHERE c.question_id=q.id),
      'choices', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'choice_text',c.choice_text,'order_index',c.order_index) ORDER BY c.order_index), '[]'::jsonb) FROM public.choices c WHERE c.question_id=q.id)
    ) AS qrow
    FROM public.questions q JOIN public.tests t ON t.id=q.test_id
    WHERE q.test_id=p_test_id AND t.is_published=true
  ) sub;
$$;
GRANT EXECUTE ON FUNCTION public.get_test_questions(uuid) TO anon, authenticated;

-- submit_test_attempt
CREATE OR REPLACE FUNCTION public.submit_test_attempt(p_attempt_id uuid, p_answers jsonb, p_time_spent integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid := auth.uid(); v_attempt public.test_attempts%ROWTYPE; v_score int:=0; v_total int:=0; v_pct numeric:=0; v_grade text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_attempt FROM public.test_attempts WHERE id=p_attempt_id AND user_id=v_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'Attempt not found'; END IF;
  IF v_attempt.completed_at IS NOT NULL THEN RAISE EXCEPTION 'Attempt already completed'; END IF;
  INSERT INTO public.user_answers (attempt_id, question_id, selected_choice_id, text_answer, is_correct)
  SELECT p_attempt_id, q.id,
    CASE WHEN hc.has_choices THEN (raw.raw)::uuid ELSE NULL END,
    CASE WHEN hc.has_choices THEN NULL ELSE raw.raw END,
    CASE WHEN hc.has_choices THEN CASE WHEN raw.raw IS NULL THEN NULL ELSE EXISTS(SELECT 1 FROM public.choices c WHERE c.id=(raw.raw)::uuid AND c.is_correct=true) END
         ELSE CASE WHEN raw.raw IS NULL THEN NULL ELSE lower(regexp_replace(raw.raw,'\s+','','g'))=lower(regexp_replace(coalesce(q.correct_answer,''),'\s+','','g')) END END
  FROM public.questions q
  CROSS JOIN LATERAL (SELECT EXISTS(SELECT 1 FROM public.choices c WHERE c.question_id=q.id) AS has_choices) hc
  LEFT JOIN LATERAL (SELECT NULLIF(p_answers->>q.id::text,'') AS raw) raw ON true
  WHERE q.test_id=v_attempt.test_id
  ON CONFLICT (attempt_id, question_id) DO NOTHING;
  SELECT COUNT(*) FILTER (WHERE ua.is_correct=true), COALESCE(v_attempt.total_questions, COUNT(*)) INTO v_score, v_total FROM public.user_answers ua WHERE ua.attempt_id=p_attempt_id;
  IF v_total IS NULL OR v_total=0 THEN v_total := GREATEST((SELECT COUNT(*) FROM public.questions q WHERE q.test_id=v_attempt.test_id),1); END IF;
  v_pct := ROUND((v_score::numeric/NULLIF(v_total,0))*100, 1);
  v_grade := CASE WHEN v_pct>=95 THEN 'A+' WHEN v_pct>=85 THEN 'A' WHEN v_pct>=75 THEN 'B+' WHEN v_pct>=65 THEN 'B' WHEN v_pct>=50 THEN 'C+' ELSE 'C' END;
  UPDATE public.test_attempts SET completed_at=now(), score=v_score, total_questions=v_total, time_spent_seconds=GREATEST(COALESCE(p_time_spent,0),0) WHERE id=p_attempt_id;
  RETURN jsonb_build_object('attempt_id',p_attempt_id,'score',v_score,'total',v_total,'percentage',v_pct,'grade',v_grade);
END; $$;
GRANT EXECUTE ON FUNCTION public.submit_test_attempt(uuid, jsonb, integer) TO authenticated;

-- get_attempt_review
CREATE OR REPLACE FUNCTION public.get_attempt_review(p_attempt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid:=auth.uid(); v_attempt public.test_attempts%ROWTYPE; v_result jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_attempt FROM public.test_attempts WHERE id=p_attempt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Attempt not found'; END IF;
  IF v_attempt.user_id <> v_user AND NOT public.is_admin_or_super(v_user) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT jsonb_build_object(
    'attempt', jsonb_build_object('id',v_attempt.id,'score',v_attempt.score,'total_questions',v_attempt.total_questions,'time_spent_seconds',v_attempt.time_spent_seconds,'percentage',v_attempt.percentage,'grade',v_attempt.grade),
    'test', (SELECT jsonb_build_object('id',t.id,'title',t.title,'subject',t.subject) FROM public.tests t WHERE t.id=v_attempt.test_id),
    'questions', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',q.id,'question_text',q.question_text,'topic',q.topic,'solution_text',q.solution_text,'intermediate_steps',q.intermediate_steps,'correct_answer',q.correct_answer,'choices',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'choice_text',c.choice_text,'is_correct',c.is_correct) ORDER BY c.order_index),'[]'::jsonb) FROM public.choices c WHERE c.question_id=q.id)) ORDER BY q.order_index),'[]'::jsonb) FROM public.questions q WHERE q.test_id=v_attempt.test_id),
    'answers', (SELECT COALESCE(jsonb_agg(jsonb_build_object('question_id',ua.question_id,'selected_choice_id',ua.selected_choice_id,'text_answer',ua.text_answer,'is_correct',ua.is_correct)),'[]'::jsonb) FROM public.user_answers ua WHERE ua.attempt_id=p_attempt_id)
  ) INTO v_result;
  RETURN v_result;
END; $$;
GRANT EXECUTE ON FUNCTION public.get_attempt_review(uuid) TO authenticated;

-- get_published_question_counts
CREATE OR REPLACE FUNCTION public.get_published_question_counts()
RETURNS TABLE(test_id uuid, question_count bigint) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT q.test_id, COUNT(*)::bigint FROM public.questions q JOIN public.tests t ON t.id=q.test_id WHERE t.is_published=true GROUP BY q.test_id;
$$;
GRANT EXECUTE ON FUNCTION public.get_published_question_counts() TO anon, authenticated;

-- get_leaderboard
CREATE OR REPLACE FUNCTION public.get_leaderboard(p_subject public.subject DEFAULT NULL, p_limit integer DEFAULT 10)
RETURNS TABLE(user_id uuid, full_name text, avatar_url text, total_score bigint, tests_completed bigint, avg_score numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_limit IS NULL OR p_limit<1 THEN p_limit:=10; END IF;
  IF p_limit>100 THEN p_limit:=100; END IF;
  RETURN QUERY
  SELECT p.user_id, p.full_name, p.avatar_url,
    COALESCE(SUM(ta.score),0)::bigint, COUNT(ta.id)::bigint,
    ROUND(COALESCE(AVG(ta.score::numeric/NULLIF(ta.total_questions,0)*100),0),1)
  FROM public.profiles p
  LEFT JOIN public.test_attempts ta ON ta.user_id=p.user_id AND ta.completed_at IS NOT NULL
  LEFT JOIN public.tests t ON t.id=ta.test_id
  WHERE (p_subject IS NULL OR t.subject=p_subject)
    AND NOT public.has_role(p.user_id,'super_admin') AND NOT public.has_role(p.user_id,'admin')
  GROUP BY p.user_id, p.full_name, p.avatar_url
  ORDER BY 4 DESC, 6 DESC LIMIT p_limit;
END; $$;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(public.subject, integer) TO anon, authenticated;

-- get_platform_stats
CREATE OR REPLACE FUNCTION public.get_platform_stats()
RETURNS TABLE(users bigint, questions bigint, tests bigint, attempts bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT (SELECT count(*) FROM public.profiles), (SELECT count(*) FROM public.questions),
         (SELECT count(*) FROM public.tests WHERE is_published=true),
         (SELECT count(*) FROM public.test_attempts WHERE completed_at IS NOT NULL);
$$;
GRANT EXECUTE ON FUNCTION public.get_platform_stats() TO anon, authenticated;

-- verify_test_access / get_test_id_by_code / get_tests_admin
CREATE OR REPLACE FUNCTION public.verify_test_access(p_test_id uuid, p_code text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS(SELECT 1 FROM public.tests t WHERE t.id=p_test_id AND t.is_published=true AND t.access_code=p_code);
$$;
GRANT EXECUTE ON FUNCTION public.verify_test_access(uuid, text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_test_id_by_code(p_code text)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id FROM public.tests t WHERE t.is_published=true AND t.access_code=p_code LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_test_id_by_code(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_tests_admin()
RETURNS TABLE(id uuid, title text, description text, subject public.subject, duration_minutes integer, is_published boolean, access_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.title, t.description, t.subject, t.duration_minutes, t.is_published, t.access_code
  FROM public.tests t WHERE public.is_admin_or_super(auth.uid()) ORDER BY t.created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_tests_admin() TO authenticated;

-- ============================================================
-- DATA: 5 MATH GO variants
-- ============================================================
INSERT INTO public.tests (id,title,subject,duration_minutes,description,is_published) VALUES
  ('a0000000-0000-0000-0000-000000000001','MATH GO - Variant 1','math',60,'Abituriyent matematika varianti 1',true),
  ('a0000000-0000-0000-0000-000000000002','MATH GO - Variant 2','math',60,'Abituriyent matematika varianti 2',true),
  ('a0000000-0000-0000-0000-000000000003','MATH GO - Variant 3','math',60,'Abituriyent matematika varianti 3',true),
  ('a0000000-0000-0000-0000-000000000004','MATH GO - Variant 4','math',60,'Abituriyent matematika varianti 4',true),
  ('a0000000-0000-0000-0000-000000000005','MATH GO - Variant 5','math',60,'Abituriyent matematika varianti 5',true);

-- Variant 1 questions
INSERT INTO public.questions (id,test_id,question_text,topic,order_index,correct_answer) VALUES
('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Agar $a + b = 5$ va $ab = 6$ bo''lsa, $a^2 + b^2$ ning qiymatini toping.','Algebra va sonlar nazariyasi',1,'A'),
('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','30 va 45 sonlarining eng kichik umumiy karralisini (EKUK) toping.','Algebra va sonlar nazariyasi',2,'B'),
('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','Tenglamani yeching: $2x - 7 = 3x + 5$','Algebra va sonlar nazariyasi',3,'B'),
('b0000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','$y = kx + b$ chiziqli funksiya grafiklari $k > 0$ va $b < 0$ bo''lganda qaysi choraklardan o''tadi?','Funksiyalar va tenglamalar',4,'B'),
('b0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','$x^2 - 5x + 6 = 0$ kvadrat tenglamaning ildizlari ko''paytmasini toping.','Funksiyalar va tenglamalar',5,'C'),
('b0000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','Funksiyaning aniqlanish sohasini toping: $y = \sqrt{x - 4}$','Funksiyalar va tenglamalar',6,'A'),
('b0000000-0000-0000-0000-000000000007','a0000000-0000-0000-0000-000000000001','To''g''ri burchakli uchburchakning katetlari 6 va 8 ga teng. Gipotenuzasini toping.','Geometriya',7,'A'),
('b0000000-0000-0000-0000-000000000008','a0000000-0000-0000-0000-000000000001','Muntazam oltiburchakning ichki burchaklari yig''indisi nechaga teng?','Geometriya',8,'C'),
('b0000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000001','Radiusi 5 ga teng bo''lgan doiraning yuzini toping.','Geometriya',9,'B'),
('b0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000001','Kubning qirrasi 3 ga teng bo''lsa, uning to''la sirti yuzini toping.','Stereometriya',10,'B'),
('b0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000001','$\sin^2 30^\circ + \cos^2 30^\circ$ ifodaning qiymatini toping.','Trigonometriya',11,'A'),
('b0000000-0000-0000-0000-000000000012','a0000000-0000-0000-0000-000000000001','5 ta turli kitobni javonga necha xil usulda joylashtirish mumkin?','Kombinatorika va ehtimollar',12,'C');

INSERT INTO public.choices (question_id,choice_text,is_correct,order_index) VALUES
('b0000000-0000-0000-0000-000000000001','A) 13',true,0),('b0000000-0000-0000-0000-000000000001','B) 25',false,1),('b0000000-0000-0000-0000-000000000001','C) 19',false,2),('b0000000-0000-0000-0000-000000000001','D) 11',false,3),
('b0000000-0000-0000-0000-000000000002','A) 15',false,0),('b0000000-0000-0000-0000-000000000002','B) 90',true,1),('b0000000-0000-0000-0000-000000000002','C) 135',false,2),('b0000000-0000-0000-0000-000000000002','D) 60',false,3),
('b0000000-0000-0000-0000-000000000003','A) 12',false,0),('b0000000-0000-0000-0000-000000000003','B) -12',true,1),('b0000000-0000-0000-0000-000000000003','C) 2',false,2),('b0000000-0000-0000-0000-000000000003','D) -2',false,3),
('b0000000-0000-0000-0000-000000000004','A) I, II, III',false,0),('b0000000-0000-0000-0000-000000000004','B) I, III, IV',true,1),('b0000000-0000-0000-0000-000000000004','C) II, III, IV',false,2),('b0000000-0000-0000-0000-000000000004','D) I, II, IV',false,3),
('b0000000-0000-0000-0000-000000000005','A) 5',false,0),('b0000000-0000-0000-0000-000000000005','B) -5',false,1),('b0000000-0000-0000-0000-000000000005','C) 6',true,2),('b0000000-0000-0000-0000-000000000005','D) -6',false,3),
('b0000000-0000-0000-0000-000000000006','A) $x \geq 4$',true,0),('b0000000-0000-0000-0000-000000000006','B) $x > 4$',false,1),('b0000000-0000-0000-0000-000000000006','C) $x \leq 4$',false,2),('b0000000-0000-0000-0000-000000000006','D) Barcha haqiqiy sonlar',false,3),
('b0000000-0000-0000-0000-000000000007','A) 10',true,0),('b0000000-0000-0000-0000-000000000007','B) 14',false,1),('b0000000-0000-0000-0000-000000000007','C) 7',false,2),('b0000000-0000-0000-0000-000000000007','D) 12',false,3),
('b0000000-0000-0000-0000-000000000008','A) $360^\circ$',false,0),('b0000000-0000-0000-0000-000000000008','B) $540^\circ$',false,1),('b0000000-0000-0000-0000-000000000008','C) $720^\circ$',true,2),('b0000000-0000-0000-0000-000000000008','D) $180^\circ$',false,3),
('b0000000-0000-0000-0000-000000000009','A) $10\pi$',false,0),('b0000000-0000-0000-0000-000000000009','B) $25\pi$',true,1),('b0000000-0000-0000-0000-000000000009','C) $5\pi$',false,2),('b0000000-0000-0000-0000-000000000009','D) $20\pi$',false,3),
('b0000000-0000-0000-0000-000000000010','A) 27',false,0),('b0000000-0000-0000-0000-000000000010','B) 54',true,1),('b0000000-0000-0000-0000-000000000010','C) 36',false,2),('b0000000-0000-0000-0000-000000000010','D) 18',false,3),
('b0000000-0000-0000-0000-000000000011','A) 1',true,0),('b0000000-0000-0000-0000-000000000011','B) 0',false,1),('b0000000-0000-0000-0000-000000000011','C) 0.5',false,2),('b0000000-0000-0000-0000-000000000011','D) $\sqrt{3}/2$',false,3),
('b0000000-0000-0000-0000-000000000012','A) 25',false,0),('b0000000-0000-0000-0000-000000000012','B) 60',false,1),('b0000000-0000-0000-0000-000000000012','C) 120',true,2),('b0000000-0000-0000-0000-000000000012','D) 720',false,3);

-- Variant 2
INSERT INTO public.questions (id,test_id,question_text,topic,order_index,correct_answer) VALUES
('b0000000-0000-0000-0000-000000000101','a0000000-0000-0000-0000-000000000002','$(x+3)(x-2)$ ko''paytmani yoying.','Algebra',1,'A'),
('b0000000-0000-0000-0000-000000000102','a0000000-0000-0000-0000-000000000002','$2^{10}$ ning qiymatini toping.','Algebra',2,'B'),
('b0000000-0000-0000-0000-000000000103','a0000000-0000-0000-0000-000000000002','$\log_2 8$ qiymati nechaga teng?','Algebra',3,'C'),
('b0000000-0000-0000-0000-000000000104','a0000000-0000-0000-0000-000000000002','Funksiya: $f(x)=3x+2$. $f(4)$ qiymatini toping.','Funksiyalar',4,'B'),
('b0000000-0000-0000-0000-000000000105','a0000000-0000-0000-0000-000000000002','$x^2=49$ tenglamaning ildizlari yig''indisi.','Funksiyalar',5,'A'),
('b0000000-0000-0000-0000-000000000106','a0000000-0000-0000-0000-000000000002','Arifmetik progressiya: $a_1=2$, $d=3$. $a_{10}$ ni toping.','Funksiyalar',6,'C'),
('b0000000-0000-0000-0000-000000000107','a0000000-0000-0000-0000-000000000002','Uchburchakning tomonlari 3, 4, 5. Yuzi qancha?','Geometriya',7,'A'),
('b0000000-0000-0000-0000-000000000108','a0000000-0000-0000-0000-000000000002','Kvadratning diagonali $4\sqrt{2}$. Tomoni nechaga teng?','Geometriya',8,'B'),
('b0000000-0000-0000-0000-000000000109','a0000000-0000-0000-0000-000000000002','Doiraning aylana uzunligi $10\pi$. Radiusi?','Geometriya',9,'A'),
('b0000000-0000-0000-0000-000000000110','a0000000-0000-0000-0000-000000000002','Silindrning balandligi 5, asos radiusi 3. Hajmi?','Stereometriya',10,'C'),
('b0000000-0000-0000-0000-000000000111','a0000000-0000-0000-0000-000000000002','$\tan 45^\circ$ qiymati?','Trigonometriya',11,'A'),
('b0000000-0000-0000-0000-000000000112','a0000000-0000-0000-0000-000000000002','10 ta sonni tartibga solib joylashtirish — nechta usul?','Kombinatorika',12,'D');

INSERT INTO public.choices (question_id,choice_text,is_correct,order_index) VALUES
('b0000000-0000-0000-0000-000000000101','A) $x^2+x-6$',true,0),('b0000000-0000-0000-0000-000000000101','B) $x^2-x-6$',false,1),('b0000000-0000-0000-0000-000000000101','C) $x^2+5x+6$',false,2),('b0000000-0000-0000-0000-000000000101','D) $x^2-5x-6$',false,3),
('b0000000-0000-0000-0000-000000000102','A) 512',false,0),('b0000000-0000-0000-0000-000000000102','B) 1024',true,1),('b0000000-0000-0000-0000-000000000102','C) 2048',false,2),('b0000000-0000-0000-0000-000000000102','D) 256',false,3),
('b0000000-0000-0000-0000-000000000103','A) 2',false,0),('b0000000-0000-0000-0000-000000000103','B) 4',false,1),('b0000000-0000-0000-0000-000000000103','C) 3',true,2),('b0000000-0000-0000-0000-000000000103','D) 8',false,3),
('b0000000-0000-0000-0000-000000000104','A) 12',false,0),('b0000000-0000-0000-0000-000000000104','B) 14',true,1),('b0000000-0000-0000-0000-000000000104','C) 10',false,2),('b0000000-0000-0000-0000-000000000104','D) 11',false,3),
('b0000000-0000-0000-0000-000000000105','A) 0',true,0),('b0000000-0000-0000-0000-000000000105','B) 7',false,1),('b0000000-0000-0000-0000-000000000105','C) 14',false,2),('b0000000-0000-0000-0000-000000000105','D) -14',false,3),
('b0000000-0000-0000-0000-000000000106','A) 27',false,0),('b0000000-0000-0000-0000-000000000106','B) 32',false,1),('b0000000-0000-0000-0000-000000000106','C) 29',true,2),('b0000000-0000-0000-0000-000000000106','D) 30',false,3),
('b0000000-0000-0000-0000-000000000107','A) 6',true,0),('b0000000-0000-0000-0000-000000000107','B) 12',false,1),('b0000000-0000-0000-0000-000000000107','C) 10',false,2),('b0000000-0000-0000-0000-000000000107','D) 7',false,3),
('b0000000-0000-0000-0000-000000000108','A) 2',false,0),('b0000000-0000-0000-0000-000000000108','B) 4',true,1),('b0000000-0000-0000-0000-000000000108','C) 8',false,2),('b0000000-0000-0000-0000-000000000108','D) $2\sqrt{2}$',false,3),
('b0000000-0000-0000-0000-000000000109','A) 5',true,0),('b0000000-0000-0000-0000-000000000109','B) 10',false,1),('b0000000-0000-0000-0000-000000000109','C) $5\pi$',false,2),('b0000000-0000-0000-0000-000000000109','D) 2.5',false,3),
('b0000000-0000-0000-0000-000000000110','A) $15\pi$',false,0),('b0000000-0000-0000-0000-000000000110','B) $30\pi$',false,1),('b0000000-0000-0000-0000-000000000110','C) $45\pi$',true,2),('b0000000-0000-0000-0000-000000000110','D) $90\pi$',false,3),
('b0000000-0000-0000-0000-000000000111','A) 1',true,0),('b0000000-0000-0000-0000-000000000111','B) 0',false,1),('b0000000-0000-0000-0000-000000000111','C) $\sqrt{2}$',false,2),('b0000000-0000-0000-0000-000000000111','D) $\sqrt{3}$',false,3),
('b0000000-0000-0000-0000-000000000112','A) 100',false,0),('b0000000-0000-0000-0000-000000000112','B) 1000',false,1),('b0000000-0000-0000-0000-000000000112','C) 100000',false,2),('b0000000-0000-0000-0000-000000000112','D) 3628800',true,3);

-- Variant 3
INSERT INTO public.questions (id,test_id,question_text,topic,order_index,correct_answer) VALUES
('b0000000-0000-0000-0000-000000000201','a0000000-0000-0000-0000-000000000003','$\sqrt{144}$ qiymatini toping.','Algebra',1,'A'),
('b0000000-0000-0000-0000-000000000202','a0000000-0000-0000-0000-000000000003','12 ning 25% i nechaga teng?','Algebra',2,'B'),
('b0000000-0000-0000-0000-000000000203','a0000000-0000-0000-0000-000000000003','$3x+9=0$ tenglamani yeching.','Algebra',3,'A'),
('b0000000-0000-0000-0000-000000000204','a0000000-0000-0000-0000-000000000003','$f(x)=x^2$. $f(-3)$ ni toping.','Funksiyalar',4,'C'),
('b0000000-0000-0000-0000-000000000205','a0000000-0000-0000-0000-000000000003','Geometrik progressiya: $b_1=2, q=3$. $b_4$ ni toping.','Funksiyalar',5,'B'),
('b0000000-0000-0000-0000-000000000206','a0000000-0000-0000-0000-000000000003','$|x|=5$ tenglamaning ildizlari.','Funksiyalar',6,'D'),
('b0000000-0000-0000-0000-000000000207','a0000000-0000-0000-0000-000000000003','To''rtburchakning ichki burchaklari yig''indisi.','Geometriya',7,'C'),
('b0000000-0000-0000-0000-000000000208','a0000000-0000-0000-0000-000000000003','Teng yonli uchburchakda asosga tushirilgan balandlik nima qiladi?','Geometriya',8,'A'),
('b0000000-0000-0000-0000-000000000209','a0000000-0000-0000-0000-000000000003','Aylana radiusi 7. Yuzi?','Geometriya',9,'B'),
('b0000000-0000-0000-0000-000000000210','a0000000-0000-0000-0000-000000000003','Shar radiusi 3. Hajmi?','Stereometriya',10,'A'),
('b0000000-0000-0000-0000-000000000211','a0000000-0000-0000-0000-000000000003','$\cos 60^\circ$ qiymati?','Trigonometriya',11,'B'),
('b0000000-0000-0000-0000-000000000212','a0000000-0000-0000-0000-000000000003','3 ta sariq, 2 ta qizil sharlar qutiga solinadi. Qizil sharni olish ehtimolligi?','Ehtimollar',12,'C');

INSERT INTO public.choices (question_id,choice_text,is_correct,order_index) VALUES
('b0000000-0000-0000-0000-000000000201','A) 12',true,0),('b0000000-0000-0000-0000-000000000201','B) 14',false,1),('b0000000-0000-0000-0000-000000000201','C) 10',false,2),('b0000000-0000-0000-0000-000000000201','D) 13',false,3),
('b0000000-0000-0000-0000-000000000202','A) 2',false,0),('b0000000-0000-0000-0000-000000000202','B) 3',true,1),('b0000000-0000-0000-0000-000000000202','C) 4',false,2),('b0000000-0000-0000-0000-000000000202','D) 6',false,3),
('b0000000-0000-0000-0000-000000000203','A) -3',true,0),('b0000000-0000-0000-0000-000000000203','B) 3',false,1),('b0000000-0000-0000-0000-000000000203','C) 9',false,2),('b0000000-0000-0000-0000-000000000203','D) -9',false,3),
('b0000000-0000-0000-0000-000000000204','A) -9',false,0),('b0000000-0000-0000-0000-000000000204','B) -6',false,1),('b0000000-0000-0000-0000-000000000204','C) 9',true,2),('b0000000-0000-0000-0000-000000000204','D) 6',false,3),
('b0000000-0000-0000-0000-000000000205','A) 18',false,0),('b0000000-0000-0000-0000-000000000205','B) 54',true,1),('b0000000-0000-0000-0000-000000000205','C) 27',false,2),('b0000000-0000-0000-0000-000000000205','D) 12',false,3),
('b0000000-0000-0000-0000-000000000206','A) 5',false,0),('b0000000-0000-0000-0000-000000000206','B) -5',false,1),('b0000000-0000-0000-0000-000000000206','C) 0',false,2),('b0000000-0000-0000-0000-000000000206','D) 5 va -5',true,3),
('b0000000-0000-0000-0000-000000000207','A) $180^\circ$',false,0),('b0000000-0000-0000-0000-000000000207','B) $270^\circ$',false,1),('b0000000-0000-0000-0000-000000000207','C) $360^\circ$',true,2),('b0000000-0000-0000-0000-000000000207','D) $540^\circ$',false,3),
('b0000000-0000-0000-0000-000000000208','A) Mediana va bissektrisa',true,0),('b0000000-0000-0000-0000-000000000208','B) Faqat mediana',false,1),('b0000000-0000-0000-0000-000000000208','C) Faqat bissektrisa',false,2),('b0000000-0000-0000-0000-000000000208','D) Hech narsa',false,3),
('b0000000-0000-0000-0000-000000000209','A) $14\pi$',false,0),('b0000000-0000-0000-0000-000000000209','B) $49\pi$',true,1),('b0000000-0000-0000-0000-000000000209','C) $7\pi$',false,2),('b0000000-0000-0000-0000-000000000209','D) $98\pi$',false,3),
('b0000000-0000-0000-0000-000000000210','A) $36\pi$',true,0),('b0000000-0000-0000-0000-000000000210','B) $27\pi$',false,1),('b0000000-0000-0000-0000-000000000210','C) $12\pi$',false,2),('b0000000-0000-0000-0000-000000000210','D) $9\pi$',false,3),
('b0000000-0000-0000-0000-000000000211','A) 1',false,0),('b0000000-0000-0000-0000-000000000211','B) 0.5',true,1),('b0000000-0000-0000-0000-000000000211','C) $\sqrt{3}/2$',false,2),('b0000000-0000-0000-0000-000000000211','D) 0',false,3),
('b0000000-0000-0000-0000-000000000212','A) 1/5',false,0),('b0000000-0000-0000-0000-000000000212','B) 3/5',false,1),('b0000000-0000-0000-0000-000000000212','C) 2/5',true,2),('b0000000-0000-0000-0000-000000000212','D) 1/2',false,3);

-- Variant 4
INSERT INTO public.questions (id,test_id,question_text,topic,order_index,correct_answer) VALUES
('b0000000-0000-0000-0000-000000000301','a0000000-0000-0000-0000-000000000004','$15-3\cdot(4-2)$ ning qiymati.','Algebra',1,'C'),
('b0000000-0000-0000-0000-000000000302','a0000000-0000-0000-0000-000000000004','$\frac{2}{3}+\frac{1}{6}$ ning qiymati.','Algebra',2,'A'),
('b0000000-0000-0000-0000-000000000303','a0000000-0000-0000-0000-000000000004','$3(x-2)=12$ tenglamani yeching.','Algebra',3,'B'),
('b0000000-0000-0000-0000-000000000304','a0000000-0000-0000-0000-000000000004','$y=x^2-4$. $y=0$ bo''lganda $x$ ning qiymatlari?','Funksiyalar',4,'D'),
('b0000000-0000-0000-0000-000000000305','a0000000-0000-0000-0000-000000000004','$f(x)=2x-1$. Teskari funksiya $f^{-1}(x)$?','Funksiyalar',5,'A'),
('b0000000-0000-0000-0000-000000000306','a0000000-0000-0000-0000-000000000004','$x^2-9>0$ tengsizlikning yechimi.','Funksiyalar',6,'B'),
('b0000000-0000-0000-0000-000000000307','a0000000-0000-0000-0000-000000000004','Parallelogrammning yuzasi $a\cdot h$ formula bilan qaerda $h$ nima?','Geometriya',7,'C'),
('b0000000-0000-0000-0000-000000000308','a0000000-0000-0000-0000-000000000004','Uchburchakning medianalari kesishish nuqtasi nima deyiladi?','Geometriya',8,'A'),
('b0000000-0000-0000-0000-000000000309','a0000000-0000-0000-0000-000000000004','Yarim doira yuzasi $r=4$ bo''lganda?','Geometriya',9,'B'),
('b0000000-0000-0000-0000-000000000310','a0000000-0000-0000-0000-000000000004','Konusning balandligi 4, asos radiusi 3. Yon sirti hosil qiluvchi uzunligi?','Stereometriya',10,'A'),
('b0000000-0000-0000-0000-000000000311','a0000000-0000-0000-0000-000000000004','$\sin 90^\circ + \cos 0^\circ$?','Trigonometriya',11,'D'),
('b0000000-0000-0000-0000-000000000312','a0000000-0000-0000-0000-000000000004','Tanga 3 marta tashlanadi. Faqat 1 marta gerb tushishi ehtimolligi?','Ehtimollar',12,'C');

INSERT INTO public.choices (question_id,choice_text,is_correct,order_index) VALUES
('b0000000-0000-0000-0000-000000000301','A) 24',false,0),('b0000000-0000-0000-0000-000000000301','B) 6',false,1),('b0000000-0000-0000-0000-000000000301','C) 9',true,2),('b0000000-0000-0000-0000-000000000301','D) 12',false,3),
('b0000000-0000-0000-0000-000000000302','A) $\frac{5}{6}$',true,0),('b0000000-0000-0000-0000-000000000302','B) $\frac{3}{9}$',false,1),('b0000000-0000-0000-0000-000000000302','C) $\frac{1}{2}$',false,2),('b0000000-0000-0000-0000-000000000302','D) $\frac{2}{6}$',false,3),
('b0000000-0000-0000-0000-000000000303','A) 4',false,0),('b0000000-0000-0000-0000-000000000303','B) 6',true,1),('b0000000-0000-0000-0000-000000000303','C) 2',false,2),('b0000000-0000-0000-0000-000000000303','D) 14',false,3),
('b0000000-0000-0000-0000-000000000304','A) 2',false,0),('b0000000-0000-0000-0000-000000000304','B) -2',false,1),('b0000000-0000-0000-0000-000000000304','C) 4',false,2),('b0000000-0000-0000-0000-000000000304','D) 2 va -2',true,3),
('b0000000-0000-0000-0000-000000000305','A) $\frac{x+1}{2}$',true,0),('b0000000-0000-0000-0000-000000000305','B) $\frac{x-1}{2}$',false,1),('b0000000-0000-0000-0000-000000000305','C) $2x+1$',false,2),('b0000000-0000-0000-0000-000000000305','D) $2x-1$',false,3),
('b0000000-0000-0000-0000-000000000306','A) $-3<x<3$',false,0),('b0000000-0000-0000-0000-000000000306','B) $x<-3$ yoki $x>3$',true,1),('b0000000-0000-0000-0000-000000000306','C) $x>3$',false,2),('b0000000-0000-0000-0000-000000000306','D) $x<-3$',false,3),
('b0000000-0000-0000-0000-000000000307','A) Diagonal',false,0),('b0000000-0000-0000-0000-000000000307','B) Tomon',false,1),('b0000000-0000-0000-0000-000000000307','C) Balandlik',true,2),('b0000000-0000-0000-0000-000000000307','D) Burchak',false,3),
('b0000000-0000-0000-0000-000000000308','A) Centroid (markaz)',true,0),('b0000000-0000-0000-0000-000000000308','B) Ortotsentr',false,1),('b0000000-0000-0000-0000-000000000308','C) Insentr',false,2),('b0000000-0000-0000-0000-000000000308','D) Sirkumsentr',false,3),
('b0000000-0000-0000-0000-000000000309','A) $4\pi$',false,0),('b0000000-0000-0000-0000-000000000309','B) $8\pi$',true,1),('b0000000-0000-0000-0000-000000000309','C) $16\pi$',false,2),('b0000000-0000-0000-0000-000000000309','D) $2\pi$',false,3),
('b0000000-0000-0000-0000-000000000310','A) 5',true,0),('b0000000-0000-0000-0000-000000000310','B) 7',false,1),('b0000000-0000-0000-0000-000000000310','C) 4',false,2),('b0000000-0000-0000-0000-000000000310','D) 6',false,3),
('b0000000-0000-0000-0000-000000000311','A) 0',false,0),('b0000000-0000-0000-0000-000000000311','B) 1',false,1),('b0000000-0000-0000-0000-000000000311','C) -1',false,2),('b0000000-0000-0000-0000-000000000311','D) 2',true,3),
('b0000000-0000-0000-0000-000000000312','A) 1/8',false,0),('b0000000-0000-0000-0000-000000000312','B) 1/2',false,1),('b0000000-0000-0000-0000-000000000312','C) 3/8',true,2),('b0000000-0000-0000-0000-000000000312','D) 1/4',false,3);

-- Variant 5
INSERT INTO public.questions (id,test_id,question_text,topic,order_index,correct_answer) VALUES
('b0000000-0000-0000-0000-000000000401','a0000000-0000-0000-0000-000000000005','$5^3$ ning qiymati.','Algebra',1,'B'),
('b0000000-0000-0000-0000-000000000402','a0000000-0000-0000-0000-000000000005','$\frac{3}{4}\cdot\frac{8}{9}$ ning qiymati.','Algebra',2,'A'),
('b0000000-0000-0000-0000-000000000403','a0000000-0000-0000-0000-000000000005','$x-7=3x+1$ tenglamani yeching.','Algebra',3,'B'),
('b0000000-0000-0000-0000-000000000404','a0000000-0000-0000-0000-000000000005','$f(x)=\sqrt{x}$ funksiyaning aniqlanish sohasi.','Funksiyalar',4,'D'),
('b0000000-0000-0000-0000-000000000405','a0000000-0000-0000-0000-000000000005','$2x+y=6, x-y=0$ sistemani yeching: $x=?$','Funksiyalar',5,'C'),
('b0000000-0000-0000-0000-000000000406','a0000000-0000-0000-0000-000000000005','$x^2-4x+4=0$ tenglamaning ildizi.','Funksiyalar',6,'A'),
('b0000000-0000-0000-0000-000000000407','a0000000-0000-0000-0000-000000000005','Kvadrat tomoni 6. Perimetri?','Geometriya',7,'D'),
('b0000000-0000-0000-0000-000000000408','a0000000-0000-0000-0000-000000000005','Romb diagonallari 6 va 8. Yuzi?','Geometriya',8,'B'),
('b0000000-0000-0000-0000-000000000409','a0000000-0000-0000-0000-000000000005','Aylana ichiga chizilgan to''g''ri burchakli uchburchakda gipotenuza nimaga teng?','Geometriya',9,'C'),
('b0000000-0000-0000-0000-000000000410','a0000000-0000-0000-0000-000000000005','Piramida asosi kvadrat tomoni 4, balandligi 6. Hajmi?','Stereometriya',10,'A'),
('b0000000-0000-0000-0000-000000000411','a0000000-0000-0000-0000-000000000005','$\sin(180^\circ-x)$ nimaga teng?','Trigonometriya',11,'A'),
('b0000000-0000-0000-0000-000000000412','a0000000-0000-0000-0000-000000000005','6 qirrali zarni tashlaganda 4 dan katta son tushish ehtimolligi?','Ehtimollar',12,'B');

INSERT INTO public.choices (question_id,choice_text,is_correct,order_index) VALUES
('b0000000-0000-0000-0000-000000000401','A) 15',false,0),('b0000000-0000-0000-0000-000000000401','B) 125',true,1),('b0000000-0000-0000-0000-000000000401','C) 25',false,2),('b0000000-0000-0000-0000-000000000401','D) 75',false,3),
('b0000000-0000-0000-0000-000000000402','A) $\frac{2}{3}$',true,0),('b0000000-0000-0000-0000-000000000402','B) $\frac{24}{36}$',false,1),('b0000000-0000-0000-0000-000000000402','C) $\frac{11}{13}$',false,2),('b0000000-0000-0000-0000-000000000402','D) $\frac{1}{3}$',false,3),
('b0000000-0000-0000-0000-000000000403','A) 4',false,0),('b0000000-0000-0000-0000-000000000403','B) -4',true,1),('b0000000-0000-0000-0000-000000000403','C) 2',false,2),('b0000000-0000-0000-0000-000000000403','D) -2',false,3),
('b0000000-0000-0000-0000-000000000404','A) $x>0$',false,0),('b0000000-0000-0000-0000-000000000404','B) $x<0$',false,1),('b0000000-0000-0000-0000-000000000404','C) Hamma haqiqiy son',false,2),('b0000000-0000-0000-0000-000000000404','D) $x\geq 0$',true,3),
('b0000000-0000-0000-0000-000000000405','A) 1',false,0),('b0000000-0000-0000-0000-000000000405','B) 3',false,1),('b0000000-0000-0000-0000-000000000405','C) 2',true,2),('b0000000-0000-0000-0000-000000000405','D) 4',false,3),
('b0000000-0000-0000-0000-000000000406','A) 2',true,0),('b0000000-0000-0000-0000-000000000406','B) -2',false,1),('b0000000-0000-0000-0000-000000000406','C) 4',false,2),('b0000000-0000-0000-0000-000000000406','D) 1',false,3),
('b0000000-0000-0000-0000-000000000407','A) 36',false,0),('b0000000-0000-0000-0000-000000000407','B) 12',false,1),('b0000000-0000-0000-0000-000000000407','C) 6',false,2),('b0000000-0000-0000-0000-000000000407','D) 24',true,3),
('b0000000-0000-0000-0000-000000000408','A) 48',false,0),('b0000000-0000-0000-0000-000000000408','B) 24',true,1),('b0000000-0000-0000-0000-000000000408','C) 14',false,2),('b0000000-0000-0000-0000-000000000408','D) 12',false,3),
('b0000000-0000-0000-0000-000000000409','A) Radiusga teng',false,0),('b0000000-0000-0000-0000-000000000409','B) Yarim radiusga teng',false,1),('b0000000-0000-0000-0000-000000000409','C) Diametrga teng',true,2),('b0000000-0000-0000-0000-000000000409','D) Ikki diametrga teng',false,3),
('b0000000-0000-0000-0000-000000000410','A) 32',true,0),('b0000000-0000-0000-0000-000000000410','B) 96',false,1),('b0000000-0000-0000-0000-000000000410','C) 48',false,2),('b0000000-0000-0000-0000-000000000410','D) 24',false,3),
('b0000000-0000-0000-0000-000000000411','A) $\sin x$',true,0),('b0000000-0000-0000-0000-000000000411','B) $-\sin x$',false,1),('b0000000-0000-0000-0000-000000000411','C) $\cos x$',false,2),('b0000000-0000-0000-0000-000000000411','D) $-\cos x$',false,3),
('b0000000-0000-0000-0000-000000000412','A) 1/2',false,0),('b0000000-0000-0000-0000-000000000412','B) 1/3',true,1),('b0000000-0000-0000-0000-000000000412','C) 1/6',false,2),('b0000000-0000-0000-0000-000000000412','D) 2/3',false,3);
