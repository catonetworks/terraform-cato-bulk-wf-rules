locals {
  wf_rules_json          = jsondecode(file("${var.wf_rules_json_file_path}"))
  wf_rules_data          = local.wf_rules_json.data.policy.wanFirewall.policy.rules
  sections_data_unsorted = local.wf_rules_json.data.policy.wanFirewall.policy.sections
  rules_in_sections_data = local.wf_rules_json.data.policy.wanFirewall.policy.rules_in_sections
  sub_policies_data_raw  = try(local.wf_rules_json.data.policy.wanFirewall.policy.sub_policies, [])

  # ───────────────────────────────────────────────────────────────────────
  # Backward-compatible split (same design as bulk-if-rules /
  # ifw-sub-policy-json-design.md). Legacy files have no sub_policies key and
  # no sub_policy_name/entry_type anywhere, so every try() below defaults to
  # "main policy" / "rule" and this split is a no-op.
  # ───────────────────────────────────────────────────────────────────────

  main_sections_unsorted = [for s in local.sections_data_unsorted : s if try(s.sub_policy_name, null) == null]
  sub_sections_unsorted  = [for s in local.sections_data_unsorted : s if try(s.sub_policy_name, null) != null]

  # Create a map with section_index as key to sort sections correctly
  sections_by_index = {
    for section in local.main_sections_unsorted :
    tostring(section.section_index) => section
  }
  # Sort sections by section_index to ensure consistent ordering regardless of JSON file order
  sections_data_list = [
    for index in sort(keys(local.sections_by_index)) :
    local.sections_by_index[index]
  ]
  sections_data = {
    for section in local.sections_data_list :
    section.section_name => section
  }

  # Sub-sections: NOT managed by this module yet (cato_wf_section has no
  # sub-policy parenting) — exposed via the unmanaged_sub_sections output only.
  sub_sections_data = {
    for s in local.sub_sections_unsorted :
    "${s.sub_policy_name}::${s.section_name}" => s
  }

  main_rules_data = [for r in local.wf_rules_data : r if try(r.sub_policy_name, null) == null]
  sub_rules_data  = [for r in local.wf_rules_data : r if try(r.sub_policy_name, null) != null]

  sub_policies_data = {
    for sp in local.sub_policies_data_raw :
    sp.sub_policy_name => sp
  }

  sub_policy_parent_section = {
    for row in local.rules_in_sections_data :
    row.sub_policy_name => row.section_name
    if try(row.entry_type, "rule") == "sub_policy"
  }

  # Move rows for cato_bulk_wf_move_rule: plain main-policy rows plus
  # sub-policy scope rows remapped to rule-shaped rows (scope rows ARE rules
  # in the live index). Rows ordering a rule INSIDE a sub-policy are excluded
  # (no provider support yet) and surfaced via unordered_sub_policy_rules.
  main_policy_rule_rows = [for row in local.rules_in_sections_data : row if try(row.sub_policy_name, null) == null]
  sub_policy_scope_move_rows = [
    for row in local.rules_in_sections_data : {
      index_in_section = row.index_in_section
      section_name     = row.section_name
      rule_name        = row.sub_policy_name
    }
    if try(row.entry_type, "rule") == "sub_policy" && contains(keys(local.sections_data), row.section_name)
  ]
  rules_data = concat(local.main_policy_rule_rows, local.sub_policy_scope_move_rows)

  unordered_sub_policies_data = [
    for row in local.rules_in_sections_data : row
    if try(row.entry_type, "rule") == "sub_policy" && !contains(keys(local.sections_data), row.section_name)
  ]
  unordered_sub_policy_rules_data = [
    for row in local.rules_in_sections_data : row
    if try(row.sub_policy_name, null) != null && try(row.entry_type, "rule") == "rule"
  ]

  # Cleanup rules ride along in sub_policies[].cleanup_rule (the API
  # auto-creates one per sub-policy; cato_wf_sub_policy embeds and manages
  # it). Their entry shape matches rules[], so they share rule_bodies.
  cleanup_rule_entries = [
    for sp in local.sub_policies_data_raw : sp.cleanup_rule
    if try(sp.cleanup_rule, null) != null
  ]

  # Shared rule-body construction: main rules, sub-rules and cleanup rules
  # carry the same rules[] entry shape, keyed by (globally unique) rule name.
  rule_bodies = {
    for entry in concat(local.main_rules_data, local.sub_rules_data, local.cleanup_rule_entries) :
    entry.rule.name => merge(
      {
        name      = entry.rule.name
        enabled   = entry.rule.enabled
        action    = entry.rule.action
        direction = entry.rule.direction
        # Always include tracking block with defaults
        tracking = {
          alert = merge(
            {
              enabled   = try(entry.rule.tracking.alert.enabled, false)
              frequency = try(entry.rule.tracking.alert.frequency, "IMMEDIATE")
            },
            # Only include webhook if it exists and is not empty
            try(length(entry.rule.tracking.alert.webhook), 0) > 0 ? {
              webhook = [for hook in entry.rule.tracking.alert.webhook : can(hook.name) ? { name = hook.name } : { id = hook.id }]
            } : {},
            # Only include mailing_list if it exists and is not empty
            try(length(entry.rule.tracking.alert.mailingList), 0) > 0 ? {
              mailing_list = [for list in entry.rule.tracking.alert.mailingList : can(list.name) ? { name = list.name } : { id = list.id }]
            } : {},
            # Only include subscription_group if it exists and is not empty
            try(length(entry.rule.tracking.alert.subscriptionGroup), 0) > 0 ? {
              subscription_group = [for group in entry.rule.tracking.alert.subscriptionGroup : can(group.name) ? { name = group.name } : { id = group.id }]
            } : {}
          )
          event = {
            enabled = try(entry.rule.tracking.event.enabled, true)
          }
        }
      },

      # Only include description if it's not empty
      entry.rule.description != "" ? {
        description = entry.rule.description
      } : {},

      # Only include connection_origin if it exists
      try(entry.rule.connectionOrigin, null) != null ? {
        connection_origin = entry.rule.connectionOrigin
      } : {},

      # Only include device_os if it exists and is not empty
      try(length(entry.rule.deviceOS), 0) > 0 ? {
        device_os = entry.rule.deviceOS
      } : {},

      # Only include country if it exists and is not empty
      try(length(entry.rule.country), 0) > 0 ? {
        country = [for country in entry.rule.country : can(country.name) ? { name = country.name } : { id = country.id }]
      } : {},

      # Only include device if it exists and is not empty
      try(length(entry.rule.device), 0) > 0 ? {
        device = [for device in entry.rule.device : can(device.name) ? { name = device.name } : { id = device.id }]
      } : {},

      # device_attributes: export keys are camelCase (osVersion) while the
      # provider uses os_version, so map each one explicitly. Empty lists -> null.
      length(flatten([for v in values(try(entry.rule.deviceAttributes, {})) : try(v, [])])) > 0 ? {
        device_attributes = {
          category     = length(try(entry.rule.deviceAttributes.category, [])) > 0 ? entry.rule.deviceAttributes.category : null
          manufacturer = length(try(entry.rule.deviceAttributes.manufacturer, [])) > 0 ? entry.rule.deviceAttributes.manufacturer : null
          model        = length(try(entry.rule.deviceAttributes.model, [])) > 0 ? entry.rule.deviceAttributes.model : null
          os           = length(try(entry.rule.deviceAttributes.os, [])) > 0 ? entry.rule.deviceAttributes.os : null
          os_version   = length(try(entry.rule.deviceAttributes.osVersion, [])) > 0 ? entry.rule.deviceAttributes.osVersion : null
          type         = length(try(entry.rule.deviceAttributes.type, [])) > 0 ? entry.rule.deviceAttributes.type : null
        }
      } : {},

      # Dynamic source block - include if source exists (even if empty)
      try(entry.rule.source, null) != null ? {
        source = {
          for k, v in {
            ip          = try(length(entry.rule.source.ip), 0) > 0 ? entry.rule.source.ip : null
            host        = try(length(entry.rule.source.host), 0) > 0 ? [for host in entry.rule.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
            site        = try(length(entry.rule.source.site), 0) > 0 ? [for site in entry.rule.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
            users_group = try(length(entry.rule.source.usersGroup), 0) > 0 ? [for group in entry.rule.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
            subnet      = try(length(entry.rule.source.subnet), 0) > 0 ? entry.rule.source.subnet : null
            ip_range = try(length(entry.rule.source.ipRange), 0) > 0 ? [for range in entry.rule.source.ipRange : {
              from = range.from
              to   = range.to
            }] : null
            network_interface   = try(length(entry.rule.source.networkInterface), 0) > 0 ? [for ni in entry.rule.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
            floating_subnet     = try(length(entry.rule.source.floatingSubnet), 0) > 0 ? [for subnet in entry.rule.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
            site_network_subnet = try(length(entry.rule.source.siteNetworkSubnet), 0) > 0 ? [for subnet in entry.rule.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
            system_group        = try(length(entry.rule.source.systemGroup), 0) > 0 ? [for group in entry.rule.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
            group               = try(length(entry.rule.source.group), 0) > 0 ? [for group in entry.rule.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
            user                = try(length(entry.rule.source.user), 0) > 0 ? [for user in entry.rule.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
            global_ip_range     = try(length(entry.rule.source.globalIpRange), 0) > 0 ? [for range in entry.rule.source.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
          } : k => v if v != null
        }
      } : {},

      # Application block - always required for WAN Firewall rules
      {
        application = {
          for k, v in {
            app_category = try(length(entry.rule.application.appCategory), 0) > 0 ? [for cat in entry.rule.application.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

            application = try(length(entry.rule.application.application), 0) > 0 ? [for app in entry.rule.application.application : can(app.name) ? { name = app.name } : { id = app.id }] : null

            custom_app = try(length(entry.rule.application.customApp), 0) > 0 ? [for app in entry.rule.application.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null

            custom_category = try(length(entry.rule.application.customCategory), 0) > 0 ? [for cat in entry.rule.application.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

            sanctioned_apps_category = try(length(entry.rule.application.sanctionedAppsCategory), 0) > 0 ? [for cat in entry.rule.application.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

            domain = try(length(entry.rule.application.domain), 0) > 0 ? entry.rule.application.domain : null

            fqdn = try(length(entry.rule.application.fqdn), 0) > 0 ? entry.rule.application.fqdn : null

            ip = try(length(entry.rule.application.ip), 0) > 0 ? entry.rule.application.ip : null

            subnet = try(length(entry.rule.application.subnet), 0) > 0 ? entry.rule.application.subnet : null

            ip_range = try(length(entry.rule.application.ipRange), 0) > 0 ? [for range in entry.rule.application.ipRange : {
              from = range.from
              to   = range.to
            }] : null

            global_ip_range = try(length(entry.rule.application.globalIpRange), 0) > 0 ? [for range in entry.rule.application.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
          } : k => v if v != null
        }
      },

      # Dynamic destination block - only if destination has content
      {
        destination = {
          for k, v in {
            app_category = try(length(entry.rule.destination.appCategory), 0) > 0 ? [for cat in entry.rule.destination.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

            application = try(length(entry.rule.destination.application), 0) > 0 ? [for app in entry.rule.destination.application : can(app.name) ? { name = app.name } : { id = app.id }] : null

            custom_app = try(length(entry.rule.destination.customApp), 0) > 0 ? [for app in entry.rule.destination.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null

            custom_category = try(length(entry.rule.destination.customCategory), 0) > 0 ? [for cat in entry.rule.destination.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

            sanctioned_apps_category = try(length(entry.rule.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in entry.rule.destination.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

            domain = try(length(entry.rule.destination.domain), 0) > 0 ? entry.rule.destination.domain : null

            fqdn = try(length(entry.rule.destination.fqdn), 0) > 0 ? entry.rule.destination.fqdn : null

            ip = try(length(entry.rule.destination.ip), 0) > 0 ? entry.rule.destination.ip : null

            ip_range = try(length(entry.rule.destination.ipRange), 0) > 0 ? [for range in entry.rule.destination.ipRange : {
              from = range.from
              to   = range.to
            }] : null

            country = try(length(entry.rule.destination.country), 0) > 0 ? [for country in entry.rule.destination.country : can(country.name) ? { name = country.name } : { id = country.id }] : null

            remote_asn = try(length(entry.rule.destination.remoteAsn), 0) > 0 ? entry.rule.destination.remoteAsn : null

            host = try(length(entry.rule.destination.host), 0) > 0 ? [for host in entry.rule.destination.host : can(host.name) ? { name = host.name } : { id = host.id }] : null

            site = try(length(entry.rule.destination.site), 0) > 0 ? [for site in entry.rule.destination.site : can(site.name) ? { name = site.name } : { id = site.id }] : null

            users_group = try(length(entry.rule.destination.usersGroup), 0) > 0 ? [for group in entry.rule.destination.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null

            subnet = try(length(entry.rule.destination.subnet), 0) > 0 ? entry.rule.destination.subnet : null

            network_interface = try(length(entry.rule.destination.networkInterface), 0) > 0 ? [for ni in entry.rule.destination.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null

            floating_subnet = try(length(entry.rule.destination.floatingSubnet), 0) > 0 ? [for subnet in entry.rule.destination.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null

            site_network_subnet = try(length(entry.rule.destination.siteNetworkSubnet), 0) > 0 ? [for subnet in entry.rule.destination.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null

            system_group = try(length(entry.rule.destination.systemGroup), 0) > 0 ? [for group in entry.rule.destination.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null

            group = try(length(entry.rule.destination.group), 0) > 0 ? [for group in entry.rule.destination.group : can(group.name) ? { name = group.name } : { id = group.id }] : null

            user = try(length(entry.rule.destination.user), 0) > 0 ? [for user in entry.rule.destination.user : can(user.name) ? { name = user.name } : { id = user.id }] : null

            global_ip_range = try(length(entry.rule.destination.globalIpRange), 0) > 0 ? [for range in entry.rule.destination.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
          } : k => v if v != null
        }
      },

      # Dynamic service block - always include service, even if empty
      {
        service = {
          for k, v in {
            standard = try(length(entry.rule.service.standard), 0) > 0 ? [for svc in entry.rule.service.standard : can(svc.name) ? { name = svc.name } : { id = svc.id }] : null

            custom = try(length(entry.rule.service.custom), 0) > 0 ? [for svc in entry.rule.service.custom : {
              protocol = svc.protocol
              port     = try(length(svc.port), 0) > 0 ? [for p in svc.port : tostring(p)] : null
              port_range = try(svc.portRange, null) != null ? {
                from = tostring(svc.portRange.from)
                to   = tostring(svc.portRange.to)
              } : null
            }] : null
          } : k => v if v != null
        }
      },

      # Dynamic schedule block - only if custom schedules exist
      try(entry.rule.schedule.customTimeframePolicySchedule, null) != null ||
      try(entry.rule.schedule.customRecurringPolicySchedule, null) != null ||
      try(entry.rule.schedule.activeOn, "ALWAYS") != "ALWAYS" ? {
        schedule = {
          for k, v in {
            active_on        = try(entry.rule.schedule.activeOn, "ALWAYS")
            custom_timeframe = try(entry.rule.schedule.customTimeframePolicySchedule, null)
            custom_recurring = try(entry.rule.schedule.customRecurringPolicySchedule, null)
          } : k => v if v != null && (k != "active_on" || v != "ALWAYS")
        }
      } : {},

      # Dynamic exceptions block - only if exceptions exist
      try(length(entry.rule.exceptions), 0) > 0 ? {
        exceptions = [
          for exception in entry.rule.exceptions : merge(
            {
              name = exception.name
            },

            # Exception connection_origin
            try(exception.connectionOrigin, null) != null ? {
              connection_origin = exception.connectionOrigin
            } : {},

            # Exception direction
            try(exception.direction, null) != null ? {
              direction = exception.direction
            } : {},

            # Exception deviceOS
            try(length(exception.deviceOS), 0) > 0 ? {
              device_os = exception.deviceOS
            } : {},

            # Exception deviceAttributes
            length(keys(try(exception.deviceAttributes, {}))) > 0 ? {
              device_attributes = {
                for k, v in exception.deviceAttributes : k => length(v) > 0 ? v : null
              }
            } : {},

            # Exception country
            try(length(exception.country), 0) > 0 ? {
              country = [for country in exception.country : can(country.name) ? { name = country.name } : { id = country.id }]
            } : {},

            # Exception application
            length(keys(try(exception.application, {}))) > 0 ? {
              application = {
                for k, v in {
                  app_category = try(length(exception.application.appCategory), 0) > 0 ? [for cat in exception.application.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

                  application = try(length(exception.application.application), 0) > 0 ? [for app in exception.application.application : can(app.name) ? { name = app.name } : { id = app.id }] : null

                  custom_app = try(length(exception.application.customApp), 0) > 0 ? [for app in exception.application.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null

                  custom_category = try(length(exception.application.customCategory), 0) > 0 ? [for cat in exception.application.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

                  sanctioned_apps_category = try(length(exception.application.sanctionedAppsCategory), 0) > 0 ? [for cat in exception.application.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

                  domain = try(length(exception.application.domain), 0) > 0 ? exception.application.domain : null

                  fqdn = try(length(exception.application.fqdn), 0) > 0 ? exception.application.fqdn : null

                  ip = try(length(exception.application.ip), 0) > 0 ? exception.application.ip : null

                  subnet = try(length(exception.application.subnet), 0) > 0 ? exception.application.subnet : null

                  ip_range = try(length(exception.application.ipRange), 0) > 0 ? [for range in exception.application.ipRange : {
                    from = range.from
                    to   = range.to
                  }] : null

                  global_ip_range = try(length(exception.application.globalIpRange), 0) > 0 ? [for range in exception.application.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
                } : k => v if v != null
              }
            } : {},

            # Exception source - always required
            {
              source = {
                for k, v in {
                  ip                = try(length(exception.source.ip), 0) > 0 ? exception.source.ip : null
                  host              = try(length(exception.source.host), 0) > 0 ? [for host in exception.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
                  site              = try(length(exception.source.site), 0) > 0 ? [for site in exception.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
                  users_group       = try(length(exception.source.usersGroup), 0) > 0 ? [for group in exception.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
                  network_interface = try(length(exception.source.networkInterface), 0) > 0 ? [for ni in exception.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
                  ip_range = try(length(exception.source.ipRange), 0) > 0 ? [for range in exception.source.ipRange : {
                    from = range.from
                    to   = range.to
                  }] : null
                  floating_subnet     = try(length(exception.source.floatingSubnet), 0) > 0 ? [for subnet in exception.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
                  site_network_subnet = try(length(exception.source.siteNetworkSubnet), 0) > 0 ? [for subnet in exception.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
                  system_group        = try(length(exception.source.systemGroup), 0) > 0 ? [for group in exception.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
                  group               = try(length(exception.source.group), 0) > 0 ? [for group in exception.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
                  user                = try(length(exception.source.user), 0) > 0 ? [for user in exception.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
                } : k => v if v != null
              }
            },

            # Exception destination - always required
            {
              destination = {
                for k, v in {
                  app_category = try(length(exception.destination.appCategory), 0) > 0 ? [for cat in exception.destination.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

                  application = try(length(exception.destination.application), 0) > 0 ? [for app in exception.destination.application : can(app.name) ? { name = app.name } : { id = app.id }] : null

                  custom_app = try(length(exception.destination.customApp), 0) > 0 ? [for app in exception.destination.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null

                  custom_category = try(length(exception.destination.customCategory), 0) > 0 ? [for cat in exception.destination.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

                  sanctioned_apps_category = try(length(exception.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in exception.destination.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

                  domain = try(length(exception.destination.domain), 0) > 0 ? exception.destination.domain : null

                  fqdn = try(length(exception.destination.fqdn), 0) > 0 ? exception.destination.fqdn : null

                  country = try(length(exception.destination.country), 0) > 0 ? [for country in exception.destination.country : can(country.name) ? { name = country.name } : { id = country.id }] : null

                  ip_range = try(length(exception.destination.ipRange), 0) > 0 ? [for range in exception.destination.ipRange : {
                    from = range.from
                    to   = range.to
                  }] : null
                } : k => v if v != null
              }
            },

            # Exception service - always required
            {
              service = {
                for k, v in {
                  standard = try(length(exception.service.standard), 0) > 0 ? [for svc in exception.service.standard : can(svc.name) ? { name = svc.name } : { id = svc.id }] : null

                  custom = try(length(exception.service.custom), 0) > 0 ? [for svc in exception.service.custom : {
                    protocol = svc.protocol
                    port     = try(length(svc.port), 0) > 0 ? [for p in svc.port : tostring(p)] : null
                    port_range = try(svc.portRangeCustomService, null) != null ? {
                      from = tostring(svc.portRangeCustomService.from)
                      to   = tostring(svc.portRangeCustomService.to)
                    } : null
                  }] : null
                } : k => v if v != null
              }
            }
          )
        ]
      } : {}
    )
  }
}

# Safety guard: for_each over an empty main_rules_data would otherwise plan to
# silently destroy every live rule. A precondition on a rule resource would
# never run with 0 for_each instances, so it lives on this standalone resource.
resource "terraform_data" "guard_empty_policy" {
  lifecycle {
    precondition {
      condition     = var.allow_empty_policy || length(local.main_rules_data) > 0
      error_message = "Policy JSON contains 0 rules. If intentional (greenfield/teardown), set allow_empty_policy = true. A truncated or wrong-tenant export would otherwise destroy the entire live policy."
    }
  }
}

resource "cato_wf_section" "sections" {
  for_each = local.sections_data
  at = {
    position = "LAST_IN_POLICY"
  }
  section = {
    name = each.value.section_name
  }
}

resource "cato_wf_rule" "rules" {
  depends_on = [cato_wf_section.sections]
  for_each   = { for rule in local.main_rules_data : rule.rule.name => rule }

  at = {
    position = "LAST_IN_POLICY" // adding last to reorder in cato_bulk_wf_move_rule
  }

  rule = local.rule_bodies[each.value.rule.name]

  lifecycle {
    ignore_changes = [at] # create-only positioning; ordering owned by the move resource
  }
}

# ─────────────────────────────────────────────────────────────────────────
# Sub-policies. Keyed by sub_policy_name (globally unique, same constraint
# as rule names). Same design as bulk-if-rules.
# ─────────────────────────────────────────────────────────────────────────
resource "cato_wf_sub_policy" "sub_policies" {
  depends_on = [cato_wf_section.sections]
  for_each   = local.sub_policies_data

  name        = each.value.sub_policy_name
  description = try(each.value.description, "")

  # Cleanup rule: the API auto-creates one per sub-policy; when the export
  # nests it (sub_policies[].cleanup_rule) manage it with the configured body,
  # otherwise omit it and adopt the API default.
  cleanup_rule = try(local.rule_bodies[each.value.cleanup_rule.rule.name], null)

  # Position: LAST_IN_SECTION under the parent section from this sub-policy's
  # entry_type == "sub_policy" row; LAST_IN_POLICY when that section is not
  # managed by this module.
  at = contains(keys(local.sections_data), try(local.sub_policy_parent_section[each.key], "")) ? {
    position = "LAST_IN_SECTION"
    ref      = cato_wf_section.sections[local.sub_policy_parent_section[each.key]].id
    } : {
    position = "LAST_IN_POLICY"
  }

  # Scope: the SUB_POLICY_SCOPE rule's matching criteria. action/name/
  # description are Computed on the provider's scope attribute and must NOT
  # be passed; tracking is API-rejected on scoping rules and omitted. enabled
  # comes from scope_enabled (the scope rule's flag — the one terraform can
  # manage; each.value.enabled mirrors the sub-policy object's own
  # policy.enabled, which is not settable via the public API).
  scope = merge(
    {
      enabled     = try(each.value.scope_enabled, true)
      direction   = try(each.value.scope.direction, "TO")
      application = {}
      destination = {}
      service     = {}
    },

    # Only include connection_origin if it exists
    try(each.value.scope.connectionOrigin, null) != null ? {
      connection_origin = each.value.scope.connectionOrigin
    } : {},

    # Only include device_os if it exists and is not empty
    try(length(each.value.scope.deviceOS), 0) > 0 ? {
      device_os = each.value.scope.deviceOS
    } : {},

    # Only include country if it exists and is not empty
    try(length(each.value.scope.country), 0) > 0 ? {
      country = [for country in each.value.scope.country : can(country.name) ? { name = country.name } : { id = country.id }]
    } : {},

    # Only include device if it exists and is not empty
    try(length(each.value.scope.device), 0) > 0 ? {
      device = [for device in each.value.scope.device : can(device.name) ? { name = device.name } : { id = device.id }]
    } : {},

    length(keys(try(each.value.scope.deviceAttributes, {}))) > 0 ? {
      device_attributes = {
        for k, v in each.value.scope.deviceAttributes : k => length(v) > 0 ? v : null
      }
    } : {},

    # Dynamic source block - include if source exists (even if empty)
    try(each.value.scope.source, null) != null ? {
      source = {
        for k, v in {
          ip          = try(length(each.value.scope.source.ip), 0) > 0 ? each.value.scope.source.ip : null
          host        = try(length(each.value.scope.source.host), 0) > 0 ? [for host in each.value.scope.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null
          site        = try(length(each.value.scope.source.site), 0) > 0 ? [for site in each.value.scope.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null
          users_group = try(length(each.value.scope.source.usersGroup), 0) > 0 ? [for group in each.value.scope.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
          subnet      = try(length(each.value.scope.source.subnet), 0) > 0 ? each.value.scope.source.subnet : null
          ip_range = try(length(each.value.scope.source.ipRange), 0) > 0 ? [for range in each.value.scope.source.ipRange : {
            from = range.from
            to   = range.to
          }] : null
          network_interface   = try(length(each.value.scope.source.networkInterface), 0) > 0 ? [for ni in each.value.scope.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null
          floating_subnet     = try(length(each.value.scope.source.floatingSubnet), 0) > 0 ? [for subnet in each.value.scope.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          site_network_subnet = try(length(each.value.scope.source.siteNetworkSubnet), 0) > 0 ? [for subnet in each.value.scope.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null
          system_group        = try(length(each.value.scope.source.systemGroup), 0) > 0 ? [for group in each.value.scope.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null
          group               = try(length(each.value.scope.source.group), 0) > 0 ? [for group in each.value.scope.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null
          user                = try(length(each.value.scope.source.user), 0) > 0 ? [for user in each.value.scope.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null
          global_ip_range     = try(length(each.value.scope.source.globalIpRange), 0) > 0 ? [for range in each.value.scope.source.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
        } : k => v if v != null
      }
    } : {}
  )
}

# ─────────────────────────────────────────────────────────────────────────
# Sub-rules: rules owned by a sub-policy, keyed "<sub_policy_name>::
# <rule_name>". `at` is always LAST_IN_POLICY — the provider repositions the
# rule inside the sub-policy, before its cleanup rule, automatically.
# Ordering WITHIN a sub-policy is creation-order best-effort (see
# unordered_sub_policy_rules output).
# ─────────────────────────────────────────────────────────────────────────
resource "cato_wf_rule" "sub_rules" {
  depends_on = [cato_wf_sub_policy.sub_policies]
  for_each   = { for rule in local.sub_rules_data : "${rule.sub_policy_name}::${rule.rule.name}" => rule }

  sub_policy_id = cato_wf_sub_policy.sub_policies[each.value.sub_policy_name].id

  at = {
    position = "LAST_IN_POLICY"
  }

  rule = local.rule_bodies[each.value.rule.name]

  lifecycle {
    ignore_changes = [at] # create-only positioning; ordering owned by the move resource
  }
}

resource "cato_bulk_wf_move_rule" "all_wf_rules" {
  depends_on = [cato_wf_section.sections, cato_wf_rule.rules, cato_wf_sub_policy.sub_policies]
  rule_data = merge(
    {
      for row in local.main_policy_rule_rows : row.rule_name => {
        rule_name        = row.rule_name
        section_name     = row.section_name
        index_in_section = row.index_in_section
        id               = cato_wf_rule.rules[row.rule_name].rule.id
      }
    },
    {
      for row in local.sub_policy_scope_move_rows : row.rule_name => {
        rule_name        = row.rule_name
        section_name     = row.section_name
        index_in_section = row.index_in_section
        id               = cato_wf_sub_policy.sub_policies[row.rule_name].scope_rule_id
      }
    }
  )
  section_data = {
    for name, section in local.sections_data : name => {
      section_name  = section.section_name
      section_index = section.section_index
      id            = cato_wf_section.sections[name].id
    }
  }
  section_to_start_after_id = var.section_to_start_after_id != null ? var.section_to_start_after_id : null
}
