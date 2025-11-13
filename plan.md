## Implementation Plan: Per-Domain Key Type Selection

### Overview
Add `domain_key_types_for_domain` callback to allow per-domain certificate type selection while maintaining backward compatibility.

### Requirements Summary
- Lambda takes domain name, returns array of key types for that domain
- Returned types must be subset of global `domain_key_types` (validated)
- **Lookup**: Check storage for ALL global types (backward compat)
- **Generation**: Only create certificates for per-domain types
- **Serving**: Prefer per-domain types in their returned order, fallback to any available
- **Renewal**: Continue renewing ALL existing certificates (independent of per-domain config)
- **Validation**: If ANY invalid type returned, log error and use global as fallback
- **Nil/empty**: Use global `domain_key_types` as default

### Changes to `lib/resty/acme/autossl.lua`

#### 1. **Add Configuration Option**
Location: ~line 36 in `default_config`

Add new optional configuration field `domain_key_types_for_domain` that accepts a function callback.

**Verification** (autossl.t):
- Test init succeeds with `domain_key_types_for_domain = nil` (default)
- Test init succeeds with valid function
- Test init fails with error if value is not a function (string, number, table)

---

#### 2. **Cache Callback in Module Variable**
Location: ~line 77 alongside other module-level vars

Declare module-level variable to cache the callback for use during requests.

**Verification** (code inspection):
- Read autossl.lua lines ~75-80
- Confirm variable exists alongside `domain_key_types`, `domain_whitelist`, etc.

---

#### 3. **Validate and Cache Callback**
Location: ~line 514 in `init()` function, after `failure_cooloff_callback` validation

Validate that if provided, `domain_key_types_for_domain` is a function, then cache it in the module variable.

**Verification** (autossl.t):
- Test with `domain_key_types_for_domain = "not a function"` → expect error message
- Test with `domain_key_types_for_domain = 123` → expect error message
- Test with `domain_key_types_for_domain = {}` → expect error message

---

#### 4. **Create Helper Function `get_domain_key_types(domain)`**
Location: After line ~426, before `AUTOSSL.init()`

Create a helper function that:
- Returns global `domain_key_types` if no callback is configured
- Calls the callback with the domain name
- Returns global `domain_key_types` if callback returns nil, non-table, or empty table
- Validates all returned types exist in global `domain_key_types`
- Logs error and returns global `domain_key_types` if validation fails
- Returns the per-domain types if validation passes

**Verification** (autossl.t - unit-style tests):
- Test: callback returns `nil` → should return global types
- Test: callback returns `{}` → should return global types
- Test: callback returns `{"invalid_type"}` when global is `{"rsa", "ecc"}` → should log error and return global types
- Test: callback returns `{"ecc"}` when global is `{"rsa", "ecc"}` → should return `{"ecc"}`
- Test: callback returns `{"ecc", "rsa"}` when global is `{"rsa", "ecc"}` → should return `{"ecc", "rsa"}` (respects order)

---

#### 5. **Modify Certificate Lookup & Serving Logic**
Location: Lines ~630-654 in `ssl_certificate()` function

Replace current inline certificate lookup/serving with multi-phase approach:

**Phase 1 - Lookup**: Look up certificates for ALL global `domain_key_types` from storage, store in a lookup table (for backward compatibility - existing certs must be found regardless of current per-domain preferences).

**Phase 2 - Get Preferences**: Call `get_domain_key_types(domain)` to get preferred types for this domain.

**Phase 3 - Serve Preferred**: Iterate through preferred types in order, serve any available certificates from the lookup table. Mark served certificates.

**Phase 4 - Serve Fallback**: Iterate through global types, serve any remaining unserved certificates from the lookup table.

**Verification** (e2e.t):
- Test: `domain_key_types = {"rsa", "ecc"}`, callback returns `{"ecc"}`, storage has both RSA and ECC
  - Should serve ECC first (preferred), then RSA (fallback)
  - Client with ECC support should receive ECC cert
- Test: `domain_key_types = {"rsa", "ecc"}`, callback returns `{"rsa"}`, storage has both
  - Should serve RSA first (preferred), then ECC (fallback)
  - Verify via nginx debug logs showing order
- Test: callback returns `nil`, storage has both
  - Should serve in global order (RSA, then ECC)

---

#### 6. **Modify Certificate Generation Logic**
Location: Lines ~656-683 in `ssl_certificate()` function

Replace current generation logic:

