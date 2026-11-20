// Sends a push notification to a pet's other caregivers when someone logs care or joins a care plan.
//
// The app calls this right after it writes a log. The function trusts nothing from the caller except
// their sign-in: it re-reads the log from the database, checks the caller really wrote it, works out
// who else cares for that pet, and sends to their phones through Apple's push service (APNs).
//
// Secrets (Supabase dashboard → Edge Functions → Secrets):
//   APNS_KEY_ID       the 10-character ID of the APNs key
//   APNS_TEAM_ID      the Apple developer team ID
//   APNS_PRIVATE_KEY  the full contents of the .p8 file
//   APNS_BUNDLE_ID    the app's bundle ID (defaults to com.streakhoney.tandem)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.streakhoney.tandem";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The short-lived token APNs wants, signed with the team's key. Null when the key isn't configured. */
async function apnsToken(): Promise<string | null> {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const pem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !pem) return null;

  const base64 = pem.replace(/\\n/g, "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${claims}`));
  return `${head}.${claims}.${b64url(signature)}`;
}

const dayOffset = (days: number) => new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);

/** Household members of the pet, plus any sitter whose active plan covers this kind of care today. */
async function caregivers(petId: string, householdId: string, category: string): Promise<string[]> {
  const ids = new Set<string>();
  const { data: members } = await admin.from("household_members").select("user_id").eq("household_id", householdId);
  for (const m of members ?? []) ids.add(m.user_id);

  const { data: plans } = await admin
    .from("care_plans")
    .select("sitter_id, categories, start_date, end_date, care_plan_pets!inner(pet_id)")
    .eq("care_plan_pets.pet_id", petId)
    .eq("status", "active")
    .not("sitter_id", "is", null);
  for (const p of plans ?? []) {
    // A day of slack either side, since the server's "today" can differ from the phone's.
    const current = p.start_date <= dayOffset(1) && p.end_date >= dayOffset(-1);
    if (current && (category === "note" || (p.categories ?? []).includes(category))) ids.add(p.sitter_id);
  }
  return [...ids];
}

Deno.serve(async (req) => {
  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return json({ error: "Not signed in" }, 401);

    const body = await req.json().catch(() => ({}));
    let recipients: string[] = [];
    let title = "Tandem";
    let text = "";
    let preference: "notify_tasks" | "notify_notes" | null = null;
    let petId: string | null = null;

    if (body.type === "log") {
      const { data: log } = await admin
        .from("care_logs")
        .select("pet_id, routine_id, category, title, status, note, logged_by, logged_by_name")
        .eq("id", body.log_id)
        .maybeSingle();
      if (!log || log.logged_by !== user.id) return json({ error: "Log not found" }, 404);
      const { data: pet } = await admin.from("pets").select("id, name, household_id").eq("id", log.pet_id).single();
      if (!pet) return json({ error: "Pet not found" }, 404);

      const who = log.logged_by_name || "Someone";
      petId = pet.id;
      title = pet.name;
      if (!log.routine_id) {
        preference = "notify_notes";
        text = `${who} noted: ${log.title}${log.note ? ` – ${log.note}` : ""}`;
      } else {
        preference = "notify_tasks";
        text = `${who} ${log.status === "skipped" ? "skipped" : "checked off"} ${log.title}${log.note ? ` – ${log.note}` : ""}`;
      }
      recipients = await caregivers(pet.id, pet.household_id, log.category);
    } else if (body.type === "plan_joined") {
      const { data: plan } = await admin
        .from("care_plans")
        .select("household_id, sitter_id, sitter_name, start_date, end_date")
        .eq("id", body.plan_id)
        .maybeSingle();
      if (!plan || plan.sitter_id !== user.id) return json({ error: "Plan not found" }, 404);
      title = "Care plan";
      text = `${plan.sitter_name || "Your sitter"} joined the care plan and can now see the routine.`;
      const { data: members } = await admin.from("household_members").select("user_id").eq("household_id", plan.household_id);
      recipients = (members ?? []).map((m) => m.user_id);
    } else {
      return json({ error: "Unknown type" }, 400);
    }

    recipients = recipients.filter((id) => id !== user.id);
    if (preference && recipients.length) {
      const { data: prefs } = await admin.from("profiles").select("id").in("id", recipients).eq(preference, true);
      recipients = (prefs ?? []).map((p) => p.id);
    }
    if (!recipients.length) return json({ sent: 0, reason: "No one else to notify" });

    const { data: devices } = await admin.from("device_tokens").select("token, environment").in("user_id", recipients);
    if (!devices?.length) return json({ sent: 0, reason: "No registered phones" });

    const token = await apnsToken();
    if (!token) return json({ sent: 0, reason: "APNs key is not configured" });

    const payload = JSON.stringify({
      aps: { alert: { title, body: text }, sound: "default", "content-available": 1, ...(petId ? { "thread-id": petId } : {}) },
      pet_id: petId,
    });

    let sent = 0;
    const failures: string[] = [];
    await Promise.all(devices.map(async (device) => {
      const host = device.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
      const res = await fetch(`https://${host}/3/device/${device.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${token}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        body: payload,
      });
      if (res.ok) {
        sent++;
        return;
      }
      const reason = (await res.json().catch(() => ({})))?.reason ?? String(res.status);
      failures.push(reason);
      // The app was deleted or the token is for the other environment: stop trying this phone.
      if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
        await admin.from("device_tokens").delete().eq("token", device.token);
      }
    }));

    return json({ sent, failures });
  } catch (error) {
    console.error(error);
    return json({ error: String(error) }, 500);
  }
});
