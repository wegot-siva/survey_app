// review-signup — approve or reject a signup request.
//
// ===========================================================================
// READ THIS FIRST. This is the project's first DEPLOYED CODE artifact — the
// only thing here that is neither Flutter nor SQL — and it is invisible to
// anyone reading only the Dart. Nothing in `flutter build` touches it. It
// lives in Supabase, is deployed by hand, and if it is not deployed the
// review queue fails at the first Approve tap.
//
// (It is not the project's only server-side machinery: schema.sql already
// schedules purge_expired_photo_tombstones via pg_cron + pg_net. But that
// runs inside the database. This does not.)
// ===========================================================================
//
// WHY THIS EXISTS RATHER THAN A PLAIN SQL RPC
// -------------------------------------------
// Two reasons, both hard blocks:
//
// 1. Creating an auth.users row and minting a password-set link are GoTrue
//    operations, not Postgres ones. SECURITY DEFINER grants Postgres
//    privileges — it does not grant GoTrue privileges. No amount of SQL can
//    call the Auth Admin API. (Writing bcrypt straight into GoTrue's own
//    tables would "work" until the next GoTrue release changes them, which
//    is the same trap we refused in Slice 3 over password storage.)
//
// 2. approve_signup_request() has to set profiles.role and profiles.active.
//    The prevent_self_role_escalation trigger refuses that unless
//    auth.uid() is null or the caller is_admin(). An APPROVER is neither, so
//    an approver calling the RPC with their own JWT would be rejected by the
//    trigger — correctly. Under the service_role key there is no `sub`
//    claim, auth.uid() is null, and the trigger exempts the write. That
//    trigger is load-bearing and is NOT weakened; this function is how a
//    non-admin reviewer acts without it needing to be.
//
// The consequence of (2) is that the RPC cannot discover its own caller —
// auth.uid() is null there. So this function verifies the caller's JWT
// against GoTrue and passes the ALREADY-VERIFIED reviewer id as a parameter.
// The trust boundary is right here, at getUser(). The request body is never
// trusted for identity, for the caller's role, or for the granted role.
//
// DEPLOYING
// ---------
//   supabase functions deploy review-signup --project-ref <ref>
//
// The service_role key is NOT in this file, not in the repo, not in .env and
// not in the APK. Supabase injects SUPABASE_SERVICE_ROLE_KEY into the
// function's environment automatically; it never leaves the server. If you
// ever need to set it by hand it belongs in Dashboard → Edge Functions →
// Secrets (or `supabase secrets set`), never in source control.
//
// KEY ROTATION, and this one WILL bite somebody: the project now holds the
// service_role key in two independent places. This function gets it injected
// and so follows a rotation automatically. purge_expired_photo_tombstones
// reads its own COPY from Supabase Vault (secret `service_role_key`) and does
// NOT. Rotate the key and the nightly photo purge starts failing silently
// until that Vault secret is updated by hand. Nothing here changes that — it
// just makes it easier to forget there are two.
//
// Deploying is a manual step after any change here. There is no CI.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.10';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

// EMAIL DELIVERY — the two paths, and why they must never both run.
//
// 'link'  (default, primary): generateLink mints the password-set link and we
//         hand it back to the approver, who sends it however they already
//         talk to that person. Needs no SMTP and cannot be rate-limited.
//
// 'smtp'  (fallback): GoTrue sends the mail itself. This depends on project
//         SMTP being configured. Supabase's built-in sender is NOT a real
//         mail service — it is heavily rate-limited and, on a default
//         project, will only deliver to addresses on the project's own team.
//         Field engineers on gmail addresses will simply not receive
//         anything until a real SMTP provider is configured.
//
// They are mutually exclusive ON PURPOSE. GoTrue keeps a SINGLE recovery
// token per user (auth.users.recovery_token), so generating a second link
// invalidates the first. Running both paths would email a link and then hand
// the approver a different link that silently killed it. Pick one.
const EMAIL_DELIVERY = (Deno.env.get('SIGNUP_EMAIL_DELIVERY') ?? 'link').toLowerCase();

