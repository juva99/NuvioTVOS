# Trakt proxy

This Edge Function backs the tvOS Trakt login flow without shipping the Trakt
client secret in the app.

## Secrets

Set these in the Supabase/Nuvio backend project:

```sh
supabase secrets set \
  TRAKT_CLIENT_ID="your_trakt_client_id" \
  TRAKT_CLIENT_SECRET="your_trakt_client_secret" \
  TRAKT_API_URL="https://api.trakt.tv" \
  TRAKT_REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
```

## Deploy

The tvOS app currently calls this function with the Nuvio publishable key, not a
user JWT, so deploy it without JWT verification:

```sh
supabase functions deploy trakt --no-verify-jwt
```

Run this from the repo root so Supabase can find
`supabase/functions/trakt/index.ts`. The helper script does the same:

```sh
./scripts/deploy_trakt_function.sh
```

After deploy, tvOS calls:

```text
https://api.nuvio.tv/functions/v1/trakt
```

Quick boot check:

```sh
curl -i https://api.nuvio.tv/functions/v1/trakt
```

If the function is deployed correctly, that should return JSON instead of
`InvalidWorkerCreation`.

## Account restore

tvOS first tries:

```text
GET /functions/v1/trakt/account/session
```

If the Nuvio backend stores Trakt tokens per signed-in Nuvio user, return:

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "bearer",
  "expires_in": 7776000,
  "created_at": 1760000000,
  "username": "trakt_user",
  "user_slug": "trakt-user"
}
```

If the backend does not have an account-level Trakt session, return `404`.
tvOS will then fall back to starting a normal Trakt device-code login.
