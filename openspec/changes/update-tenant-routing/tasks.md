## 1. Tenant resolution
- [ ] 1.1 Update tenant plug to drop host-based slug resolution and document lookup order
- [ ] 1.2 Persist resolved tenant in session without fallback churn/warnings

## 2. PubSub scoping
- [ ] 2.1 Propagate tenant ids on AudioPlayer success/error broadcasts (stop/play/reconnect paths)
- [ ] 2.2 Add regression coverage for multi-tenant error broadcasts

## 3. Auth and edition behavior
- [ ] 3.1 Ensure community edition honors basic auth/API tokens without forcing Discord OAuth
- [ ] 3.2 Keep pro edition tenant-scoped user lookup intact

## 4. Validation
- [ ] 4.1 Run `mix test` (or focused suites) and ensure specs align with implementation
