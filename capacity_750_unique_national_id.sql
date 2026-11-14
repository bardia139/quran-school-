-- تنظیم ظرفیت ۷۵۰ دانش‌آموز و جلوگیری از ثبت‌نام تکراری با کد ملی
-- این اسکریپت را یک‌بار در Supabase SQL Editor اجرا کنید.

alter table public.student_submissions
  add column if not exists national_id text;

-- رکوردهای قدیمی می‌توانند فعلاً کد ملی خالی داشته باشند؛
-- اما برای ثبت‌نام‌های جدید کد ملی اجباری است.
alter table public.student_submissions
  drop constraint if exists student_submissions_national_id_format;

alter table public.student_submissions
  add constraint student_submissions_national_id_format
  check (national_id is null or national_id ~ '^[0-9]{10}$');

create unique index if not exists student_submissions_national_id_unique
  on public.student_submissions (national_id)
  where national_id is not null;

create or replace function public.enforce_student_registration_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_total bigint;
begin
  if new.national_id is null or new.national_id !~ '^[0-9]{10}$' then
    raise exception 'کد ملی باید دقیقاً ۱۰ رقم باشد'
      using errcode = '23514';
  end if;

  -- هم‌زمانی ثبت‌نام‌ها را کنترل می‌کند تا ظرفیت از ۷۵۰ عبور نکند.
  perform pg_advisory_xact_lock(hashtext('student_submissions_capacity_750'));

  select count(*) into current_total
  from public.student_submissions;

  if current_total >= 750 then
    raise exception 'ظرفیت ثبت‌نام ۷۵۰ نفر تکمیل شده است'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists student_submissions_registration_limits
  on public.student_submissions;

create trigger student_submissions_registration_limits
before insert on public.student_submissions
for each row
execute function public.enforce_student_registration_limits();
