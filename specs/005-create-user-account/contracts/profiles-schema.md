# Contract: Supabase Auth and `profiles` (shared backend)

## Status: already implemented and deployed

Este contrato descreve o schema **já criado e aplicado** pela feature Android equivalente, no mesmo
projeto Supabase compartilhado pelos dois apps. Nenhuma migration nova é criada por esta feature
iOS (ver [research.md §0](../research.md)) — este documento existe para que o Repository iOS seja
implementado contra o contrato exato já ativo, incluindo os nomes de constraint usados na allowlist
de sanitização de erros.

## Ownership

- A identidade de autenticação pertence ao Supabase Auth em `auth.users`.
- O perfil do aplicativo pertence a `public.profiles`.
- Ambas as linhas compartilham o mesmo UUID; o perfil não pode existir sem sua identidade Auth.
- `public.profiles` é o armazenamento autoritativo de perfil. A metadata de usuário do Auth é
  entrada não confiável de trigger/recuperação, nunca dado de autorização.
- Este schema é consumido de forma idêntica por Android e iOS — nenhum campo, constraint, trigger
  ou policy é específico de uma plataforma.

## Table contract

| Column | Type | Required | Source |
|---|---|---:|---|
| `id` | `uuid` | Yes | `auth.users.id`; PK/FK with delete cascade |
| `name` | `text` | Yes | Normalized `name` metadata |
| `email` | `text` | Yes | Lowercased `auth.users.email` |
| `phone` | `text` | Yes | Normalized `phone` metadata |
| `cpf` | `text` | Conditional | Normalized `cpf` for person |
| `cnpj` | `text` | Conditional | Normalized `cnpj` for company |
| `active` | `boolean` | Yes | Database default `true`; system-owned |

No other columns are added by this feature (Android nor iOS).

## Named constraints

Stable names are part of the Repository error-classification allowlist on **both** platforms:

| Constraint | Rule |
|---|---|
| `profiles_pkey` | Unique ID and 1:1 relation |
| `profiles_name_normalized` | `name = btrim(name)` and nonblank |
| `profiles_email_normalized` | `email = lower(btrim(email))` and nonblank |
| `profiles_phone_normalized` | 10/11 digits and accepted Brazilian DDD |
| `profiles_exactly_one_document` | Exactly one of CPF/CNPJ is non-null |
| `profiles_cpf_normalized` | Null or 11 digits |
| `profiles_cpf_valid` | Null or valid non-repeated CPF checksum |
| `profiles_cnpj_normalized` | Null or `[0-9A-Z]{12}[0-9]{2}` |
| `profiles_cnpj_valid` | Null or valid official CNPJ checksum |
| `profiles_email_unique` | Normalized email unique |
| `profiles_cpf_unique` | Present CPF unique; multiple nulls allowed |
| `profiles_cnpj_unique` | Present CNPJ unique; multiple nulls allowed |

CPF and CNPJ are text, never numeric. CNPJ accepts both legacy numeric and the alphanumeric format
assigned from July 2026.

## Trigger contract

An `AFTER INSERT` trigger on `auth.users` calls a hardened function that:

1. uses `security definer` and an empty `search_path`;
2. fully qualifies every schema/table/function reference;
3. reads `new.id`, `new.email` and namespaced profile metadata;
4. normalizes name, email, phone and selected document;
5. inserts one same-ID profile, omitting `active`;
6. propagates any failure so the Auth signup transaction is blocked/rolled back.

The trigger function is not callable by `anon` or `authenticated`. Helper validators reside in a
non-exposed schema and expose only the minimum execution needed by table checks. This behavior is
identical regardless of which client (Android or iOS) triggered the signup.

## Grants and RLS

- RLS enabled on `public.profiles`.
- All inherited table privileges revoked from `anon` and `authenticated` before granting the
  minimum.
- `anon`: no table privilege and no policy.
- `authenticated`: SELECT and INSERT only.
- No client UPDATE/DELETE policy or grant.

### Own SELECT policy

Applies only to `authenticated`; row is visible when `(select auth.uid()) = id`.

### Own INSERT policy

Applies only to `authenticated`; insert is accepted only when:

- `(select auth.uid()) = id`;
- normalized row email equals the authenticated JWT email;
- `active` resolves to true;
- all table constraints pass.

The INSERT policy exists for recovery. Normal profile creation occurs in the Auth trigger. Because
RLS is enforced by Postgres against the authenticated JWT, this protection is identical whether the
request originates from the Android app, the iOS app, or any other client holding a valid session.

## Idempotency and concurrency

- Trigger primary-key conflict fails the signup transaction; it does not overwrite a profile.
- Recovery first selects, then inserts/upserts with conflict target `id` and ignores duplicate ID.
- Recovery always selects again and confirms consistency.
- CPF/CNPJ conflicts against another ID still fail their named unique constraint.
- Parallel/repeated taps are blocked client-side (ViewModel guard, on both platforms); database
  PK/unique constraints remain the final concurrency boundary.

## Migration boundary

The complete implementation lives in one ordered migration under
`supabase/migrations/<timestamp>_create_profiles.sql` **in the Android repository**, including
schema helpers, table, constraints, trigger, grants and policies. The iOS repository does not carry
a duplicate migration file — it depends on the same remote project already provisioned by that
migration. Any future schema change MUST be authored once (in the Android repository's migration
history, or in whichever repository the team designates as the schema source of truth) and applied
to the single shared project; it must not be forked per platform.

## Required assertions

- Valid individual/company signup creates exactly one same-ID row with `active=true`.
- Trigger validation failure leaves no committed Auth identity/profile pair.
- Exactly one document is present.
- Numeric and alphanumeric valid CNPJs pass; invalid DVs fail.
- Duplicate normalized email/CPF/CNPJ fails without changing existing data.
- Authenticated users see/insert only their own row; cross-user and anonymous access is denied.
- Recovery of an absent own profile converges to one row under repeated calls.
- All of the above hold identically whether exercised from the Android app, the iOS app, or a
  direct authenticated REST call.
