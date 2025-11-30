## ADDED Requirements
### Requirement: Tenant resolution without host subdomains
Tenant resolution in pro edition SHALL derive the tenant from request path params (`tenant_slug`/`tenant`), query params (`tenant`), or a previously stored session tenant id; the system SHALL NOT attempt host/subdomain-based slug lookup when choosing a tenant.

#### Scenario: Resolution priority
- **WHEN** both a path/query tenant param and a session tenant exist
- **THEN** the path/query tenant slug takes precedence
- **AND** the chosen tenant id replaces the session tenant for subsequent requests

#### Scenario: Resolve tenant from params or session
- **WHEN** a request includes a `tenant_slug` path param or `tenant` query param
- **THEN** the system selects the matching tenant and stores its id in the session
- **AND** subsequent requests without tenant params reuse the stored tenant without emitting host-based warnings

#### Scenario: Reject invalid tenant slug
- **WHEN** a tenant param is present but fails validation or lookup
- **THEN** the system logs a warning describing the invalid slug
- **AND** falls back to the default tenant without trying host-derived slugs
- **AND** the resolved tenant is persisted to session so subsequent requests stay consistent

#### Scenario: Ignore host subdomain
- **WHEN** a request arrives on `www.example.com` (or any host prefix) with no tenant params
- **AND** a tenant id already exists in session
- **THEN** the session tenant is used and no host-derived slug lookup or warning occurs

#### Scenario: Default tenant fallback
- **WHEN** no tenant params are present and no tenant session is set
- **THEN** the system selects the default tenant
- **AND** logs a single warning about missing tenant identifiers without trying subdomain resolution or emitting multiple messages for the same request
- **AND** the warning explicitly notes the absence of tenant params/session rather than a host-derived slug
- **AND** the chosen default tenant id is stored in session for stability on subsequent requests

### Requirement: Tenant-scoped audio broadcasts
Audio playback success and error broadcasts MUST include a tenant id so messages are sent on tenant-specific PubSub topics; tenant defaults MAY only be used when the default tenant initiated the action.

#### Scenario: Error broadcast reaches caller's tenant
- **WHEN** a user on tenant B triggers a playback error (e.g., bot not connected or failed reconnect)
- **THEN** the AudioPlayer broadcast includes tenant B's id and publishes on tenant B's soundboard topic, not the default tenant topic
- **AND** no duplicate broadcast is sent to any legacy or default-only topic

#### Scenario: Stop-sound broadcast stays tenant-bound
- **WHEN** a stop request is issued from tenant C via UI or API
- **THEN** the success/error broadcast uses tenant C's id so only tenant C subscribers receive the message
- **AND** no broadcast is emitted on legacy or cross-tenant topics

### Requirement: Edition-aware authentication
Community edition deployments MUST allow basic auth or bearer API tokens to authorize web/API requests without forcing Discord OAuth, while pro edition MUST continue requiring tenant-scoped users after any API token check.

#### Scenario: Community basic auth bypasses OAuth
- **WHEN** a community deployment receives a request with valid basic auth or a valid bearer token
- **THEN** the request is accepted without a Discord OAuth redirect
- **AND** the resolved tenant (from params or session) is persisted in session for subsequent requests

#### Scenario: Pro users remain tenant-scoped
- **WHEN** a pro deployment authenticates a user (via session or verified API token)
- **THEN** the user record must belong to the same tenant that was resolved from params or session
- **AND** a mismatch clears the session and falls back to default tenant resolution rather than trusting host subdomains

#### Scenario: Legacy API token in community sets tenant
- **WHEN** a community deployment receives a bearer token matching the legacy `API_TOKEN`
- **THEN** the request is authorized without OAuth
- **AND** the tenant stored in session remains unchanged (or defaults once) so subsequent requests keep the same tenant without host-based lookups
- **AND** the token does not override an explicitly chosen tenant param

#### Scenario: Pro API tokens are tenant-bound
- **WHEN** a pro deployment receives a bearer token issued to tenant D
- **THEN** the token is accepted only if the resolved tenant (params or session) is also tenant D (or absent and then set to D)
- **AND** a tenant mismatch rejects the token, clears the session user, and does not rely on host subdomains for recovery