**Determine Missing Types**: Call `get_domain_key_types(domain)` to get preferred types. Check which preferred types are missing from storage (not served because they don't exist).

**Generate Only Missing Preferred Types**: Only trigger certificate generation for the missing preferred types, not all global types.

**Handle Blocking Mode**: If blocking mode is enabled, immediately load and serve newly generated certificates following the same serving preference order.

Note: Fix bug in current code where `domain_key_types_count` is compared to `chains_set` (should be `chains_set_count`).

**Verification** (e2e.t):
- Test: `domain_key_types = {"rsa", "ecc"}`, callback returns `{"ecc"}`, storage is empty
  - Should ONLY generate ECC cert
  - Verify storage contains only `domain:ecc:example.com`, NOT `domain:rsa:example.com`
- Test: `domain_key_types = {"rsa", "ecc"}`, callback returns `{"rsa", "ecc"}`, storage is empty
  - Should generate both RSA and ECC
- Test: `domain_key_types = {"rsa", "ecc"}`, callback returns `nil` (uses global), storage is empty
  - Should generate both RSA and ECC (fallback behavior)
- Test: `domain_key_types = {"rsa", "ecc"}`, callback returns `{"ecc"}`, storage has RSA but not ECC
  - Should NOT generate RSA (already exists)
  - Should generate ECC (preferred but missing)
  - After generation, serves ECC first, RSA second
- Test: blocking mode with callback returning `{"ecc"}`
  - Should generate ECC synchronously and serve immediately

---

#### 7. **Keep Renewal Unchanged**
Location: Lines ~328-395 in `check_renew()` function

No changes needed. The renewal logic already:
- Lists all certificates from storage (using prefix scan)
- Reads the `type` field from each stored certificate
- Renews based on the stored type
- Operates independently of per-domain preferences

**Verification** (e2e.t - longer running test):
- Test: Storage has RSA cert (created when callback returned `{"rsa"}`) and ECC cert (created when callback returned `{"ecc"}`)
  - Change callback to return `{"ecc"}` only
  - Simulate time passing and certs approaching expiration (mock cert expiration or lower `renew_threshold`)
  - Both RSA and ECC certs should be renewed
  - Verify renewal logs show both types being renewed
  - Verify storage updated timestamp for both certificate types

---

### End-to-End Integration Test
Location: e2e.t

Full workflow test:
1. Configure `domain_key_types = {"rsa", "ecc"}`
2. Set callback to return `{"rsa"}` for `test1.com`, `{"ecc"}` for `test2.com`
3. Request `test1.com` → generates only RSA cert, verify via storage
4. Request `test2.com` → generates only ECC cert, verify via storage
5. Update callback to return `{"ecc"}` for `test1.com`
6. Request `test1.com` → serves existing RSA (fallback), generates ECC (preferred), verify both served
7. Verify client receives certs in preference order
8. Simulate cert expiration → verify renewal continues for all existing certs regardless of callback

---

### Test File Organization

**t/autossl.t** (unit-style/config tests):
- Configuration validation (steps 1, 3)
- Helper function behavior (step 4)
- Invalid callback responses

**t/e2e.t** (integration tests):
- Certificate generation with per-domain preferences (step 6)
- Certificate serving order (step 5)
- Certificate renewal independence (step 7)
- End-to-end workflow

---

### Documentation Updates

#### 8. **Update README.md**

**Section: Synopsis (around line 86-99)**

Add example demonstrating the new `domain_key_types_for_domain` callback in the basic configuration example. Position after the `domain_key_types` comment.

Example to add:
```lua
-- per-domain certificate type selection (optional)
-- domain_key_types_for_domain = function(domain)
--     if domain == "modern.example.com" then
--         return { 'ecc' }  -- ECC only for modern clients
--     elseif domain == "legacy.example.com" then
--         return { 'rsa' }  -- RSA only for legacy clients
--     end
--     -- return nil to use global domain_key_types
-- end,
```

**Verification**:
- Read README.md lines 86-99
- Confirm example is present and correctly formatted
- Ensure it's positioned logically after `domain_key_types` configuration

---

**Section: Advanced Usage (new subsection after line 219)**

Add new subsection titled "### Per-Domain Certificate Type Selection" after the "Define failure cooloff period" section (around line 219).

Content should explain:
- Purpose: Customize which certificate types to generate/serve per domain
- Function signature: `function(domain) -> { 'rsa' } | { 'ecc' } | { 'rsa', 'ecc' } | nil`
- Behavior:
  - Returned types must be a subset of global `domain_key_types`
  - Return `nil` or empty table to use global `domain_key_types`
  - Invalid types are logged and fallback to global config
  - Return order determines serving preference
- Lookup: All global types are checked in storage (backward compatibility)
- Generation: Only generates missing types from the per-domain preference
- Serving: Prefers per-domain types in returned order, then fallback to any other available
- Renewal: All existing certificates continue to renew regardless of callback

Include example use cases:
1. Modern vs legacy domain split (ECC for new domains, RSA for old)
2. Performance-sensitive domains (ECC only)
3. Compatibility-first domains (RSA only)
4. Dynamic selection based on external criteria (database, config service)

**Verification**:
- Read README.md around line 220-240
- Confirm new subsection exists with title and complete explanation
- Ensure examples are practical and clear
- Check that behavior details match implementation

---

**Section: resty.acme.autossl config table (around line 417-475)**

Add new configuration option in the default config block at appropriate position (after `domain_key_types` around line 437).

Entry to add:
```lua
  -- function to select certificate types per domain
  -- must return a subset of domain_key_types or nil
  domain_key_types_for_domain = nil,
```

**Verification**:
- Read README.md lines 417-475
- Confirm new entry exists in config table
- Positioned logically after `domain_key_types`
- Comment accurately describes the option

---

#### 9. **Update CHANGELOG.md**

**Section: Top of file (unreleased changes)**

Add entry under appropriate version section (or create "Unreleased" section if needed).

Entry should describe:
- Feature: Add `domain_key_types_for_domain` callback for per-domain certificate type selection
- Allows customizing which certificate types (RSA/ECC) to generate and prefer per domain
- Maintains backward compatibility: all existing certificates in storage continue to be served and renewed
- Invalid callback responses fallback gracefully to global `domain_key_types`

**Verification**:
- Read CHANGELOG.md top section
- Confirm new entry exists with clear description
- Follows existing CHANGELOG format/style

---

### Documentation Test Coverage

After documentation updates, verify:
- All new configuration options are documented in both Synopsis and config reference
- Advanced usage section provides clear examples for common use cases
- Behavior is explained comprehensively (lookup, generation, serving, renewal)
- Backward compatibility guarantees are clearly stated
- Examples are tested to ensure they work as documented

