# Change: Align tenant resolution with single-domain deployments

## Why
Host-based slug resolution emits false warnings and selects the default tenant when the app runs on a single hostname (app.soundbored.app), causing noisy logs and inconsistent tenant assignments. Audio error broadcasts also drop tenant context, so non-default tenants miss critical UI errors.

## What Changes
- Remove host/subdomain lookup from the tenant resolution chain; rely on path/query params and session for tenant selection.
- Ensure all AudioPlayer success/error broadcasts carry the caller's tenant id so PubSub topics stay tenant-scoped.
- Document community vs pro authentication expectations (community allows basic auth/API tokens before Discord OAuth; pro requires tenant-scoped users).

## Impact
- Affected specs: tenancy
- Affected code: tenant plug, audio player broadcasts, auth/router