// 'recovery' rather than 'invite': the account already exists by the time we
// mint a link (we create it inert first — see the ordering note in
// schema.sql), and GoTrue's invite link refuses an existing user. A recovery
// link lands the user on the set-a-password flow, which is what we want for
// an account that has no password at all yet.
const LINK_TYPE = 'recovery';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

/** Maps a Postgres error from the RPCs onto a stable code for the client. */
function rpcErrorCode(message: string): string {
  for (
    const known of [
      'not_a_reviewer',
      'role_above_reviewer',
      'invite_unusable',
      'account_not_inert',
      'account_email_mismatch',
      'unknown_role',
    ]
  ) {
    if (message.includes(known)) return known;
  }
  return 'server_error';
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return json({ error: 'unauthenticated' }, 401);
  }

  // ---- The trust boundary. Everything downstream depends on this line. ----
  // The caller's JWT is validated against GoTrue here. `user.id` is the only
  // identity this function will use; the body cannot override it.
  const asCaller = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await asCaller.auth.getUser();
  if (authError || !user) return json({ error: 'unauthenticated' }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // The reviewer's role is read SERVER-SIDE from profiles. It is never
  // accepted from the request, and an inactive reviewer is refused here as
  // well as inside the RPCs.
  const { data: reviewer } = await admin
    .from('profiles')
    .select('role, active')
    .eq('id', user.id)
    .maybeSingle();

  if (!reviewer || !reviewer.active || !['admin', 'approver'].includes(reviewer.role)) {
    return json({ error: 'not_a_reviewer' }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }

  const action = String(body.action ?? '');
  const requestId = String(body.request_id ?? '');
  if (!requestId) return json({ error: 'bad_request' }, 400);

  const { data: request } = await admin
    .from('signup_requests')
    .select('id, email, full_name, requested_role, status, invite_code_used')
    .eq('id', requestId)
    .maybeSingle();

  if (!request) return json({ error: 'not_found' }, 404);
  if (request.status !== 'pending') {
    return json({ ok: false, reason: 'already_reviewed' });
  }

  if (action === 'reject') {
    const { data, error } = await admin.rpc('reject_signup_request', {
      p_request_id: requestId,
      p_reviewer_id: user.id,
      p_reason: body.reason == null ? null : String(body.reason),
    });
    if (error) {
      return json({ error: rpcErrorCode(error.message) }, 403);
    }
    return json(data);
  }

  if (action !== 'approve') return json({ error: 'bad_request' }, 400);

  // The granted role is the APPROVER'S decision. It defaults to what was
  // requested only for convenience — requested_role never grants anything by
  // itself, and the authority check below is against the granted role, not
  // the requested one.
  const grantedRole = String(body.granted_role ?? request.requested_role);

  // Pre-flight the authority matrix BEFORE creating any account. The RPC
  // re-checks it and is the real authority, but failing here means an
  // unauthorised reviewer never causes an orphaned Auth user to exist.
  const { data: mayGrant } = await admin.rpc('may_approve_role', {
    p_reviewer_role: reviewer.role,
    p_target_role: grantedRole,
  });
  if (mayGrant !== true) return json({ error: 'role_above_reviewer' }, 403);

  // Pre-flight the invite code BEFORE creating anything.
  //
  // approve_signup_request() re-checks this under a row lock and is the real
  // authority — but it does so AFTER the account exists, so without this a
  // plainly revoked code would leave an inert orphan account behind every
  // time somebody tried. Checking first means the ordinary "that code is
  // dead" case creates nothing at all. The orphan state is then reserved for
  // what it was designed for: a genuine race, where the code died in the
  // moment between here and consumption.
  //
  // Read-only. Reuses validate_signup_invite so it cannot drift from the
  // predicate consumption applies.
  const { data: codeCheck } = await admin.rpc('validate_signup_invite', {
    p_code: request.invite_code_used,
  });
  const codeUsable = Array.isArray(codeCheck) && codeCheck[0]?.valid === true;
  if (!codeUsable) {
    return json({ error: 'invite_unusable', recoverable: true }, 409);
  }

  // ---- Step 2: create the account INERT. ----------------------------------
  // No `role` in app_metadata, so Slice 0's handle_new_user writes a profile
  // with role='engineer', active=false, and Slice 1 makes that mean no data
  // access whatever. If anything below fails, THIS is the state left behind:
  // a login that can see nothing, and a request still sitting in the queue.
  //
  // email_confirm so the address does not also need a separate confirmation
  // round-trip; the recovery link below is what proves control of the inbox.
  let userId: string | null = null;

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: request.email,
    email_confirm: true,
    user_metadata: { full_name: request.full_name },
    // Deliberately no app_metadata.role. The role is granted by the RPC,
    // inside the transaction, after the invite code has been consumed.
  });

  if (created?.user) {
    userId = created.user.id;
  } else {
    // ---- Orphan recovery. -------------------------------------------------
    // An account already exists for this email. That is EXPECTED when a
    // previous attempt died between step 2 and step 3, and re-running is how
    // that state is meant to be repaired.
    //
    // But it is only safe to adopt an account this flow itself abandoned. An
    // account that is already active belongs to a real user — activating or
    // re-roling it here would be a takeover. So: adopt only an inert one,
    // and let the RPC enforce the same rule again (`and not p.active`, plus
    // an email match) so a bug in this file cannot get past it.
    const { data: existingId } = await admin.rpc('auth_user_id_for_email', {
      p_email: request.email,
    });
    if (!existingId) {
      return json({ error: 'account_create_failed', detail: createError?.message }, 500);
    }

    const { data: existingProfile } = await admin
      .from('profiles')
      .select('active')
      .eq('id', existingId)
      .maybeSingle();

    if (!existingProfile || existingProfile.active) {
      return json({ error: 'email_in_use' }, 409);
    }
    userId = existingId as string;
  }

  // ---- Step 3: the entire database side, in ONE transaction. --------------
  // Consumes the invite code (re-checking revoked/expired/exhausted under a
  // row lock), flips the request pending->approved, and activates the
  // profile with the granted role. All three or none. A raise in there rolls
  // back to the inert-account state described above.
  const { data: result, error: rpcError } = await admin.rpc('approve_signup_request', {
    p_request_id: requestId,
    p_reviewer_id: user.id,
    p_user_id: userId,
    p_granted_role: grantedRole,
  });

  if (rpcError) {
    const code = rpcErrorCode(rpcError.message);
    // The account stays inert and the request stays pending — deliberately
    // NOT cleaned up. Deleting a GoTrue user is itself a fallible remote
    // call, and a compensating delete that fails leaves a worse mess than
    // the inert account it was trying to tidy. Approving again recovers.
    return json({ error: code, recoverable: true }, 409);
  }
  if (result?.ok !== true) {
    return json(result); // already_reviewed — nothing was written.
  }

  // ---- Step 4: the link. The database is already consistent by here. ------
  // Failing now leaves a correct, working account with no link delivered,
  // which is repaired by approving again (the account is live, so this
  // returns email_in_use) or by a plain password reset. Nothing is lost.
  let actionLink: string | null = null;
  let deliveryNote: string;

  if (EMAIL_DELIVERY === 'smtp') {
    // A clean anon client, deliberately NOT the caller's — this is a
    // recovery mail for the applicant, and it has no business carrying the
    // approver's session.
    const anon = createClient(SUPABASE_URL, ANON_KEY);
    const { error: mailError } = await anon.auth.resetPasswordForEmail(request.email);
    deliveryNote = mailError
      ? `email_failed: ${mailError.message}`
      : 'emailed';
  } else {
    const { data: link, error: linkError } = await admin.auth.admin.generateLink({
      type: LINK_TYPE,
      email: request.email,
    });
    // Response shape is GoTrue's: data.properties.action_link. Read
    // defensively — this is the one part of the flow whose exact contract
    // could not be verified before deployment.
    actionLink = (link as { properties?: { action_link?: string } })?.properties?.action_link ??
      null;
    deliveryNote = linkError
      ? `link_failed: ${linkError.message}`
      : (actionLink ? 'link_generated' : 'link_missing');
  }

  return json({
    ok: true,
    request_id: requestId,
    user_id: userId,
    email: request.email,
    granted_role: grantedRole,
    delivery: deliveryNote,
    action_link: actionLink,
  });
});
