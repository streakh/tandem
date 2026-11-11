-- Demo data for testing and the final presentation. Safe to re-run: it rebuilds the demo household from scratch.
--
-- Demo accounts (all use the password below; these are throwaway test accounts on fake addresses):
--   alex@tandem.test   owner of the household
--   riley@tandem.test  household member (roommate)
--   fano@tandem.test   pet sitter with a care plan that is active right now
--   password: REPLACE_WITH_DEMO_PASSWORD

do $$
declare
  pw constant text := 'REPLACE_WITH_DEMO_PASSWORD';
  today date := (now() at time zone 'America/New_York')::date;
  tz constant text := 'America/New_York';
  alex uuid; riley uuid; fano uuid;
  hid uuid; reese uuid; biscuit uuid;
  thyroid uuid; drops uuid;
  r_breakfast uuid; r_med_am uuid; r_water uuid; r_dinner uuid; r_med_pm uuid; r_litter uuid; r_drops uuid; r_flea uuid; r_nails uuid;
  b_breakfast uuid; b_walk_am uuid; b_dinner uuid; b_walk_pm uuid; b_water uuid; b_bath uuid;
  plan_now uuid; plan_past uuid;
  d date; i int; who uuid; who_name text; pid uuid;
  u record;
begin
  -- reset
  delete from public.households where created_by in (select id from auth.users where email like '%@tandem.test');
  delete from auth.users where email like '%@tandem.test';

  -- accounts
  for u in select * from (values ('alex@tandem.test','Alex'), ('riley@tandem.test','Riley'), ('fano@tandem.test','Fano')) as t(email, name) loop
    who := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', who, 'authenticated', 'authenticated', u.email,
            extensions.crypt(pw, extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('display_name', u.name), now(), now(),
            '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), who, who::text, jsonb_build_object('sub', who::text, 'email', u.email, 'email_verified', true),
            'email', now(), now(), now());
    if u.name = 'Alex' then alex := who; elsif u.name = 'Riley' then riley := who; else fano := who; end if;
  end loop;

  -- household
  insert into public.households (name, created_by) values ('Alex & Riley''s place', alex) returning id into hid;
  insert into public.household_members (household_id, user_id, role, display_name)
  values (hid, alex, 'owner', 'Alex'), (hid, riley, 'member', 'Riley');

  -- pets
  insert into public.pets (household_id, name, species, breed, sex, birthdate, weight, weight_unit, notes, microchip,
                           vet_name, vet_clinic, vet_phone, vet_address, emergency_name, emergency_phone, created_at)
  values (hid, 'Reese', 'cat', 'Tabby', 'Female', date '2021-05-14', 10, 'lb',
          'Hides when the doorbell rings. Treats only after dinner. She''s chatty in the morning; if she''s quiet and not eating, something is off.',
          '985112004567812', 'Dr. Patel', 'Shadyside Animal Clinic', '(412) 555-0142', '5600 Walnut St, Pittsburgh',
          'Riley (roommate)', '(412) 555-0187', now() - interval '2 minutes')
  returning id into reese;
  insert into public.pets (household_id, name, species, breed, sex, birthdate, weight, weight_unit, notes,
                           vet_name, vet_clinic, vet_phone, emergency_name, emergency_phone)
  values (hid, 'Biscuit', 'dog', 'Beagle mix', 'Male', date '2019-09-02', 24, 'lb',
          'Pulls toward squirrels, so keep the leash short near the park. Never off-leash.',
          'Dr. Patel', 'Shadyside Animal Clinic', '(412) 555-0142', 'Riley (roommate)', '(412) 555-0187')
  returning id into biscuit;

  -- health
  insert into public.allergies (pet_id, name, severity, notes) values
    (reese, 'Chicken', 'Moderate', 'Vomiting within a few hours. Check treat labels.'),
    (reese, 'Flea bites', 'Severe', 'Skin flares up badly; keep the monthly treatment on time.');
  insert into public.medications (pet_id, name, dose, frequency, instructions)
  values (reese, 'Thyroid pill', '1 tablet', 'twice daily', 'Hide it in a pill pocket. Make sure she actually swallows it.') returning id into thyroid;
  insert into public.medications (pet_id, name, dose, frequency, instructions)
  values (reese, 'Ear drops', '3 drops per ear', 'every other day', 'Massage the base of the ear for a few seconds afterwards.') returning id into drops;
  insert into public.vaccines (pet_id, name, date_given, due_date) values
    (reese, 'Rabies', today - 345, today + 20),
    (reese, 'FVRCP', today - 210, today + 155),
    (biscuit, 'Rabies', today - 500, today + 595),
    (biscuit, 'DHPP', today - 380, today - 15);
  insert into public.weight_entries (pet_id, weight, unit, measured_on) values
    (reese, 10.9, 'lb', today - 240), (reese, 10.6, 'lb', today - 180), (reese, 10.4, 'lb', today - 120),
    (reese, 10.1, 'lb', today - 60), (reese, 10.0, 'lb', today - 9),
    (biscuit, 23.5, 'lb', today - 150), (biscuit, 24.0, 'lb', today - 30);

  -- Reese's routine
  insert into public.routines (pet_id, category, title, amount, details, time_of_day, start_date)
  values (reese, 'feeding', 'Breakfast', '¼ cup dry + ½ can wet', 'Salmon or turkey cans only (no chicken).', '08:00', today - 60) returning id into r_breakfast;
  insert into public.routines (pet_id, category, title, amount, time_of_day, medication_id, start_date)
  values (reese, 'medication', 'Morning med', '1 thyroid tablet', '08:00', thyroid, today - 60) returning id into r_med_am;
  insert into public.routines (pet_id, category, title, details, time_of_day, start_date)
  values (reese, 'water', 'Fresh water', 'Rinse and refill the fountain.', '08:00', today - 60) returning id into r_water;
  insert into public.routines (pet_id, category, title, amount, time_of_day, start_date)
  values (reese, 'feeding', 'Dinner', '¼ cup dry + ½ can wet', '18:00', today - 60) returning id into r_dinner;
  insert into public.routines (pet_id, category, title, amount, time_of_day, medication_id, start_date)
  values (reese, 'medication', 'Evening med', '1 thyroid tablet', '18:00', thyroid, today - 60) returning id into r_med_pm;
  insert into public.routines (pet_id, category, title, time_of_day, start_date)
  values (reese, 'cleaning', 'Scoop litter box', '19:00', today - 60) returning id into r_litter;
  insert into public.routines (pet_id, category, title, amount, schedule, interval_days, medication_id, start_date)
  values (reese, 'medication', 'Ear drops', '3 drops per ear', 'interval', 2, drops, today - 20) returning id into r_drops;
  insert into public.routines (pet_id, category, title, details, schedule, interval_days, start_date)
  values (reese, 'medication', 'Flea treatment', 'Apply between the shoulder blades.', 'interval', 30, today - 54) returning id into r_flea;
  insert into public.routines (pet_id, category, title, schedule, interval_days, start_date)
  values (reese, 'grooming', 'Nail trim', 'interval', 21, today - 30) returning id into r_nails;

  -- Biscuit's routine
  insert into public.routines (pet_id, category, title, amount, time_of_day, start_date)
  values (biscuit, 'feeding', 'Breakfast', '1 cup kibble', '07:30', today - 60) returning id into b_breakfast;
  insert into public.routines (pet_id, category, title, amount, time_of_day, start_date)
  values (biscuit, 'walk', 'Morning walk', '20 minutes', '07:45', today - 60) returning id into b_walk_am;
  insert into public.routines (pet_id, category, title, time_of_day, start_date)
  values (biscuit, 'water', 'Fresh water', '07:30', today - 60) returning id into b_water;
  insert into public.routines (pet_id, category, title, amount, time_of_day, start_date)
  values (biscuit, 'feeding', 'Dinner', '1 cup kibble', '18:00', today - 60) returning id into b_dinner;
  insert into public.routines (pet_id, category, title, amount, time_of_day, start_date)
  values (biscuit, 'walk', 'Evening walk', '30 minutes', '18:30', today - 60) returning id into b_walk_pm;
  insert into public.routines (pet_id, category, title, schedule, interval_days, start_date)
  values (biscuit, 'grooming', 'Bath', 'interval', 30, today - 40) returning id into b_bath;

  -- care plans: one that ended (the October trip), one happening now with Fano, one upcoming and not yet accepted
  insert into public.care_plans (household_id, title, caregiver_label, start_date, end_date, categories, notes, emergency_notes,
                                 sitter_id, sitter_name, created_by, created_by_name, accepted_at, created_at)
  values (hid, '', 'Fano', today - 22, today - 18, '{feeding,water,medication,cleaning}',
          'Reese hides when the doorbell rings. Treats only after dinner.',
          'Call me first: Alex. If you can''t reach me: Riley, (412) 555-0187.', fano, 'Fano', alex, 'Alex', now() - interval '23 days', now() - interval '24 days')
  returning id into plan_past;
  insert into public.care_plans (household_id, title, caregiver_label, start_date, end_date, categories, notes, emergency_notes,
                                 sitter_id, sitter_name, created_by, created_by_name, accepted_at, created_at)
  values (hid, '', 'Fano', today - 1, today + 3, '{feeding,water,medication,cleaning}',
          'Reese hides when the doorbell rings. Treats only after dinner. Spare key is with the neighbor in 2B. Wet food is in the pantry, second shelf.',
          'Call me first: Alex. If you can''t reach me: Riley, (412) 555-0187. Vet: Shadyside Animal Clinic, (412) 555-0142. If she stops eating for a full day, call the vet; you''re approved for up to $300.',
          fano, 'Fano', alex, 'Alex', now() - interval '2 days', now() - interval '3 days')
  returning id into plan_now;
  insert into public.care_plan_pets values (plan_past, reese), (plan_now, reese);
  insert into public.care_plans (household_id, title, caregiver_label, start_date, end_date, categories, notes, created_by, created_by_name)
  values (hid, 'Thanksgiving trip', 'Maya', today + 14, today + 18, '{feeding,water,walk,medication,cleaning}',
          'Both pets this time. Biscuit needs two real walks a day.', alex, 'Alex');
  insert into public.care_plan_pets select id, reese from public.care_plans where title = 'Thanksgiving trip' and household_id = hid;
  insert into public.care_plan_pets select id, biscuit from public.care_plans where title = 'Thanksgiving trip' and household_id = hid;

  -- two weeks of history, alternating between Alex and Riley (Fano during the plans)
  for i in 1..14 loop
    d := today - i;
    pid := null;
    if d between today - 22 and today - 18 then who := fano; who_name := 'Fano'; pid := plan_past;
    elsif d >= today - 1 then who := fano; who_name := 'Fano'; pid := plan_now;
    elsif i % 2 = 0 then who := alex; who_name := 'Alex';
    else who := riley; who_name := 'Riley'; end if;

    insert into public.care_logs (pet_id, routine_id, category, title, scheduled_for, logged_by, logged_by_name, logged_at, care_plan_id, note)
    values
      (reese, r_breakfast, 'feeding', 'Breakfast', d, who, who_name, (d + time '07:48') at time zone tz, pid, case when i = 3 then 'Ate about half' else '' end),
      (reese, r_med_am, 'medication', 'Morning med', d, who, who_name, (d + time '07:50') at time zone tz, pid, ''),
      (reese, r_water, 'water', 'Fresh water', d, who, who_name, (d + time '07:52') at time zone tz, pid, ''),
      (reese, r_dinner, 'feeding', 'Dinner', d, who, who_name, (d + time '18:10') at time zone tz, pid, ''),
      (reese, r_litter, 'cleaning', 'Scoop litter box', d, who, who_name, (d + time '19:20') at time zone tz, pid, '');
    if i <> 5 then  -- one missed evening dose, the kind of gap a vet wants to know about
      insert into public.care_logs (pet_id, routine_id, category, title, scheduled_for, logged_by, logged_by_name, logged_at, care_plan_id)
      values (reese, r_med_pm, 'medication', 'Evening med', d, who, who_name, (d + time '18:12') at time zone tz, pid);
    end if;
    if i % 2 = 0 then
      insert into public.care_logs (pet_id, routine_id, category, title, scheduled_for, logged_by, logged_by_name, logged_at)
      values (reese, r_drops, 'medication', 'Ear drops', d, alex, 'Alex', (d + time '20:05') at time zone tz);
    end if;

    who := case when i % 2 = 0 then alex else riley end;
    who_name := case when i % 2 = 0 then 'Alex' else 'Riley' end;
    insert into public.care_logs (pet_id, routine_id, category, title, scheduled_for, logged_by, logged_by_name, logged_at, status)
    values
      (biscuit, b_breakfast, 'feeding', 'Breakfast', d, who, who_name, (d + time '07:35') at time zone tz, 'done'),
      (biscuit, b_walk_am, 'walk', 'Morning walk', d, who, who_name, (d + time '08:10') at time zone tz, case when i = 4 then 'skipped' else 'done' end),
      (biscuit, b_water, 'water', 'Fresh water', d, who, who_name, (d + time '07:36') at time zone tz, 'done'),
      (biscuit, b_dinner, 'feeding', 'Dinner', d, who, who_name, (d + time '18:05') at time zone tz, 'done'),
      (biscuit, b_walk_pm, 'walk', 'Evening walk', d, who, who_name, (d + time '19:00') at time zone tz, 'done');
  end loop;

  -- occasional tasks done a while back, so "Coming up" has something real in it
  insert into public.care_logs (pet_id, routine_id, category, title, scheduled_for, logged_by, logged_by_name, logged_at) values
    (reese, r_flea, 'medication', 'Flea treatment', today - 24, alex, 'Alex', (today - 24 + time '10:00') at time zone tz),
    (reese, r_nails, 'grooming', 'Nail trim', today - 16, riley, 'Riley', (today - 16 + time '11:30') at time zone tz),
    (biscuit, b_bath, 'grooming', 'Bath', today - 33, riley, 'Riley', (today - 33 + time '15:00') at time zone tz);

  -- this morning: the sitter has done breakfast and the morning med, and left a note
  insert into public.care_logs (pet_id, routine_id, category, title, scheduled_for, logged_by, logged_by_name, logged_at, care_plan_id) values
    (reese, r_breakfast, 'feeding', 'Breakfast', today, fano, 'Fano', (today + time '07:42') at time zone tz, plan_now),
    (reese, r_med_am, 'medication', 'Morning med', today, fano, 'Fano', (today + time '07:44') at time zone tz, plan_now);
  insert into public.care_logs (pet_id, category, title, note, scheduled_for, logged_by, logged_by_name, logged_at, care_plan_id) values
    (reese, 'note', 'Seemed off', 'Sneezed a few times after breakfast but ate everything.', today, fano, 'Fano', (today + time '07:55') at time zone tz, plan_now),
    (reese, 'note', 'Vomiting', 'Small hairball in the hallway, back to normal after.', today - 6, riley, 'Riley', (today - 6 + time '09:15') at time zone tz, null);
  insert into public.care_logs (pet_id, routine_id, category, title, scheduled_for, logged_by, logged_by_name, logged_at) values
    (biscuit, b_breakfast, 'feeding', 'Breakfast', today, riley, 'Riley', (today + time '07:31') at time zone tz),
    (biscuit, b_walk_am, 'walk', 'Morning walk', today, riley, 'Riley', (today + time '08:05') at time zone tz),
    (biscuit, b_water, 'water', 'Fresh water', today, riley, 'Riley', (today + time '07:32') at time zone tz);
end $$;
