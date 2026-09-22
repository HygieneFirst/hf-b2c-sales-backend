


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."b2c_ai_merge_human_follow_up"("p_existing" boolean, "p_extracted" "jsonb") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select
    case
      when p_existing = true then true

      when p_extracted ? 'human_follow_up_required'
        and p_extracted->'human_follow_up_required' <> 'null'::jsonb
      then (p_extracted->>'human_follow_up_required')::boolean

      else p_existing
    end;
$$;


ALTER FUNCTION "public"."b2c_ai_merge_human_follow_up"("p_existing" boolean, "p_extracted" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_apply_ai_result_and_mark_processed"("p_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_extractor_version" "text" DEFAULT NULL::"text", "p_whatsapp_number" "text" DEFAULT NULL::"text") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "lead_status" "text", "was_created" boolean, "ai_event_id" "uuid", "processing_status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_message public.b2c_inbound_messages%rowtype;

  v_lead_id uuid;
  v_lead_no text;
  v_initial_status text;
  v_was_created boolean;

  v_updated_lead_id uuid;
  v_updated_lead_no text;
  v_updated_status text;
  v_ai_event_id uuid;

  v_service_category text;
begin

  if nullif(btrim(p_message_id), '') is null then
    raise exception 'message_id is required'
      using errcode = '22023';
  end if;

  if p_extraction is null
     or jsonb_typeof(p_extraction) <> 'object' then
    raise exception 'p_extraction must be a JSON object'
      using errcode = '22023';
  end if;


  select *
  into v_message
  from public.b2c_inbound_messages
  where message_id = p_message_id
  for update;


  if not found then
    raise exception 'Inbound message % not found', p_message_id;
  end if;


  if v_message.processing_status <> 'PROCESSING' then
    raise exception
      'Inbound message % is not in PROCESSING state (current: %)',
      p_message_id,
      v_message.processing_status;
  end if;


  v_service_category :=
    lower(
      nullif(
        btrim(p_extraction->>'service_category'),
        ''
      )
    );

  if v_service_category = 'unknown' then
    v_service_category := null;
  end if;


  select
    g.lead_id,
    g.lead_no,
    g.was_created,
    g.lead_status
  into
    v_lead_id,
    v_lead_no,
    v_was_created,
    v_initial_status
  from public.b2c_get_or_create_active_lead_v2(
    v_message.woztell_member_id,
    v_message.woztell_channel_id,
    p_whatsapp_number,
    v_service_category
  ) g;


  if v_was_created then

    insert into public.b2c_lead_events (
      lead_id,
      event_type,
      actor_type,
      source_message_id,
      after_data,
      metadata
    )
    values (
      v_lead_id,
      'LEAD_CREATED',
      'SYSTEM',
      p_message_id,
      jsonb_build_object(
        'status', 'NEW',
        'service_category', v_service_category
      ),
      jsonb_build_object(
        'source', 'WOZTELL_INBOUND'
      )
    );

  end if;


  select
    u.lead_id,
    u.lead_no,
    u.lead_status,
    u.event_id
  into
    v_updated_lead_id,
    v_updated_lead_no,
    v_updated_status,
    v_ai_event_id
  from public.b2c_update_lead_from_ai(
    v_lead_id,
    p_message_id,
    p_extraction,
    coalesce(
      p_customer_message_at,
      v_message.customer_message_at
    ),
    p_extractor_version
  ) u;


  update public.b2c_inbound_messages as m
  set
    processing_status = 'PROCESSED',
    lead_id = v_lead_id,
    processed_at = now(),
    last_error = null
  where m.message_id = p_message_id
    and m.processing_status = 'PROCESSING';


  if not found then
    raise exception
      'Unable to mark inbound message % as PROCESSED',
      p_message_id;
  end if;


  return query
  select
    v_updated_lead_id,
    v_updated_lead_no,
    v_updated_status,
    v_was_created,
    v_ai_event_id,
    'PROCESSED'::text;

end;
$$;


ALTER FUNCTION "public"."b2c_apply_ai_result_and_mark_processed"("p_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone, "p_extractor_version" "text", "p_whatsapp_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_assign_ready_lead"("p_lead_id" "uuid", "p_dispatcher_user_id" "uuid", "p_sales_user_id" "uuid") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "lead_status" "text", "assigned_sales_user_id" "uuid", "assigned_by_user_id" "uuid", "assigned_at" timestamp with time zone, "event_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_before public.b2c_leads%rowtype;
  v_after public.b2c_leads%rowtype;

  v_dispatcher public.b2c_staff_users%rowtype;
  v_sales public.b2c_staff_users%rowtype;

  v_event_id uuid;
begin

  -- ---------------------------------------------------------
  -- Validate required parameters
  -- ---------------------------------------------------------

  if p_lead_id is null then
    raise exception 'lead_id is required'
      using errcode = '22023';
  end if;

  if p_dispatcher_user_id is null then
    raise exception 'dispatcher_user_id is required'
      using errcode = '22023';
  end if;

  if p_sales_user_id is null then
    raise exception 'sales_user_id is required'
      using errcode = '22023';
  end if;


  -- ---------------------------------------------------------
  -- Lock Lead
  -- ---------------------------------------------------------

  select *
  into v_before
  from public.b2c_leads
  where id = p_lead_id
  for update;

  if not found then
    raise exception 'Lead % not found', p_lead_id;
  end if;


  -- ---------------------------------------------------------
  -- Only READY_FOR_REVIEW may be assigned by this RPC.
  --
  -- This also makes duplicate / double-click attempts
  -- fail closed after the first successful assignment.
  -- ---------------------------------------------------------

  if v_before.status <> 'READY_FOR_REVIEW' then
    raise exception
      'Lead % is not READY_FOR_REVIEW (current: %)',
      p_lead_id,
      v_before.status
      using errcode = '23514';
  end if;


  -- Existing assignment data on a READY_FOR_REVIEW Lead
  -- is treated as an integrity conflict.
  if v_before.assigned_sales_user_id is not null
     or v_before.assigned_by_user_id is not null
     or v_before.assigned_at is not null then

    raise exception
      'Lead % already contains assignment data',
      p_lead_id
      using errcode = '23514';

  end if;


  -- ---------------------------------------------------------
  -- Validate Dispatcher
  -- ---------------------------------------------------------

  select *
  into v_dispatcher
  from public.b2c_staff_users
  where id = p_dispatcher_user_id;

  if not found then
    raise exception
      'Dispatcher user % not found',
      p_dispatcher_user_id;
  end if;

  if v_dispatcher.active is not true
     or v_dispatcher.workflow_role <> 'DISPATCHER' then

    raise exception
      'Staff user % is not an active DISPATCHER',
      p_dispatcher_user_id
      using errcode = '23514';

  end if;


  -- ---------------------------------------------------------
  -- Validate Sales owner
  -- ---------------------------------------------------------

  select *
  into v_sales
  from public.b2c_staff_users
  where id = p_sales_user_id;

  if not found then
    raise exception
      'Sales user % not found',
      p_sales_user_id;
  end if;

  if v_sales.active is not true
     or v_sales.workflow_role <> 'SALES' then

    raise exception
      'Staff user % is not an active SALES user',
      p_sales_user_id
      using errcode = '23514';

  end if;


  -- ---------------------------------------------------------
  -- Atomic assignment
  -- ---------------------------------------------------------

  update public.b2c_leads
  set
    assigned_sales_user_id = v_sales.id,
    assigned_by_user_id = v_dispatcher.id,
    assigned_at = now(),
    status = 'ASSIGNED'
  where id = v_before.id
    and status = 'READY_FOR_REVIEW'
  returning *
  into v_after;

  if not found then
    raise exception
      'Unable to assign Lead %',
      p_lead_id;
  end if;


  -- ---------------------------------------------------------
  -- Audit
  -- ---------------------------------------------------------

  insert into public.b2c_lead_events (
    lead_id,
    event_type,
    actor_type,
    actor_user_id,
    source_message_id,
    before_data,
    after_data,
    metadata
  )
  values (
    v_after.id,
    'LEAD_ASSIGNED',
    'DISPATCHER',
    v_dispatcher.id,
    null,

    jsonb_build_object(
      'status', v_before.status,
      'assigned_sales_user_id', v_before.assigned_sales_user_id,
      'assigned_by_user_id', v_before.assigned_by_user_id,
      'assigned_at', v_before.assigned_at
    ),

    jsonb_build_object(
      'status', v_after.status,
      'assigned_sales_user_id', v_after.assigned_sales_user_id,
      'assigned_by_user_id', v_after.assigned_by_user_id,
      'assigned_at', v_after.assigned_at
    ),

    jsonb_build_object(
      'source', 'DISPATCHER_ASSIGNMENT_RPC'
    )
  )
  returning id
  into v_event_id;


  -- ---------------------------------------------------------
  -- Return final state
  -- ---------------------------------------------------------

  return query
  select
    v_after.id,
    v_after.lead_no,
    v_after.status,
    v_after.assigned_sales_user_id,
    v_after.assigned_by_user_id,
    v_after.assigned_at,
    v_event_id;

end;
$$;


ALTER FUNCTION "public"."b2c_assign_ready_lead"("p_lead_id" "uuid", "p_dispatcher_user_id" "uuid", "p_sales_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_assign_ready_lead_as_current_dispatcher"("p_lead_id" "uuid", "p_sales_user_id" "uuid") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "lead_status" "text", "assigned_sales_user_id" "uuid", "assigned_by_user_id" "uuid", "assigned_at" timestamp with time zone, "event_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_dispatcher_user_id uuid;
begin

  -- ---------------------------------------------------------
  -- Resolve the logged-in staff member from JWT identity.
  -- Caller does NOT provide dispatcher_user_id.
  -- ---------------------------------------------------------

  select s.id
  into v_dispatcher_user_id
  from public.b2c_staff_users s
  where s.auth_user_id = auth.uid()
    and s.active is true
    and s.workflow_role = 'DISPATCHER'
  limit 1;


  if v_dispatcher_user_id is null then
    raise exception
      'Current authenticated user is not an active DISPATCHER'
      using errcode = '42501';
  end if;


  -- ---------------------------------------------------------
  -- Delegate the actual atomic assignment + audit logic
  -- to the already tested internal RPC.
  -- ---------------------------------------------------------

  return query
  select *
  from public.b2c_assign_ready_lead(
    p_lead_id,
    v_dispatcher_user_id,
    p_sales_user_id
  );

end;
$$;


ALTER FUNCTION "public"."b2c_assign_ready_lead_as_current_dispatcher"("p_lead_id" "uuid", "p_sales_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_active_lead_context"("p_woztell_member_id" "text") RETURNS TABLE("lead_context" "jsonb")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_active_count integer;
begin

  if nullif(btrim(p_woztell_member_id), '') is null then
    raise exception 'woztell_member_id is required'
      using errcode = '22023';
  end if;


  select count(*)::integer
  into v_active_count
  from public.b2c_leads l
  where l.woztell_member_id = p_woztell_member_id
    and l.status not in ('CLOSED_WON', 'CLOSED_LOST');


  if v_active_count = 0 then

    return query
    select '{}'::jsonb;

    return;

  end if;


  if v_active_count > 1 then
    raise exception
      'Ambiguous active lead context for member %: % active leads',
      p_woztell_member_id,
      v_active_count
      using errcode = 'P0001';
  end if;


  return query
  select to_jsonb(l)
  from public.b2c_leads l
  where l.woztell_member_id = p_woztell_member_id
    and l.status not in ('CLOSED_WON', 'CLOSED_LOST')
  order by l.created_at desc
  limit 1;

end;
$$;


ALTER FUNCTION "public"."b2c_get_active_lead_context"("p_woztell_member_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_active_sales_users"() RETURNS TABLE("staff_user_id" "uuid", "display_name" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$

  select
    s.id,
    s.display_name
  from public.b2c_staff_users s
  where s.workflow_role = 'SALES'
    and s.active is true
  order by s.display_name;

$$;


ALTER FUNCTION "public"."b2c_get_active_sales_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_active_sales_users_as_current_dispatcher"() RETURNS TABLE("staff_user_id" "uuid", "display_name" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_dispatcher_user_id uuid;
begin

  -- Resolve caller from authenticated JWT.
  select s.id
  into v_dispatcher_user_id
  from public.b2c_staff_users s
  where s.auth_user_id = auth.uid()
    and s.active is true
    and s.workflow_role = 'DISPATCHER'
  limit 1;

  if v_dispatcher_user_id is null then
    raise exception
      'Current authenticated user is not an active DISPATCHER'
      using errcode = '42501';
  end if;

  -- Reuse already-tested active SALES lookup.
  return query
  select *
  from public.b2c_get_active_sales_users();

end;
$$;


ALTER FUNCTION "public"."b2c_get_active_sales_users_as_current_dispatcher"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_current_staff_context"() RETURNS TABLE("staff_user_id" "uuid", "display_name" "text", "workflow_role" "text", "active" boolean)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$

  select
    s.id,
    s.display_name,
    s.workflow_role,
    s.active

  from public.b2c_staff_users s

  where s.auth_user_id = auth.uid()
    and s.active is true

  limit 1;

$$;


ALTER FUNCTION "public"."b2c_get_current_staff_context"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_dispatcher_lead_detail"("p_lead_id" "uuid") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "status" "text", "whatsapp_number" "text", "customer_name" "text", "service_user" "text", "district" "text", "service_category" "text", "customer_relationship" "text", "conversation_purpose" "text", "buying_intent" "text", "main_requirements" "text"[], "schedule_preferences" "text"[], "preferred_start_date" "date", "preferred_start_date_raw" "text", "preferred_time" "text", "frequency" "text", "service_duration" "text", "service_details" "jsonb", "company_follow_up_appointment" "jsonb", "medical_appointment" "jsonb", "ccsv_related" boolean, "ccsv_status" "text", "ai_summary" "text", "missing_information" "text"[], "human_follow_up_required" boolean, "next_action" "text", "next_follow_up_at" timestamp with time zone, "last_customer_message_at" timestamp with time zone, "last_company_contact_at" timestamp with time zone, "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$

  select
    l.id,
    l.lead_no,
    l.status,
    l.whatsapp_number,

    l.customer_name,
    l.service_user,
    l.district,
    l.service_category,
    l.customer_relationship,
    l.conversation_purpose,
    l.buying_intent,

    l.main_requirements,
    l.schedule_preferences,
    l.preferred_start_date,
    l.preferred_start_date_raw,
    l.preferred_time,
    l.frequency,
    l.service_duration,
    l.service_details,

    l.company_follow_up_appointment,
    l.medical_appointment,

    l.ccsv_related,
    l.ccsv_status,

    l.ai_summary,
    l.missing_information,
    l.human_follow_up_required,

    l.next_action,
    l.next_follow_up_at,

    l.last_customer_message_at,
    l.last_company_contact_at,
    l.created_at,
    l.updated_at

  from public.b2c_leads l

  where l.id = p_lead_id

    -- Dispatcher Review Detail is deliberately narrow.
    and l.status = 'READY_FOR_REVIEW'

    -- Fail closed if assignment state is inconsistent.
    and l.assigned_sales_user_id is null
    and l.assigned_by_user_id is null
    and l.assigned_at is null;

$$;


ALTER FUNCTION "public"."b2c_get_dispatcher_lead_detail"("p_lead_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_dispatcher_lead_detail_as_current_dispatcher"("p_lead_id" "uuid") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "status" "text", "whatsapp_number" "text", "customer_name" "text", "service_user" "text", "district" "text", "service_category" "text", "customer_relationship" "text", "conversation_purpose" "text", "buying_intent" "text", "main_requirements" "text"[], "schedule_preferences" "text"[], "preferred_start_date" "date", "preferred_start_date_raw" "text", "preferred_time" "text", "frequency" "text", "service_duration" "text", "service_details" "jsonb", "company_follow_up_appointment" "jsonb", "medical_appointment" "jsonb", "ccsv_related" boolean, "ccsv_status" "text", "ai_summary" "text", "missing_information" "text"[], "human_follow_up_required" boolean, "next_action" "text", "next_follow_up_at" timestamp with time zone, "last_customer_message_at" timestamp with time zone, "last_company_contact_at" timestamp with time zone, "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_dispatcher_user_id uuid;
begin

  -- Resolve caller from authenticated JWT.
  select s.id
  into v_dispatcher_user_id
  from public.b2c_staff_users s
  where s.auth_user_id = auth.uid()
    and s.active is true
    and s.workflow_role = 'DISPATCHER'
  limit 1;

  if v_dispatcher_user_id is null then
    raise exception
      'Current authenticated user is not an active DISPATCHER'
      using errcode = '42501';
  end if;

  -- Reuse the already-tested Detail logic.
  return query
  select *
  from public.b2c_get_dispatcher_lead_detail(p_lead_id);

end;
$$;


ALTER FUNCTION "public"."b2c_get_dispatcher_lead_detail_as_current_dispatcher"("p_lead_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_dispatcher_review_queue"() RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "status" "text", "customer_name" "text", "service_user" "text", "service_category" "text", "district" "text", "ai_summary" "text", "human_follow_up_required" boolean, "missing_information" "text"[], "last_customer_message_at" timestamp with time zone, "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$

  select
    l.id,
    l.lead_no,
    l.status,
    l.customer_name,
    l.service_user,
    l.service_category,
    l.district,
    l.ai_summary,
    l.human_follow_up_required,
    l.missing_information,
    l.last_customer_message_at,
    l.created_at,
    l.updated_at

  from public.b2c_leads l

  where l.status = 'READY_FOR_REVIEW'

    -- Fail closed if inconsistent assignment data somehow exists.
    and l.assigned_sales_user_id is null
    and l.assigned_by_user_id is null
    and l.assigned_at is null

  order by
    l.human_follow_up_required desc,
    l.last_customer_message_at asc nulls first,
    l.created_at asc;

$$;


ALTER FUNCTION "public"."b2c_get_dispatcher_review_queue"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_dispatcher_review_queue_as_current_dispatcher"() RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "status" "text", "customer_name" "text", "service_user" "text", "service_category" "text", "district" "text", "ai_summary" "text", "human_follow_up_required" boolean, "missing_information" "text"[], "last_customer_message_at" timestamp with time zone, "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_dispatcher_user_id uuid;
begin

  -- Resolve caller from authenticated JWT.
  select s.id
  into v_dispatcher_user_id
  from public.b2c_staff_users s
  where s.auth_user_id = auth.uid()
    and s.active is true
    and s.workflow_role = 'DISPATCHER'
  limit 1;

  if v_dispatcher_user_id is null then
    raise exception
      'Current authenticated user is not an active DISPATCHER'
      using errcode = '42501';
  end if;

  -- Reuse the already-tested queue logic.
  return query
  select *
  from public.b2c_get_dispatcher_review_queue();

end;
$$;


ALTER FUNCTION "public"."b2c_get_dispatcher_review_queue_as_current_dispatcher"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_or_create_active_lead"("p_woztell_member_id" "text", "p_woztell_channel_id" "text" DEFAULT NULL::"text", "p_whatsapp_number" "text" DEFAULT NULL::"text") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "was_created" boolean, "lead_status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
begin

  return query
  select
    r.lead_id,
    r.lead_no,
    r.was_created,
    r.lead_status
  from public.b2c_get_or_create_active_lead_v2(
    p_woztell_member_id,
    p_woztell_channel_id,
    p_whatsapp_number,
    null
  ) r;

end;
$$;


ALTER FUNCTION "public"."b2c_get_or_create_active_lead"("p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_whatsapp_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_get_or_create_active_lead_v2"("p_woztell_member_id" "text", "p_woztell_channel_id" "text" DEFAULT NULL::"text", "p_whatsapp_number" "text" DEFAULT NULL::"text", "p_service_category" "text" DEFAULT NULL::"text") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "was_created" boolean, "lead_status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_lead public.b2c_leads%rowtype;
  v_category text;
  v_active_count integer;
begin

  if nullif(btrim(p_woztell_member_id), '') is null then
    raise exception 'woztell_member_id is required'
      using errcode = '22023';
  end if;


  -- Canonical uncategorized value is 'unknown'.
  v_category :=
    coalesce(
      lower(
        nullif(
          btrim(p_service_category),
          ''
        )
      ),
      'unknown'
    );


  -- Serialize routing for same member.
  perform pg_advisory_xact_lock(
    hashtextextended(p_woztell_member_id, 0)
  );


  -- ========================================================
  -- KNOWN SERVICE CATEGORY
  -- ========================================================

  if v_category <> 'unknown' then

    -- Reuse same member + same service.
    select l.*
    into v_lead
    from public.b2c_leads l
    where l.woztell_member_id = p_woztell_member_id
      and lower(btrim(l.service_category)) = v_category
      and l.status not in ('CLOSED_WON', 'CLOSED_LOST')
    order by l.created_at desc
    limit 1;

    if found then
      return query
      select
        v_lead.id,
        v_lead.lead_no,
        false,
        v_lead.status;

      return;
    end if;


    -- If exactly one active lead exists and it is still unknown,
    -- promote that lead into the known service category.
    select count(*)::integer
    into v_active_count
    from public.b2c_leads l
    where l.woztell_member_id = p_woztell_member_id
      and l.status not in ('CLOSED_WON', 'CLOSED_LOST');


    if v_active_count = 1 then

      select l.*
      into v_lead
      from public.b2c_leads l
      where l.woztell_member_id = p_woztell_member_id
        and l.status not in ('CLOSED_WON', 'CLOSED_LOST')
      limit 1;

      if lower(btrim(v_lead.service_category)) = 'unknown' then

        update public.b2c_leads l
        set service_category = v_category
        where l.id = v_lead.id
          and lower(btrim(l.service_category)) = 'unknown'
        returning l.*
        into v_lead;

        if found then
          return query
          select
            v_lead.id,
            v_lead.lead_no,
            false,
            v_lead.status;

          return;
        end if;

      end if;

    end if;


    -- Different known service → create separate lead.
    insert into public.b2c_leads (
      woztell_member_id,
      woztell_channel_id,
      whatsapp_number,
      service_category,
      status
    )
    values (
      p_woztell_member_id,
      p_woztell_channel_id,
      p_whatsapp_number,
      v_category,
      'NEW'
    )
    on conflict (
      woztell_member_id,
      service_category
    )
    where status not in ('CLOSED_WON', 'CLOSED_LOST')
      and service_category is not null
    do nothing
    returning *
    into v_lead;


    if found then
      return query
      select
        v_lead.id,
        v_lead.lead_no,
        true,
        v_lead.status;

      return;
    end if;


    -- Defensive fallback.
    select l.*
    into v_lead
    from public.b2c_leads l
    where l.woztell_member_id = p_woztell_member_id
      and lower(btrim(l.service_category)) = v_category
      and l.status not in ('CLOSED_WON', 'CLOSED_LOST')
    order by l.created_at desc
    limit 1;

    if not found then
      raise exception
        'Unable to resolve active lead for member % and service %',
        p_woztell_member_id,
        v_category;
    end if;


    return query
    select
      v_lead.id,
      v_lead.lead_no,
      false,
      v_lead.status;

    return;

  end if;


  -- ========================================================
  -- UNKNOWN / UNCATEGORIZED MESSAGE
  -- ========================================================

  select count(*)::integer
  into v_active_count
  from public.b2c_leads l
  where l.woztell_member_id = p_woztell_member_id
    and l.status not in ('CLOSED_WON', 'CLOSED_LOST');


  -- No active lead → create canonical unknown lead.
  if v_active_count = 0 then

    insert into public.b2c_leads (
      woztell_member_id,
      woztell_channel_id,
      whatsapp_number,
      service_category,
      status
    )
    values (
      p_woztell_member_id,
      p_woztell_channel_id,
      p_whatsapp_number,
      'unknown',
      'NEW'
    )
    on conflict (woztell_member_id)
    where status not in ('CLOSED_WON', 'CLOSED_LOST')
      and lower(btrim(service_category)) = 'unknown'
    do nothing
    returning *
    into v_lead;


    if found then
      return query
      select
        v_lead.id,
        v_lead.lead_no,
        true,
        v_lead.status;

      return;
    end if;


    select l.*
    into v_lead
    from public.b2c_leads l
    where l.woztell_member_id = p_woztell_member_id
      and lower(btrim(l.service_category)) = 'unknown'
      and l.status not in ('CLOSED_WON', 'CLOSED_LOST')
    order by l.created_at desc
    limit 1;


    if not found then
      raise exception
        'Unable to create unknown lead for member %',
        p_woztell_member_id;
    end if;


    return query
    select
      v_lead.id,
      v_lead.lead_no,
      false,
      v_lead.status;

    return;

  end if;


  -- Exactly one active lead → safe continuation.
  if v_active_count = 1 then

    select l.*
    into v_lead
    from public.b2c_leads l
    where l.woztell_member_id = p_woztell_member_id
      and l.status not in ('CLOSED_WON', 'CLOSED_LOST')
    order by l.created_at desc
    limit 1;


    return query
    select
      v_lead.id,
      v_lead.lead_no,
      false,
      v_lead.status;

    return;

  end if;


  -- Multiple active leads + unknown service → fail closed.
  raise exception
    'Ambiguous active lead: member % has % active leads and service category is unknown',
    p_woztell_member_id,
    v_active_count
    using errcode = 'P0001';

end;
$$;


ALTER FUNCTION "public"."b2c_get_or_create_active_lead_v2"("p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_whatsapp_number" "text", "p_service_category" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_next_lead_no"() RETURNS "text"
    LANGUAGE "sql"
    AS $$
  select
    'B2C-' ||
    to_char(
      now() at time zone 'Asia/Hong_Kong',
      'YYYYMMDD'
    ) ||
    '-' ||
    lpad(
      nextval('public.b2c_lead_no_seq')::text,
      6,
      '0'
    );
$$;


ALTER FUNCTION "public"."b2c_next_lead_no"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."b2c_leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_no" "text" DEFAULT "public"."b2c_next_lead_no"() NOT NULL,
    "woztell_member_id" "text" NOT NULL,
    "woztell_channel_id" "text",
    "whatsapp_number" "text",
    "customer_name" "text",
    "service_user" "text",
    "district" "text",
    "service_category" "text" DEFAULT 'unknown'::"text" NOT NULL,
    "customer_relationship" "text" DEFAULT 'unknown'::"text" NOT NULL,
    "conversation_purpose" "text" DEFAULT 'unknown'::"text" NOT NULL,
    "buying_intent" "text" DEFAULT 'unknown'::"text" NOT NULL,
    "main_requirements" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "schedule_preferences" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "preferred_start_date" "date",
    "preferred_start_date_raw" "text",
    "preferred_time" "text",
    "frequency" "text",
    "service_duration" "text",
    "service_details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "company_follow_up_appointment" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "medical_appointment" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "ccsv_related" boolean,
    "ccsv_status" "text",
    "ai_summary" "text",
    "missing_information" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "human_follow_up_required" boolean DEFAULT false NOT NULL,
    "extractor_version" "text",
    "status" "text" DEFAULT 'NEW'::"text" NOT NULL,
    "assigned_sales_user_id" "uuid",
    "assigned_by_user_id" "uuid",
    "assigned_at" timestamp with time zone,
    "last_customer_message_at" timestamp with time zone,
    "last_company_contact_at" timestamp with time zone,
    "next_action" "text",
    "next_follow_up_at" timestamp with time zone,
    "last_processed_message_id" "text",
    "closed_at" timestamp with time zone,
    "closed_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "b2c_leads_buying_intent_check" CHECK (("buying_intent" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text", 'unknown'::"text"]))),
    CONSTRAINT "b2c_leads_customer_relationship_check" CHECK (("customer_relationship" = ANY (ARRAY['new_prospect'::"text", 'existing_customer'::"text", 'former_customer'::"text", 'unknown'::"text"]))),
    CONSTRAINT "b2c_leads_service_category_check" CHECK (("service_category" = ANY (ARRAY['meal_delivery'::"text", 'home_cleaning'::"text", 'home_care'::"text", 'wound_care'::"text", 'physiotherapy'::"text", 'medical_escort'::"text", 'ccsv'::"text", 'elderly_support'::"text", 'other'::"text", 'unknown'::"text"]))),
    CONSTRAINT "b2c_leads_status_check" CHECK (("status" = ANY (ARRAY['NEW'::"text", 'AI_COLLECTING'::"text", 'READY_FOR_REVIEW'::"text", 'ASSIGNED'::"text", 'SALES_FOLLOWING_UP'::"text", 'WAITING_CUSTOMER'::"text", 'CLOSED_WON'::"text", 'CLOSED_LOST'::"text"])))
);


ALTER TABLE "public"."b2c_leads" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_is_lead_ready_for_review"("p_lead" "public"."b2c_leads") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$

  select
    coalesce(p_lead.human_follow_up_required, false)

    or (

      -- -----------------------------------------------------
      -- 1. Known service category
      -- -----------------------------------------------------
      lower(
        btrim(
          coalesce(p_lead.service_category, '')
        )
      ) not in (
        '',
        'unknown',
        'null',
        'n/a',
        'not provided'
      )

      and

      -- -----------------------------------------------------
      -- 2. Customer name known
      -- -----------------------------------------------------
      lower(
        btrim(
          coalesce(p_lead.customer_name, '')
        )
      ) not in (
        '',
        'unknown',
        'null',
        'n/a',
        'not provided'
      )

      and

      -- -----------------------------------------------------
      -- 3. Location known
      -- -----------------------------------------------------
      (
        lower(
          btrim(
            coalesce(p_lead.district, '')
          )
        ) not in (
          '',
          'unknown',
          'null',
          'n/a',
          'not provided'
        )

        or

        lower(
          btrim(
            coalesce(
              p_lead.service_details->>'pickup_district',
              ''
            )
          )
        ) not in (
          '',
          'unknown',
          'null',
          'n/a',
          'not provided'
        )

        or

        lower(
          btrim(
            coalesce(
              p_lead.service_details->>'pickup_location',
              ''
            )
          )
        ) not in (
          '',
          'unknown',
          'null',
          'n/a',
          'not provided'
        )
      )

      and

      -- -----------------------------------------------------
      -- 4. At least one timing / schedule signal
      -- -----------------------------------------------------
      (
        p_lead.preferred_start_date is not null

        or

        lower(
          btrim(
            coalesce(p_lead.preferred_time, '')
          )
        ) not in (
          '',
          'unknown',
          'null',
          'n/a',
          'not provided'
        )

        or

        lower(
          btrim(
            coalesce(p_lead.frequency, '')
          )
        ) not in (
          '',
          'unknown',
          'null',
          'n/a',
          'not provided'
        )

        or

        coalesce(
          cardinality(p_lead.schedule_preferences),
          0
        ) > 0

        or

        case
          when jsonb_typeof(
            p_lead.service_details->'delivery_days'
          ) = 'array'
          then jsonb_array_length(
            p_lead.service_details->'delivery_days'
          ) > 0
          else false
        end

        or

        case
          when jsonb_typeof(
            p_lead.service_details->'meal_periods'
          ) = 'array'
          then jsonb_array_length(
            p_lead.service_details->'meal_periods'
          ) > 0
          else false
        end

        or

        case
          when jsonb_typeof(
            p_lead.service_details->'service_days'
          ) = 'array'
          then jsonb_array_length(
            p_lead.service_details->'service_days'
          ) > 0
          else false
        end

        or

        case
          when jsonb_typeof(
            p_lead.service_details->'time_periods'
          ) = 'array'
          then jsonb_array_length(
            p_lead.service_details->'time_periods'
          ) > 0
          else false
        end

        or

        lower(
          btrim(
            coalesce(
              p_lead.medical_appointment->>'date',
              ''
            )
          )
        ) not in (
          '',
          'unknown',
          'null',
          'n/a',
          'not provided'
        )

        or

        lower(
          btrim(
            coalesce(
              p_lead.medical_appointment->>'time',
              ''
            )
          )
        ) not in (
          '',
          'unknown',
          'null',
          'n/a',
          'not provided'
        )
      )
    );

$$;


ALTER FUNCTION "public"."b2c_is_lead_ready_for_review"("p_lead" "public"."b2c_leads") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_list_active_lead_contexts"("p_woztell_member_id" "text") RETURNS TABLE("active_leads" "jsonb")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_active_leads jsonb;
begin

  if nullif(btrim(p_woztell_member_id), '') is null then
    raise exception 'woztell_member_id is required'
      using errcode = '22023';
  end if;


  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'lead_id', l.id,
        'lead_no', l.lead_no,
        'status', l.status,

        'service_category', l.service_category,
        'customer_name', l.customer_name,
        'service_user', l.service_user,
        'district', l.district,
        'customer_relationship', l.customer_relationship,
        'conversation_purpose', l.conversation_purpose,

        'buying_intent', l.buying_intent,
        'main_requirements', to_jsonb(l.main_requirements),
        'schedule_preferences', to_jsonb(l.schedule_preferences),

        'preferred_start_date', l.preferred_start_date,
        'preferred_start_date_raw', l.preferred_start_date_raw,
        'preferred_time', l.preferred_time,

        'frequency', l.frequency,
        'service_duration', l.service_duration,

        'service_details', l.service_details,

        'ccsv_related', l.ccsv_related,
        'ccsv_status', l.ccsv_status,

        'medical_appointment', l.medical_appointment,
        'company_follow_up_appointment',
          l.company_follow_up_appointment,

        'missing_information',
          to_jsonb(l.missing_information),

        'human_follow_up_required',
          l.human_follow_up_required,

        'ai_summary', l.ai_summary,

        'last_customer_message_at',
          l.last_customer_message_at,

        'updated_at', l.updated_at
      )
      order by l.updated_at desc, l.created_at desc
    ),
    '[]'::jsonb
  )
  into v_active_leads
  from public.b2c_leads l
  where l.woztell_member_id = p_woztell_member_id
    and l.status not in ('CLOSED_WON', 'CLOSED_LOST');


  return query
  select v_active_leads;

end;
$$;


ALTER FUNCTION "public"."b2c_list_active_lead_contexts"("p_woztell_member_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_mark_inbound_message_failed"("p_message_id" "text", "p_error" "text", "p_lead_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("message_id" "text", "processing_status" "text", "lead_id" "uuid", "attempt_count" integer, "last_error" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_message public.b2c_inbound_messages%rowtype;
begin
  if nullif(btrim(p_message_id), '') is null then
    raise exception 'message_id is required'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_error), '') is null then
    raise exception 'error message is required'
      using errcode = '22023';
  end if;

  update public.b2c_inbound_messages
  set
    processing_status = 'FAILED',
    lead_id = coalesce(
      p_lead_id,
      b2c_inbound_messages.lead_id
    ),
    last_error = p_error,
    processed_at = null
  where b2c_inbound_messages.message_id = p_message_id
    and b2c_inbound_messages.processing_status = 'PROCESSING'
  returning *
  into v_message;

  if not found then
    raise exception
      'Message % is not in PROCESSING state',
      p_message_id;
  end if;

  return query
  select
    v_message.message_id,
    v_message.processing_status,
    v_message.lead_id,
    v_message.attempt_count,
    v_message.last_error;
end;
$$;


ALTER FUNCTION "public"."b2c_mark_inbound_message_failed"("p_message_id" "text", "p_error" "text", "p_lead_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_mark_inbound_message_processed"("p_message_id" "text", "p_lead_id" "uuid") RETURNS TABLE("message_id" "text", "processing_status" "text", "lead_id" "uuid", "processed_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_message public.b2c_inbound_messages%rowtype;
begin
  if nullif(btrim(p_message_id), '') is null then
    raise exception 'message_id is required'
      using errcode = '22023';
  end if;

  if p_lead_id is null then
    raise exception 'lead_id is required'
      using errcode = '22023';
  end if;

  update public.b2c_inbound_messages
  set
    processing_status = 'PROCESSED',
    lead_id = p_lead_id,
    processed_at = now(),
    last_error = null
  where b2c_inbound_messages.message_id = p_message_id
    and b2c_inbound_messages.processing_status = 'PROCESSING'
  returning *
  into v_message;

  if not found then
    raise exception
      'Message % is not in PROCESSING state',
      p_message_id;
  end if;

  return query
  select
    v_message.message_id,
    v_message.processing_status,
    v_message.lead_id,
    v_message.processed_at;
end;
$$;


ALTER FUNCTION "public"."b2c_mark_inbound_message_processed"("p_message_id" "text", "p_lead_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_meal_delivery_date_available"("p_date" "date") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select
    -- ISO weekday: Sunday = 7
    extract(isodow from p_date) <> 7

    and not exists (
      select 1
      from public.b2c_service_blackout_dates b
      where b.service_category = 'meal_delivery'
        and b.blackout_date = p_date
        and b.active = true
    );
$$;


ALTER FUNCTION "public"."b2c_meal_delivery_date_available"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_reserve_inbound_message"("p_message_id" "text", "p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_message_type" "text" DEFAULT NULL::"text", "p_event_type" "text" DEFAULT NULL::"text", "p_customer_message_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE("should_process" boolean, "current_status" "text", "attempt_count" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_message public.b2c_inbound_messages%rowtype;
begin
  -- Required identifiers must exist.
  if nullif(btrim(p_message_id), '') is null then
    raise exception 'message_id is required'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_woztell_member_id), '') is null then
    raise exception 'woztell_member_id is required'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_woztell_channel_id), '') is null then
    raise exception 'woztell_channel_id is required'
      using errcode = '22023';
  end if;

  -- First delivery:
  -- create the message directly in PROCESSING state.
  insert into public.b2c_inbound_messages (
    message_id,
    woztell_member_id,
    woztell_channel_id,
    message_type,
    event_type,
    customer_message_at,
    processing_status,
    attempt_count
  )
  values (
    p_message_id,
    p_woztell_member_id,
    p_woztell_channel_id,
    p_message_type,
    p_event_type,
    p_customer_message_at,
    'PROCESSING',
    1
  )
  on conflict (message_id)
  do nothing
  returning *
  into v_message;

  if found then
    return query
    select
      true,
      v_message.processing_status,
      v_message.attempt_count;

    return;
  end if;

  -- Existing FAILED message may be retried.
  update public.b2c_inbound_messages
  set
    processing_status = 'PROCESSING',
    attempt_count = b2c_inbound_messages.attempt_count + 1,
    last_error = null
  where message_id = p_message_id
    and processing_status = 'FAILED'
  returning *
  into v_message;

  if found then
    return query
    select
      true,
      v_message.processing_status,
      v_message.attempt_count;

    return;
  end if;

  -- Already PROCESSING / PROCESSED:
  -- do not process again.
  select *
  into v_message
  from public.b2c_inbound_messages
  where message_id = p_message_id;

  if not found then
    raise exception 'Unable to resolve inbound message %',
      p_message_id;
  end if;

  return query
  select
    false,
    v_message.processing_status,
    v_message.attempt_count;
end;
$$;


ALTER FUNCTION "public"."b2c_reserve_inbound_message"("p_message_id" "text", "p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_message_type" "text", "p_event_type" "text", "p_customer_message_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."b2c_set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_update_lead_from_ai"("p_lead_id" "uuid", "p_source_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_extractor_version" "text" DEFAULT NULL::"text") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "lead_status" "text", "event_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_existing_handoff boolean;
  v_existing_category text;
  v_existing_status text;
  v_existing_lead_no text;

  v_incoming_category text;
  v_safe_extraction jsonb;

  v_event_id uuid;
begin

  if p_lead_id is null then
    raise exception 'lead_id is required'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_source_message_id), '') is null then
    raise exception 'source_message_id is required'
      using errcode = '22023';
  end if;

  if p_extraction is null
     or jsonb_typeof(p_extraction) <> 'object' then
    raise exception 'p_extraction must be a JSON object'
      using errcode = '22023';
  end if;


  -- Lock the Lead and evaluate the CURRENT workflow state.
  select
    l.human_follow_up_required,
    lower(nullif(btrim(l.service_category), '')),
    l.status,
    l.lead_no
  into
    v_existing_handoff,
    v_existing_category,
    v_existing_status,
    v_existing_lead_no
  from public.b2c_leads l
  where l.id = p_lead_id
  for update;


  if not found then
    raise exception 'Lead % not found', p_lead_id;
  end if;


  -- =======================================================
  -- POST-HANDOFF INTEGRITY GUARD
  --
  -- AI may mutate Lead facts only while the Lead remains in
  -- the AI / Dispatcher intake stages.
  --
  -- Once ownership has moved beyond READY_FOR_REVIEW,
  -- customer/service facts are human-owned and immutable
  -- through this AI update path.
  --
  -- We still advance message receipt metadata so inbound
  -- processing remains traceable.
  -- =======================================================

  if v_existing_status not in (
    'NEW',
    'AI_COLLECTING',
    'READY_FOR_REVIEW'
  ) then

    update public.b2c_leads
    set
      last_customer_message_at =
        coalesce(
          p_customer_message_at,
          last_customer_message_at
        ),

      last_processed_message_id =
        p_source_message_id

    where id = p_lead_id;


    insert into public.b2c_lead_events (
      lead_id,
      event_type,
      actor_type,
      source_message_id,
      before_data,
      after_data,
      metadata
    )
    values (
      p_lead_id,
      'AI_UPDATE_SKIPPED',
      'AI',
      p_source_message_id,

      jsonb_build_object(
        'status', v_existing_status
      ),

      jsonb_build_object(
        'status', v_existing_status
      ),

      jsonb_build_object(
        'reason', 'HUMAN_OWNED_LEAD_STATE',
        'extractor_version', p_extractor_version
      )
    )
    on conflict do nothing
    returning id
    into v_event_id;


    -- Idempotent fallback if this message event already exists.
    if v_event_id is null then
      select e.id
      into v_event_id
      from public.b2c_lead_events e
      where e.event_type = 'AI_UPDATE_SKIPPED'
        and e.source_message_id = p_source_message_id
      limit 1;
    end if;


    return query
    select
      p_lead_id,
      v_existing_lead_no,
      v_existing_status,
      v_event_id;

    return;
  end if;


  -- =======================================================
  -- EXISTING PRE-HANDOFF AI LOGIC
  -- =======================================================

  v_incoming_category :=
    lower(
      nullif(
        btrim(p_extraction->>'service_category'),
        ''
      )
    );


  if v_incoming_category = 'unknown' then
    v_incoming_category := null;
  end if;


  -- Once a Lead has a known service category,
  -- AI cannot convert it into another service.
  if v_existing_category is not null
     and v_incoming_category is not null
     and v_existing_category <> v_incoming_category then

    raise exception
      'Service category mismatch for lead %: existing %, incoming %',
      p_lead_id,
      v_existing_category,
      v_incoming_category
      using errcode = '23514';

  end if;


  v_safe_extraction := p_extraction;


  -- Canonicalize incoming category.
  if v_incoming_category is not null then
    v_safe_extraction :=
      jsonb_set(
        v_safe_extraction,
        '{service_category}',
        to_jsonb(v_incoming_category),
        true
      );
  end if;


  -- AI may escalate false -> true,
  -- but may never downgrade true -> false.
  v_safe_extraction :=
    jsonb_set(
      v_safe_extraction,
      '{human_follow_up_required}',
      to_jsonb(
        public.b2c_ai_merge_human_follow_up(
          v_existing_handoff,
          v_safe_extraction
        )
      ),
      true
    );


  return query
  select *
  from public.b2c_update_lead_from_ai_v1_internal(
    p_lead_id,
    p_source_message_id,
    v_safe_extraction,
    p_customer_message_at,
    p_extractor_version
  );

end;
$$;


ALTER FUNCTION "public"."b2c_update_lead_from_ai"("p_lead_id" "uuid", "p_source_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone, "p_extractor_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."b2c_update_lead_from_ai_v1_internal"("p_lead_id" "uuid", "p_source_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_extractor_version" "text" DEFAULT NULL::"text") RETURNS TABLE("lead_id" "uuid", "lead_no" "text", "lead_status" "text", "event_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_before public.b2c_leads%rowtype;
  v_after public.b2c_leads%rowtype;
  v_event_id uuid;

  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
begin

  -- ---------------------------------------------------------
  -- Validation
  -- ---------------------------------------------------------

  if p_lead_id is null then
    raise exception 'lead_id is required'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_source_message_id), '') is null then
    raise exception 'source_message_id is required'
      using errcode = '22023';
  end if;

  if p_extraction is null
     or jsonb_typeof(p_extraction) <> 'object' then
    raise exception 'p_extraction must be a JSON object'
      using errcode = '22023';
  end if;


  -- ---------------------------------------------------------
  -- Lock lead
  -- ---------------------------------------------------------

  select *
  into v_before
  from public.b2c_leads
  where id = p_lead_id
  for update;

  if not found then
    raise exception 'Lead % not found', p_lead_id;
  end if;


  -- ---------------------------------------------------------
  -- Selected BEFORE snapshot
  -- Avoid duplicating unnecessary PII into audit table.
  -- ---------------------------------------------------------

  v_before_snapshot := jsonb_build_object(
    'service_category', v_before.service_category,
    'customer_name', v_before.customer_name,
    'service_user', v_before.service_user,
    'district', v_before.district,
    'customer_relationship', v_before.customer_relationship,
    'conversation_purpose', v_before.conversation_purpose,
    'buying_intent', v_before.buying_intent,
    'main_requirements', to_jsonb(v_before.main_requirements),
    'schedule_preferences', to_jsonb(v_before.schedule_preferences),
    'preferred_start_date', v_before.preferred_start_date,
    'preferred_start_date_raw', v_before.preferred_start_date_raw,
    'preferred_time', v_before.preferred_time,
    'frequency', v_before.frequency,
    'service_duration', v_before.service_duration,
    'ccsv_related', v_before.ccsv_related,
    'ccsv_status', v_before.ccsv_status,
    'medical_appointment', v_before.medical_appointment,
    'company_follow_up_appointment', v_before.company_follow_up_appointment,
    'ai_summary', v_before.ai_summary,
    'missing_information', to_jsonb(v_before.missing_information),
    'human_follow_up_required', v_before.human_follow_up_required,
    'status', v_before.status
  );


  -- ---------------------------------------------------------
  -- Update ONLY AI-owned / extracted fields.
  --
  -- Null / unknown values do not erase previously known facts.
  -- Human ownership / follow-up fields are untouched.
  -- ---------------------------------------------------------

  update public.b2c_leads
  set

    customer_name =
      case
        when nullif(btrim(p_extraction->>'customer_name'), '') is not null
        then p_extraction->>'customer_name'
        else customer_name
      end,

    service_user =
      case
        when nullif(btrim(p_extraction->>'service_user'), '') is not null
        then p_extraction->>'service_user'
        else service_user
      end,

    district =
      case
        when nullif(btrim(p_extraction->>'district'), '') is not null
        then p_extraction->>'district'
        else district
      end,

    service_category =
      case
        when nullif(btrim(p_extraction->>'service_category'), '') is not null
          and p_extraction->>'service_category' <> 'unknown'
        then p_extraction->>'service_category'
        else service_category
      end,

    customer_relationship =
      case
        when nullif(
          btrim(p_extraction->>'customer_relationship'),
          ''
        ) is not null
          and p_extraction->>'customer_relationship' <> 'unknown'
        then p_extraction->>'customer_relationship'
        else customer_relationship
      end,

    conversation_purpose =
      case
        when nullif(
          btrim(p_extraction->>'conversation_purpose'),
          ''
        ) is not null
          and p_extraction->>'conversation_purpose' <> 'unknown'
        then p_extraction->>'conversation_purpose'
        else conversation_purpose
      end,

    buying_intent =
      case
        when nullif(btrim(p_extraction->>'buying_intent'), '') is not null
          and p_extraction->>'buying_intent' <> 'unknown'
        then p_extraction->>'buying_intent'
        else buying_intent
      end,

    main_requirements =
      case
        when jsonb_typeof(p_extraction->'main_requirements') = 'array'
          and jsonb_array_length(
            p_extraction->'main_requirements'
          ) > 0
        then array(
          select jsonb_array_elements_text(
            p_extraction->'main_requirements'
          )
        )
        else main_requirements
      end,

    schedule_preferences =
      case
        when jsonb_typeof(
          p_extraction->'schedule_preferences'
        ) = 'array'
          and jsonb_array_length(
            p_extraction->'schedule_preferences'
          ) > 0
        then array(
          select jsonb_array_elements_text(
            p_extraction->'schedule_preferences'
          )
        )
        else schedule_preferences
      end,

    preferred_start_date =
      case
        when nullif(
          btrim(p_extraction->>'preferred_start_date'),
          ''
        ) is not null
        then (p_extraction->>'preferred_start_date')::date
        else preferred_start_date
      end,

    preferred_start_date_raw =
      case
        when nullif(
          btrim(p_extraction->>'preferred_start_date_raw'),
          ''
        ) is not null
        then p_extraction->>'preferred_start_date_raw'
        else preferred_start_date_raw
      end,

    preferred_time =
      case
        when nullif(btrim(p_extraction->>'preferred_time'), '') is not null
        then p_extraction->>'preferred_time'
        else preferred_time
      end,

    frequency =
      case
        when nullif(btrim(p_extraction->>'frequency'), '') is not null
        then p_extraction->>'frequency'
        else frequency
      end,

    service_duration =
      case
        when nullif(
          btrim(p_extraction->>'service_duration'),
          ''
        ) is not null
        then p_extraction->>'service_duration'
        else service_duration
      end,

    ccsv_related =
      case
        when p_extraction ? 'ccsv_related'
          and p_extraction->'ccsv_related' <> 'null'::jsonb
        then (p_extraction->>'ccsv_related')::boolean
        else ccsv_related
      end,

    ccsv_status =
      case
        when nullif(btrim(p_extraction->>'ccsv_status'), '') is not null
        then p_extraction->>'ccsv_status'
        else ccsv_status
      end,

    medical_appointment =
      case
        when jsonb_typeof(
          p_extraction->'medical_appointment'
        ) = 'object'
        then
          medical_appointment
          ||
          jsonb_strip_nulls(
            p_extraction->'medical_appointment'
          )
        else medical_appointment
      end,

    company_follow_up_appointment =
      case
        when jsonb_typeof(
          p_extraction->'follow_up_appointment'
        ) = 'object'
        then
          company_follow_up_appointment
          ||
          jsonb_strip_nulls(
            p_extraction->'follow_up_appointment'
          )
        else company_follow_up_appointment
      end,

    service_details =
      case
        when jsonb_typeof(
          p_extraction->'service_details'
        ) = 'object'
        then
          service_details
          ||
          jsonb_strip_nulls(
            p_extraction->'service_details'
          )
        else service_details
      end,

    ai_summary =
      case
        when nullif(btrim(p_extraction->>'summary'), '') is not null
        then p_extraction->>'summary'
        else ai_summary
      end,

    -- missing_information may legitimately become empty.
    missing_information =
      case
        when jsonb_typeof(
          p_extraction->'missing_information'
        ) = 'array'
        then array(
          select jsonb_array_elements_text(
            p_extraction->'missing_information'
          )
        )
        else missing_information
      end,

    human_follow_up_required =
      case
        when p_extraction ? 'human_follow_up_required'
          and p_extraction->'human_follow_up_required'
              <> 'null'::jsonb
        then (
          p_extraction->>'human_follow_up_required'
        )::boolean
        else human_follow_up_required
      end,

    extractor_version =
      coalesce(
        nullif(btrim(p_extractor_version), ''),
        extractor_version
      ),

    last_customer_message_at =
      coalesce(
        p_customer_message_at,
        last_customer_message_at
      ),

    last_processed_message_id =
      p_source_message_id,

    -- AI initially moves a brand-new lead into collection.
    status =
      case
        when status = 'NEW'
        then 'AI_COLLECTING'
        else status
      end

  where id = p_lead_id

  returning *
  into v_after;


  -- ---------------------------------------------------------
  -- Readiness transition
  --
  -- IMPORTANT:
  -- Evaluate the MERGED lead state, not the current message
  -- extraction alone.
  --
  -- AI may promote only:
  -- AI_COLLECTING -> READY_FOR_REVIEW
  --
  -- Eva / Sales workflow states are never overwritten here.
  -- ---------------------------------------------------------

  if v_after.status = 'AI_COLLECTING'
     and public.b2c_is_lead_ready_for_review(v_after) then

    update public.b2c_leads
    set status = 'READY_FOR_REVIEW'
    where id = p_lead_id
      and status = 'AI_COLLECTING'
    returning *
    into v_after;

  end if;


  -- ---------------------------------------------------------
  -- Selected AFTER snapshot
  -- ---------------------------------------------------------

  v_after_snapshot := jsonb_build_object(
    'service_category', v_after.service_category,
    'customer_name', v_after.customer_name,
    'service_user', v_after.service_user,
    'district', v_after.district,
    'customer_relationship', v_after.customer_relationship,
    'conversation_purpose', v_after.conversation_purpose,
    'buying_intent', v_after.buying_intent,
    'main_requirements', to_jsonb(v_after.main_requirements),
    'schedule_preferences', to_jsonb(v_after.schedule_preferences),
    'preferred_start_date', v_after.preferred_start_date,
    'preferred_start_date_raw', v_after.preferred_start_date_raw,
    'preferred_time', v_after.preferred_time,
    'frequency', v_after.frequency,
    'service_duration', v_after.service_duration,
    'ccsv_related', v_after.ccsv_related,
    'ccsv_status', v_after.ccsv_status,
    'medical_appointment', v_after.medical_appointment,
    'company_follow_up_appointment', v_after.company_follow_up_appointment,
    'ai_summary', v_after.ai_summary,
    'missing_information', to_jsonb(v_after.missing_information),
    'human_follow_up_required', v_after.human_follow_up_required,
    'status', v_after.status
  );


  -- ---------------------------------------------------------
  -- Audit event
  -- ---------------------------------------------------------

  insert into public.b2c_lead_events (
    lead_id,
    event_type,
    actor_type,
    source_message_id,
    before_data,
    after_data,
    metadata
  )
  values (
    p_lead_id,
    'AI_UPDATED',
    'AI',
    p_source_message_id,
    v_before_snapshot,
    v_after_snapshot,
    jsonb_build_object(
      'extractor_version',
      p_extractor_version
    )
  )
  on conflict do nothing
  returning id
  into v_event_id;


  -- If this exact message/event already exists, reuse it.
  if v_event_id is null then
    select id
    into v_event_id
    from public.b2c_lead_events
    where event_type = 'AI_UPDATED'
      and source_message_id = p_source_message_id
    limit 1;
  end if;


  return query
  select
    v_after.id,
    v_after.lead_no,
    v_after.status,
    v_event_id;

end;
$$;


ALTER FUNCTION "public"."b2c_update_lead_from_ai_v1_internal"("p_lead_id" "uuid", "p_source_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone, "p_extractor_version" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."b2c_inbound_messages" (
    "message_id" "text" NOT NULL,
    "woztell_member_id" "text" NOT NULL,
    "woztell_channel_id" "text" NOT NULL,
    "message_type" "text",
    "event_type" "text",
    "customer_message_at" timestamp with time zone,
    "processing_status" "text" DEFAULT 'RECEIVED'::"text" NOT NULL,
    "lead_id" "uuid",
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "last_error" "text",
    "processed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "b2c_inbound_messages_processing_status_check" CHECK (("processing_status" = ANY (ARRAY['RECEIVED'::"text", 'PROCESSING'::"text", 'PROCESSED'::"text", 'FAILED'::"text"])))
);


ALTER TABLE "public"."b2c_inbound_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."b2c_lead_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "actor_type" "text" NOT NULL,
    "actor_user_id" "uuid",
    "source_message_id" "text",
    "before_data" "jsonb",
    "after_data" "jsonb",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "b2c_lead_events_actor_type_check" CHECK (("actor_type" = ANY (ARRAY['CUSTOMER'::"text", 'AI'::"text", 'DISPATCHER'::"text", 'SALES'::"text", 'SYSTEM'::"text"])))
);


ALTER TABLE "public"."b2c_lead_events" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."b2c_lead_no_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."b2c_lead_no_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."b2c_service_blackout_dates" (
    "service_category" "text" NOT NULL,
    "blackout_date" "date" NOT NULL,
    "reason" "text" NOT NULL,
    "source" "text",
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."b2c_service_blackout_dates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."b2c_staff_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_user_id" "uuid",
    "display_name" "text" NOT NULL,
    "workflow_role" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "b2c_staff_users_workflow_role_check" CHECK (("workflow_role" = ANY (ARRAY['DISPATCHER'::"text", 'SALES'::"text", 'ADMIN'::"text"])))
);


ALTER TABLE "public"."b2c_staff_users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."b2c_inbound_messages"
    ADD CONSTRAINT "b2c_inbound_messages_pkey" PRIMARY KEY ("message_id");



ALTER TABLE ONLY "public"."b2c_lead_events"
    ADD CONSTRAINT "b2c_lead_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."b2c_leads"
    ADD CONSTRAINT "b2c_leads_lead_no_key" UNIQUE ("lead_no");



ALTER TABLE ONLY "public"."b2c_leads"
    ADD CONSTRAINT "b2c_leads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."b2c_service_blackout_dates"
    ADD CONSTRAINT "b2c_service_blackout_dates_pkey" PRIMARY KEY ("service_category", "blackout_date");



ALTER TABLE ONLY "public"."b2c_staff_users"
    ADD CONSTRAINT "b2c_staff_users_auth_user_id_key" UNIQUE ("auth_user_id");



ALTER TABLE ONLY "public"."b2c_staff_users"
    ADD CONSTRAINT "b2c_staff_users_pkey" PRIMARY KEY ("id");



CREATE INDEX "b2c_inbound_member_idx" ON "public"."b2c_inbound_messages" USING "btree" ("woztell_member_id", "created_at");



CREATE INDEX "b2c_lead_events_lead_idx" ON "public"."b2c_lead_events" USING "btree" ("lead_id", "created_at");



CREATE UNIQUE INDEX "b2c_lead_events_unique_ai_message" ON "public"."b2c_lead_events" USING "btree" ("source_message_id") WHERE (("event_type" = 'AI_UPDATED'::"text") AND ("source_message_id" IS NOT NULL));



CREATE INDEX "b2c_leads_assigned_sales_idx" ON "public"."b2c_leads" USING "btree" ("assigned_sales_user_id");



CREATE INDEX "b2c_leads_next_follow_up_idx" ON "public"."b2c_leads" USING "btree" ("next_follow_up_at") WHERE ("next_follow_up_at" IS NOT NULL);



CREATE INDEX "b2c_leads_status_idx" ON "public"."b2c_leads" USING "btree" ("status");



CREATE UNIQUE INDEX "b2c_one_active_lead_per_member_service" ON "public"."b2c_leads" USING "btree" ("woztell_member_id", "service_category") WHERE (("status" <> ALL (ARRAY['CLOSED_WON'::"text", 'CLOSED_LOST'::"text"])) AND ("service_category" IS NOT NULL));



CREATE UNIQUE INDEX "b2c_one_active_unknown_lead_per_member" ON "public"."b2c_leads" USING "btree" ("woztell_member_id") WHERE (("status" <> ALL (ARRAY['CLOSED_WON'::"text", 'CLOSED_LOST'::"text"])) AND ("lower"("btrim"("service_category")) = 'unknown'::"text"));



CREATE OR REPLACE TRIGGER "b2c_inbound_messages_set_updated_at" BEFORE UPDATE ON "public"."b2c_inbound_messages" FOR EACH ROW EXECUTE FUNCTION "public"."b2c_set_updated_at"();



CREATE OR REPLACE TRIGGER "b2c_leads_set_updated_at" BEFORE UPDATE ON "public"."b2c_leads" FOR EACH ROW EXECUTE FUNCTION "public"."b2c_set_updated_at"();



CREATE OR REPLACE TRIGGER "b2c_staff_users_set_updated_at" BEFORE UPDATE ON "public"."b2c_staff_users" FOR EACH ROW EXECUTE FUNCTION "public"."b2c_set_updated_at"();



ALTER TABLE ONLY "public"."b2c_inbound_messages"
    ADD CONSTRAINT "b2c_inbound_messages_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."b2c_leads"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."b2c_lead_events"
    ADD CONSTRAINT "b2c_lead_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "public"."b2c_staff_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."b2c_lead_events"
    ADD CONSTRAINT "b2c_lead_events_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."b2c_leads"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."b2c_leads"
    ADD CONSTRAINT "b2c_leads_assigned_by_user_id_fkey" FOREIGN KEY ("assigned_by_user_id") REFERENCES "public"."b2c_staff_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."b2c_leads"
    ADD CONSTRAINT "b2c_leads_assigned_sales_user_id_fkey" FOREIGN KEY ("assigned_sales_user_id") REFERENCES "public"."b2c_staff_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."b2c_staff_users"
    ADD CONSTRAINT "b2c_staff_users_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE "public"."b2c_inbound_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."b2c_lead_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."b2c_leads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."b2c_service_blackout_dates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."b2c_staff_users" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_ai_merge_human_follow_up"("p_existing" boolean, "p_extracted" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_ai_merge_human_follow_up"("p_existing" boolean, "p_extracted" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_apply_ai_result_and_mark_processed"("p_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone, "p_extractor_version" "text", "p_whatsapp_number" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_apply_ai_result_and_mark_processed"("p_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone, "p_extractor_version" "text", "p_whatsapp_number" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_assign_ready_lead"("p_lead_id" "uuid", "p_dispatcher_user_id" "uuid", "p_sales_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_assign_ready_lead"("p_lead_id" "uuid", "p_dispatcher_user_id" "uuid", "p_sales_user_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_assign_ready_lead_as_current_dispatcher"("p_lead_id" "uuid", "p_sales_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_assign_ready_lead_as_current_dispatcher"("p_lead_id" "uuid", "p_sales_user_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."b2c_get_active_lead_context"("p_woztell_member_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_active_lead_context"("p_woztell_member_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_get_active_sales_users"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_active_sales_users"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_get_active_sales_users_as_current_dispatcher"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_active_sales_users_as_current_dispatcher"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."b2c_get_current_staff_context"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_current_staff_context"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."b2c_get_dispatcher_lead_detail"("p_lead_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_dispatcher_lead_detail"("p_lead_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_get_dispatcher_lead_detail_as_current_dispatcher"("p_lead_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_dispatcher_lead_detail_as_current_dispatcher"("p_lead_id" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."b2c_get_dispatcher_review_queue"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_dispatcher_review_queue"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_get_dispatcher_review_queue_as_current_dispatcher"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_get_dispatcher_review_queue_as_current_dispatcher"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."b2c_get_or_create_active_lead"("p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_whatsapp_number" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."b2c_get_or_create_active_lead_v2"("p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_whatsapp_number" "text", "p_service_category" "text") FROM PUBLIC;



GRANT ALL ON FUNCTION "public"."b2c_next_lead_no"() TO "anon";
GRANT ALL ON FUNCTION "public"."b2c_next_lead_no"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."b2c_next_lead_no"() TO "service_role";



GRANT ALL ON TABLE "public"."b2c_leads" TO "anon";
GRANT ALL ON TABLE "public"."b2c_leads" TO "authenticated";
GRANT ALL ON TABLE "public"."b2c_leads" TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_is_lead_ready_for_review"("p_lead" "public"."b2c_leads") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_is_lead_ready_for_review"("p_lead" "public"."b2c_leads") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_list_active_lead_contexts"("p_woztell_member_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_list_active_lead_contexts"("p_woztell_member_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_mark_inbound_message_failed"("p_message_id" "text", "p_error" "text", "p_lead_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_mark_inbound_message_failed"("p_message_id" "text", "p_error" "text", "p_lead_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_mark_inbound_message_processed"("p_message_id" "text", "p_lead_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_mark_inbound_message_processed"("p_message_id" "text", "p_lead_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."b2c_meal_delivery_date_available"("p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."b2c_meal_delivery_date_available"("p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."b2c_meal_delivery_date_available"("p_date" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_reserve_inbound_message"("p_message_id" "text", "p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_message_type" "text", "p_event_type" "text", "p_customer_message_at" timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."b2c_reserve_inbound_message"("p_message_id" "text", "p_woztell_member_id" "text", "p_woztell_channel_id" "text", "p_message_type" "text", "p_event_type" "text", "p_customer_message_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."b2c_set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."b2c_set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."b2c_set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."b2c_update_lead_from_ai"("p_lead_id" "uuid", "p_source_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone, "p_extractor_version" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."b2c_update_lead_from_ai_v1_internal"("p_lead_id" "uuid", "p_source_message_id" "text", "p_extraction" "jsonb", "p_customer_message_at" timestamp with time zone, "p_extractor_version" "text") FROM PUBLIC;



GRANT ALL ON TABLE "public"."b2c_inbound_messages" TO "anon";
GRANT ALL ON TABLE "public"."b2c_inbound_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."b2c_inbound_messages" TO "service_role";



GRANT ALL ON TABLE "public"."b2c_lead_events" TO "anon";
GRANT ALL ON TABLE "public"."b2c_lead_events" TO "authenticated";
GRANT ALL ON TABLE "public"."b2c_lead_events" TO "service_role";



GRANT ALL ON SEQUENCE "public"."b2c_lead_no_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."b2c_lead_no_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."b2c_lead_no_seq" TO "service_role";



GRANT ALL ON TABLE "public"."b2c_service_blackout_dates" TO "anon";
GRANT ALL ON TABLE "public"."b2c_service_blackout_dates" TO "authenticated";
GRANT ALL ON TABLE "public"."b2c_service_blackout_dates" TO "service_role";



GRANT ALL ON TABLE "public"."b2c_staff_users" TO "anon";
GRANT ALL ON TABLE "public"."b2c_staff_users" TO "authenticated";
GRANT ALL ON TABLE "public"."b2c_staff_users" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







