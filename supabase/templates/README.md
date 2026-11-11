# Email templates

Copies of the eight auth emails Supabase can send for this project. The dashboard is where they actually run
from; these files keep the wording versioned with the app so a dashboard reset does not lose it.
`supabase/config.toml` points at the six standard ones, so `supabase config push` also sends them.

To set one by hand: Dashboard → Authentication → Emails → the page below, paste the HTML into **Body** and the
subject into **Subject**, then Save. Each file's opening comment repeats the page, the subject and the variables.

## Action emails

Sent because someone asked for something. All carry a link.

| File | Dashboard page | Subject | Used by the app |
| --- | --- | --- | --- |
| `reset_password.html` | Reset password | Atur ulang kata sandi FinDesk | Yes, "Lupa password?" on the login page |
| `change_email_address.html` | Change email address | Konfirmasi perubahan alamat email FinDesk | When an email is changed |
| `invite_user.html` | Invite user | Undangan bergabung ke FinDesk | No, only the dashboard's Invite button |
| `confirm_sign_up.html` | Confirm sign up | Konfirmasi akun FinDesk Anda | No, Admin creates accounts pre-confirmed |
| `magic_link_or_otp.html` | Magic link or OTP | Tautan masuk FinDesk | No, password and Google only |

## Notifications

Sent after the fact, nothing to do. Deliberately link-free.

| File | Dashboard page | Subject |
| --- | --- | --- |
| `password_changed.html` | Security → Password changed (turn the toggle on) | Kata sandi FinDesk Anda telah diubah |
| `email_address_changed.html` | Security → Email address changed (turn the toggle on) | Alamat email akun FinDesk Anda telah diubah |

## Codes

| File | Dashboard page | Subject |
| --- | --- | --- |
| `reauthentication.html` | Reauthentication | Kode verifikasi FinDesk |

## Why

- **Unused flows are branded anyway.** Invite, confirm sign-up and magic link fire the moment someone enables
  them or presses the dashboard's Invite button, and the default English template reads like phishing.
- **Notifications have no link.** An account-security email that asks you to click something is exactly what a
  phisher sends; these say what happened and point to the finance admin instead.
- **The reset link stays on our domain.** `reset_password.html` builds `{{ .SiteURL }}/reset-password?token_hash=…`
  instead of `{{ .ConfirmationURL }}` (which points at `*.supabase.co`), and `ResetPasswordPage.vue` trades the
  token for a session with `verifyOtp`. Mail from our domain linking to another domain gets flagged as phishing.
  The other action emails keep `ConfirmationURL` because the app has no landing page to exchange their tokens.
- **No images.** The logo is a table cell, not a picture, so nothing breaks before the app is deployed and
  Gmail never hides it.

The remaining Security toggles (phone, linked sign-in methods, MFA) stay off: nothing in the app can trigger them.
