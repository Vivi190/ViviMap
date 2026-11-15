# TestFlight setup (without a Mac)

**Status:** set up on 2026-11-13.

| Item | Value |
|---|---|
| Bundle ID | `com.vivimap.atlas` |
| App Store Connect app | "Atlas Navigasyon" |
| Distribution certificate | Valid until 2027-11-13 |
| TestFlight internal group | One group; the account holder is its tester |

Signing files exist only in a local folder outside the repository (which must be backed up) and in GitHub Secrets; `.gitignore` keeps them out of the repository.

## Uploading a build

```bash
gh workflow run testflight.yml -R Vivi190/ViviMap
gh run watch -R Vivi190/ViviMap
```

After Apple processes it (usually a few minutes), the build appears in TestFlight on the iPhone. Internal testing needs no Beta App Review.

## GitHub Actions and the public repository

The repository has been public since 2026-11-14. While private, macOS minutes counted tenfold and GitHub Free's 2,000 monthly minutes ran out overnight. Standard runners are free for public repositories.

| Job | Duration |
|---|---|
| CI (build, unit and UI tests) | ~17 min |
| TestFlight upload | ~6 min |

Rules for a public repository:

- **Logs are public.** Workflows never print a secret, its length or hash, or the signing identity (which contains the developer's name). Old TestFlight logs were deleted before going public.
- **No secrets in code or history.** Keys and certificates live in GitHub Secrets. The full history was scanned before going public; commits carry only GitHub's noreply email.
- **No HERE data in the repository.** HERE's terms restrict redistributing its content. Test fixtures are synthetic; two recorded HERE responses were removed from history. OSM data is free to use with ODbL attribution.

Pre-rewrite commits may stay visible for a while, to anyone who knows their old IDs, via old Actions run pages and the PR #1 timeline. Asking GitHub Support to purge the cache removes them completely.

## How it was set up

Only two steps were manual, in Apple's web interface; [Tools/appstore/provision.mjs](../Tools/appstore/provision.mjs) did the rest through the App Store Connect API.

1. The key and CSR were generated locally:
   ```bash
   MSYS_NO_PATHCONV=1 openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr -subj "/CN=Atlas Distribution/C=TR"
   ```
2. An API key "Atlas CI" with the **Admin** role was created in App Store Connect under **Users and Access → Integrations → Team Keys**; its `.p8` file went into the local signing folder.
3. The script created the Bundle ID, the certificate (from the CSR) and the App Store profile:
   ```bash
   node Tools/appstore/provision.mjs --key <signing-dir>/AuthKey_<KEYID>.p8 --issuer <ISSUER_ID> \
     --csr <signing-dir>/dist.csr --out <signing-dir> --steps bundle,cert,profile
   ```
4. The app record was created on the web under **Apps → New App**; the API does not offer this.
5. With `--steps testflight`, the script created the internal group and added the account holder to it.
6. The certificate was converted to a .p12 with legacy algorithms, and 6 secrets were uploaded:
   - `DIST_P12_BASE64`, `DIST_P12_PASSWORD`
   - `PROFILE_BASE64`
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`

## Live traffic key (optional)

Without a HERE key the build has no traffic; the route card says "Trafik dahil değil" (traffic not included). To add the key:

1. https://platform.here.com → **Access Manager → Apps → Register new app** → **Credentials → API Keys → Create API key**.
2. Store the key as a GitHub Secret: `gh secret set HERE_API_KEY -R Vivi190/ViviMap` (the command prompts for the value, so it never lands in code or the repository).
3. Upload a new TestFlight build. The build writes the key into Info.plist.

Quota: at most 1,200 route imports and 2,400 traffic flow requests per device per month (under half of HERE's free quota).

## Annual renewal (when the certificate expires)

Repeat steps 3 and 6. No new CSR is needed: reuse `dist.csr`.

## Pitfalls

- **OpenSSL output on Windows ends in CRLF.** Strip it with `tr -d '\r\n'` when generating the password: an invisible trailing `\r` stays in the password that encrypts the .p12, but `gh secret set` trims it on upload, and CI fails with "passphrase not correct".
- In Git Bash, OpenSSL cannot take a path in `file:/c/...` form; pass the password via `env:` or `stdin`.
- Workflow logs are public, so the "Check secrets" step names only missing secrets, with no length or hash, and the signing identity (the developer's name) is never logged. To check a suspect secret, compare it locally; never print it to the log.
