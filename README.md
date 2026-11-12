# Tandem

A shared care record for pets, built for 95-422 Managing Digital Transformation.

Most pets are cared for by more than one person, and nobody has the full picture. Tandem lets an owner set up a pet's routine once; everyone who helps works from the same record and checks off what they do, so the next person knows what's already done. Care can be handed to a sitter for a few days with a scoped care plan, and to a vet with a one-page summary.

## What's in the app

| Tab | What it does |
|---|---|
| **Today** | The pet's checklist for the day. One tap logs a task with who did it and when. Two people can't log the same task twice. Allergies are always visible. Occasional tasks and vaccines appear under "Coming up". |
| **Health** | Allergies, medications, vaccines, weight trend, vet and emergency contacts, document photos. "Share with a vet" builds a PDF from the parts the owner picks. |
| **Care plans** | Hand care to a sitter for a date range. The plan is generated from the existing routine; the owner chooses which kinds of tasks to include. The sitter joins with a 6-character code, link or QR code, and access ends automatically. |
| **Household** | People who share care every day, sitters with temporary access, invites, reminders, account. |

Any species is supported, with several pets per household. One person can own pets in one household and sit for another.

## Running it

1. Open `Tandem.xcodeproj` in Xcode 26 or later.
2. Pick an iPhone simulator (or your phone) and press Run. The Supabase package downloads on first build.

The app talks to a hosted Supabase project; the URL and publishable key are in `Tandem/Services/Backend.swift`. The publishable key is meant to ship in the app. What each person can read or change is enforced by row-level security in the database.

### Demo accounts

`supabase/seed.sql` builds a demo household (Streak and a roommate, Riley; Reese the cat, Biscuit the dog, and Fano the sitter with a care plan that is active today). The three account emails and their shared password are listed at the top of that file. Re-running the file in the Supabase SQL editor resets the demo data and re-dates it to today.

For screenshots and demos, a debug build can sign in straight from launch arguments:

```
-autoLoginEmail streak@tandem.test -autoLoginPassword <password from seed.sql> -startTab 0
```

## How it's built

- **SwiftUI**, iOS 17+, one dependency (`supabase-swift`).
- **`Store/AppStore.swift`** holds everything the signed-in person can see and is the only place that talks to the backend. It reloads whenever Supabase Realtime reports a change, which is how one caregiver's check-off appears on everyone else's phone.
- **`Models/Schedule.swift`** turns routines plus logs into today's task list and the "Coming up" list.
- **`supabase/migrations`** is the database: tables, row-level security, and three RPCs (`create_household`, `redeem_invite`, `rotate_household_code`).

### Who can see what

| | Household member | Sitter (during their plan) | Vet |
|---|---|---|---|
| Routine tasks | All | Only the categories in the plan | – |
| Logging | Any task | Included tasks, on the plan's dates | – |
| Allergies, vet and emergency contacts | Yes | Yes | – |
| Medications | Yes | Only if the plan includes medication | – |
| Vaccines, weight, documents, older history | Yes | No | – |
| Health summary PDF | Creates it | No | Receives what the owner chose |

A vet doesn't need an account; they get a PDF through the share sheet.

### Measuring effectiveness

The app writes anonymous usage events to the `events` table (`task_completed`, `duplicate_prevented`, `invite_accepted`, `care_plan_created`, `vet_summary_shared`, and so on). These can be queried in the Supabase SQL editor for the final report, for example how often a duplicate log was prevented or what share of invites were accepted.

## Not built yet

- Push notifications to other caregivers. Reminders are local to each phone, so they only know about someone else's check-off once the app has synced.
- Sign in with Apple. Accounts use email and password.
