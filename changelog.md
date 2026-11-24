# Changelog

## 0.0.11 (2026-11-24)

### Changes
- Require the Cato provider `>= 2.0.0` (now GA on the Terraform Registry).
- README: replaced the early-access/beta provider notice with a GA notice.

## 0.0.10 (2026-11-04)

### Features
- Sub-policy support (parity with bulk-if-rules): `cato_wf_sub_policy` with embedded
  API-created cleanup rule, `cato_wf_rule.sub_rules` (keyed `<sub_policy_name>::<rule_name>`),
  scope rows ordered via `cato_bulk_wf_move_rule`, shared `rule_bodies` local across
  main/sub/cleanup rules. New outputs: `sub_policy_ids`, `sub_policy_scope_rule_ids`,
  `sub_rule_ids`, `cleanup_rule_ids`, `unmanaged_sub_sections`, `unordered_sub_policies`,
  `unordered_sub_policy_rules`. Legacy (flat) JSON exports are unaffected.
- Requires provider >= 1.3.1 (cato_wf_sub_policy cleanup_rule embed + input-only `at`)
  and `catocli export wf_rules` with sub-policy support.
- Added `allow_empty_policy` safety guard — planning fails when the policy
  JSON contains 0 rules unless explicitly allowed, protecting against
  truncated or wrong-tenant exports mass-destroying a live policy.
- README: brownfield import documentation now covers two options — native
  Terraform `import` blocks (recommended, declarative/previewable) and the
  `catocli import wf_rules_to_tf` imperative alternative.

## 0.0.1 (2025-07-05)

### Features
- Initial bulk wf rule module release

## 0.0.2 (2025-07-12)

### Features
- Fixing versions syntax to point to published provider

## 0.0.4 (2025-07-15)

### Features
- Refactor section data to sort and index by name to support reordering of source json without error
- Updated versions file to reference published provider

## 0.0.5 (2025-07-23)

### Features
- Fixed state management issues with name to id mapping

## 0.0.6 (2025-10-28)

### Features
- Fixed tracking.alert parsing and device_attributes

## 0.0.8 (2025-11-01)

### Features
- Updated required cato provider to 49 and TF version to >= 1.13

## 0.0.9 (2025-11-03)

### Features
- Updated import logic around customService with portrange, and subnet inpur params
