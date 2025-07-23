locals {
  wf_rules_json          = jsondecode(file("${var.wf_rules_json_file_path}"))
  wf_rules_data          = local.wf_rules_json.data.policy.wanFirewall.policy.rules
  sections_data_unsorted = local.wf_rules_json.data.policy.wanFirewall.policy.sections
  # Create a map with section_index as key to sort sections correctly
  sections_by_index = {
    for section in local.sections_data_unsorted :
    tostring(section.section_index) => section
  }
  # Sort sections by section_index to ensure consistent ordering regardless of JSON file order
  sections_data = [
    for index in sort(keys(local.sections_by_index)) :
    local.sections_by_index[index]
  ]
  rules_data = local.wf_rules_json.data.policy.wanFirewall.policy.rules_in_sections
}

resource "cato_wf_section" "sections" {
  for_each = { for section in local.sections_data : section.section_name => section }
  at = {
    position = "LAST_IN_POLICY"
  }
  section = {
    name = each.value.section_name
  }
}

resource "cato_wf_rule" "rules" {
  depends_on = [cato_wf_section.sections]
  for_each   = { for rule in local.wf_rules_data : rule.rule.name => rule }

  at = {
    position = "LAST_IN_POLICY" // adding last to reorder in cato_bulk_if_move_rule
  }

  rule = merge(
    {
      name      = each.value.rule.name
      enabled   = each.value.rule.enabled
      action    = each.value.rule.action
      direction = each.value.rule.direction
      # Always include tracking block with defaults
      tracking = {
        alert = {
          enabled   = try(each.value.rule.tracking.alert.enabled, false)
          frequency = try(each.value.rule.tracking.alert.frequency, "IMMEDIATE")
        }
        event = {
          enabled = try(each.value.rule.tracking.event.enabled, true)
        }
      }
    },

    # Only include description if it's not empty
    each.value.rule.description != "" ? {
      description = each.value.rule.description
    } : {},

    # Only include connection_origin if it exists
    try(each.value.rule.connectionOrigin, null) != null ? {
      connection_origin = each.value.rule.connectionOrigin
    } : {},

    # Only include device_os if it exists and is not empty
    try(length(each.value.rule.deviceOS), 0) > 0 ? {
      device_os = each.value.rule.deviceOS
    } : {},

    # Only include country if it exists and is not empty
    try(length(each.value.rule.country), 0) > 0 ? {
      country = [for country in each.value.rule.country : can(country.name) ? { name = country.name } : { id = country.id }]
    } : {},

    # Only include device if it exists and is not empty
    try(length(each.value.rule.device), 0) > 0 ? {
      device = [for device in each.value.rule.device : can(device.name) ? { name = device.name } : { id = device.id }]
    } : {},

    # Only include device_attributes if it exists and is not empty
    length(keys(try(each.value.rule.deviceAttributes, {}))) > 0 ? {
      device_attributes = each.value.rule.deviceAttributes
    } : {},

    # Dynamic source block - include if source exists (even if empty)
    try(each.value.rule.source, null) != null ? {
      source = {
        for k, v in {
          ip = try(length(each.value.rule.source.ip), 0) > 0 ? each.value.rule.source.ip : null

          host = try(length(each.value.rule.source.host), 0) > 0 ? [for host in each.value.rule.source.host : can(host.name) ? { name = host.name } : { id = host.id }] : null

          site = try(length(each.value.rule.source.site), 0) > 0 ? [for site in each.value.rule.source.site : can(site.name) ? { name = site.name } : { id = site.id }] : null

          users_group = try(length(each.value.rule.source.usersGroup), 0) > 0 ? [for group in each.value.rule.source.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null

          subnet = try(length(each.value.rule.source.subnet), 0) > 0 ? each.value.rule.source.subnet : null

          ip_range = try(length(each.value.rule.source.ipRange), 0) > 0 ? [for range in each.value.rule.source.ipRange : {
            from = range.from
            to   = range.to
          }] : null

          network_interface = try(length(each.value.rule.source.networkInterface), 0) > 0 ? [for ni in each.value.rule.source.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null

          floating_subnet = try(length(each.value.rule.source.floatingSubnet), 0) > 0 ? [for subnet in each.value.rule.source.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null

          site_network_subnet = try(length(each.value.rule.source.siteNetworkSubnet), 0) > 0 ? [for subnet in each.value.rule.source.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null

          system_group = try(length(each.value.rule.source.systemGroup), 0) > 0 ? [for group in each.value.rule.source.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null

          group = try(length(each.value.rule.source.group), 0) > 0 ? [for group in each.value.rule.source.group : can(group.name) ? { name = group.name } : { id = group.id }] : null

          user = try(length(each.value.rule.source.user), 0) > 0 ? [for user in each.value.rule.source.user : can(user.name) ? { name = user.name } : { id = user.id }] : null

          global_ip_range = try(length(each.value.rule.source.globalIpRange), 0) > 0 ? [for range in each.value.rule.source.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
        } : k => v if v != null
      }
    } : {},

    # Application block - always required for WAN Firewall rules
    {
      application = {
        for k, v in {
          app_category = try(length(each.value.rule.application.appCategory), 0) > 0 ? [for cat in each.value.rule.application.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

          application = try(length(each.value.rule.application.application), 0) > 0 ? [for app in each.value.rule.application.application : can(app.name) ? { name = app.name } : { id = app.id }] : null

          custom_app = try(length(each.value.rule.application.customApp), 0) > 0 ? [for app in each.value.rule.application.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null

          custom_category = try(length(each.value.rule.application.customCategory), 0) > 0 ? [for cat in each.value.rule.application.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

          sanctioned_apps_category = try(length(each.value.rule.application.sanctionedAppsCategory), 0) > 0 ? [for cat in each.value.rule.application.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

          domain = try(length(each.value.rule.application.domain), 0) > 0 ? each.value.rule.application.domain : null

          fqdn = try(length(each.value.rule.application.fqdn), 0) > 0 ? each.value.rule.application.fqdn : null

          ip = try(length(each.value.rule.application.ip), 0) > 0 ? each.value.rule.application.ip : null

          subnet = try(length(each.value.rule.application.subnet), 0) > 0 ? each.value.rule.application.subnet : null

          ip_range = try(length(each.value.rule.application.ipRange), 0) > 0 ? [for range in each.value.rule.application.ipRange : {
            from = range.from
            to   = range.to
          }] : null

          global_ip_range = try(length(each.value.rule.application.globalIpRange), 0) > 0 ? [for range in each.value.rule.application.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
        } : k => v if v != null
      }
    },

    # Dynamic destination block - only if destination has content
    {
      destination = {
        for k, v in {
          app_category = try(length(each.value.rule.destination.appCategory), 0) > 0 ? [for cat in each.value.rule.destination.appCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

          application = try(length(each.value.rule.destination.application), 0) > 0 ? [for app in each.value.rule.destination.application : can(app.name) ? { name = app.name } : { id = app.id }] : null

          custom_app = try(length(each.value.rule.destination.customApp), 0) > 0 ? [for app in each.value.rule.destination.customApp : can(app.name) ? { name = app.name } : { id = app.id }] : null

          custom_category = try(length(each.value.rule.destination.customCategory), 0) > 0 ? [for cat in each.value.rule.destination.customCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

          sanctioned_apps_category = try(length(each.value.rule.destination.sanctionedAppsCategory), 0) > 0 ? [for cat in each.value.rule.destination.sanctionedAppsCategory : can(cat.name) ? { name = cat.name } : { id = cat.id }] : null

          domain = try(length(each.value.rule.destination.domain), 0) > 0 ? each.value.rule.destination.domain : null

          fqdn = try(length(each.value.rule.destination.fqdn), 0) > 0 ? each.value.rule.destination.fqdn : null

          ip = try(length(each.value.rule.destination.ip), 0) > 0 ? each.value.rule.destination.ip : null

          ip_range = try(length(each.value.rule.destination.ipRange), 0) > 0 ? [for range in each.value.rule.destination.ipRange : {
            from = range.from
            to   = range.to
          }] : null

          country = try(length(each.value.rule.destination.country), 0) > 0 ? [for country in each.value.rule.destination.country : can(country.name) ? { name = country.name } : { id = country.id }] : null

          remote_asn = try(length(each.value.rule.destination.remoteAsn), 0) > 0 ? each.value.rule.destination.remoteAsn : null

          host = try(length(each.value.rule.destination.host), 0) > 0 ? [for host in each.value.rule.destination.host : can(host.name) ? { name = host.name } : { id = host.id }] : null

          site = try(length(each.value.rule.destination.site), 0) > 0 ? [for site in each.value.rule.destination.site : can(site.name) ? { name = site.name } : { id = site.id }] : null

          users_group = try(length(each.value.rule.destination.usersGroup), 0) > 0 ? [for group in each.value.rule.destination.usersGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null

          subnet = try(length(each.value.rule.destination.subnet), 0) > 0 ? each.value.rule.destination.subnet : null

          network_interface = try(length(each.value.rule.destination.networkInterface), 0) > 0 ? [for ni in each.value.rule.destination.networkInterface : can(ni.name) ? { name = ni.name } : { id = ni.id }] : null

          floating_subnet = try(length(each.value.rule.destination.floatingSubnet), 0) > 0 ? [for subnet in each.value.rule.destination.floatingSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null

          site_network_subnet = try(length(each.value.rule.destination.siteNetworkSubnet), 0) > 0 ? [for subnet in each.value.rule.destination.siteNetworkSubnet : can(subnet.name) ? { name = subnet.name } : { id = subnet.id }] : null

          system_group = try(length(each.value.rule.destination.systemGroup), 0) > 0 ? [for group in each.value.rule.destination.systemGroup : can(group.name) ? { name = group.name } : { id = group.id }] : null

          group = try(length(each.value.rule.destination.group), 0) > 0 ? [for group in each.value.rule.destination.group : can(group.name) ? { name = group.name } : { id = group.id }] : null

          user = try(length(each.value.rule.destination.user), 0) > 0 ? [for user in each.value.rule.destination.user : can(user.name) ? { name = user.name } : { id = user.id }] : null

          global_ip_range = try(length(each.value.rule.destination.globalIpRange), 0) > 0 ? [for range in each.value.rule.destination.globalIpRange : can(range.name) ? { name = range.name } : { id = range.id }] : null
        } : k => v if v != null
      }
    },

    # Dynamic service block - always include service, even if empty
    {
      service = {
        for k, v in {
          standard = try(length(each.value.rule.service.standard), 0) > 0 ? [for svc in each.value.rule.service.standard : can(svc.name) ? { name = svc.name } : { id = svc.id }] : null

          custom = try(length(each.value.rule.service.custom), 0) > 0 ? [for svc in each.value.rule.service.custom : merge(
            {
              protocol = svc.protocol
            },
            try(svc.port, null) != null ? {
              port = [for p in svc.port : tostring(p)]
            } : {},
            try(svc.portRange, null) != null ? {
              port_range = {
                from = tostring(svc.portRange.from)
                to   = tostring(svc.portRange.to)
              }
            } : {}
          )] : null
        } : k => v if v != null
      }
    },

    # Dynamic schedule block - only if custom schedules exist
    try(each.value.rule.schedule.customTimeframePolicySchedule, null) != null ||
    try(each.value.rule.schedule.customRecurringPolicySchedule, null) != null ||
    try(each.value.rule.schedule.activeOn, "ALWAYS") != "ALWAYS" ? {
      schedule = {
        for k, v in {
          active_on        = try(each.value.rule.schedule.activeOn, "ALWAYS")
          custom_timeframe = try(each.value.rule.schedule.customTimeframePolicySchedule, null)
          custom_recurring = try(each.value.rule.schedule.customRecurringPolicySchedule, null)
        } : k => v if v != null && (k != "active_on" || v != "ALWAYS")
      }
    } : {},

    # Dynamic exceptions block - only if exceptions exist
    try(length(each.value.rule.exceptions), 0) > 0 ? {
      exceptions = [
        for exception in each.value.rule.exceptions : merge(
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
            device_attributes = exception.deviceAttributes
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

                custom = try(length(exception.service.custom), 0) > 0 ? [for svc in exception.service.custom : merge(
                  {
                    protocol = svc.protocol
                  },
                  try(svc.port, null) != null ? {
                    port = [for p in svc.port : tostring(p)]
                  } : {},
                  try(svc.portRangeCustomService, null) != null ? {
                    port_range = {
                      from = tostring(svc.portRangeCustomService.from)
                      to   = tostring(svc.portRangeCustomService.to)
                    }
                  } : {}
                )] : null
              } : k => v if v != null
            }
          }
        )
      ]
    } : {}
  )
}

resource "cato_bulk_wf_move_rule" "all_wf_rules" {
  depends_on = [cato_wf_section.sections, cato_wf_rule.rules]
  rule_data = {
    for rule_mapping in local.rules_data : rule_mapping.rule_name => {
      rule_name        = rule_mapping.rule_name
      section_name     = rule_mapping.section_name
      index_in_section = rule_mapping.index_in_section
      id               = cato_wf_rule.rules[rule_mapping.rule_name].rule.id
    }
  }
  section_data = {
    for section in local.sections_data : section.section_name => {
      section_name  = section.section_name
      section_index = section.section_index
      id            = cato_wf_section.sections[section.section_name].id
    }
  }
  section_to_start_after_id = var.section_to_start_after_id != null ? var.section_to_start_after_id : null
}
