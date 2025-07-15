# Terraform Cato Bulk WAN Firewall Rules Module

This module allows you to bulk import WAN Firewall (WF) rules and sections from a JSON configuration file, and define the order of those rules and sections within the Cato policy.

## Usage

The module reads a JSON configuration file that defines:
- **Rules**: Individual firewall rules with their configurations
- **Sections**: Logical groupings for organizing rules
- **Rule ordering**: Defines which rules belong to which sections and their order within sections

### Basic Example

```hcl
module "bulk_wf_rules" {
  source = "catonetworks/bulk-wf-rules/cato"
  
  wf_rules_json_file_path = "./config_data/all_wf_rules_and_sections_simple_working.json"
  section_to_start_after_id = "existing-section-id" # Optional
}
```

### JSON Configuration Structure

The JSON file should contain a nested structure with the following key components:

- `data.policy.wanFirewall.policy.rules[]` - Array of firewall rules
- `data.policy.wanFirewall.policy.sections[]` - Array of sections with index and name
- `data.policy.wanFirewall.policy.rules_in_sections[]` - Mapping of rules to sections with ordering

#### Key Fields:

**Rules Array**: Each rule contains standard WF rule properties like name, description, enabled status, source, destination, application, action, and tracking settings.

**Sections Array**: Defines sections with:
- `section_index`: The order of the section in the policy
- `section_name`: The display name of the section

**Rules in Sections Array**: Maps rules to sections with:
- `index_in_section`: The order of the rule within its section
- `section_name`: The section this rule belongs to
- `rule_name`: The name of the rule to place in the section

### How Rule Ordering Works

Based on the example:
1. **Section 11** ("My WF Section 11") is created first
2. **Section 22** ("My WF Section 22") is created second
3. **Rule 11** is placed in Section 11 at position 1
4. **Rule 33** is placed in Section 22 at position 1
5. **Rule 22** is placed in Section 22 at position 2

The final policy structure will be:
```
├── My WF Section 11
│   └── My WF Rule 11
└── My WF Section 22
    ├── My WF Rule 33
    └── My WF Rule 22
```

### Parameters

- `wf_rules_json_file_path`: Path to your JSON configuration file
- `section_to_start_after_id`: (Optional) ID of an existing section after which to insert the new sections

<details>
<summary>Click to expand full JSON configuration example</summary>

```json
{
  "data": {
    "policy": {
      "wanFirewall": {
        "policy": {
          "enabled": true,
          "rules": [
            {
              "rule": {
                "name": "My WF Rule 11",
                "description": "My WF Rule 1",
                "enabled": true,
                "direction": "TO",
                "source": {},
                "connectionOrigin": "REMOTE",
                "destination": {},
                "application": {},
                "action": "ALLOW",
                "tracking": {
                  "alert": {
                    "enabled": false,
                    "frequency": "DAILY"
                  },
                  "event": {
                    "enabled": true
                  }
                }
              }
            },
            {
              "rule": {
                "name": "My WF Rule 22",
                "description": "My WF Rule 2",
                "enabled": true,
                "direction": "BOTH",
                "source": {},
                "connectionOrigin": "REMOTE",
                "destination": {},
                "application": {},
                "action": "ALLOW",
                "tracking": {
                  "alert": {
                    "enabled": false,
                    "frequency": "DAILY"
                  },
                  "event": {
                    "enabled": true
                  }
                }
              }
            },
            {
              "rule": {
                "name": "My WF Rule 33",
                "description": "My WF Rule 3",
                "enabled": true,
                "direction": "TO",
                "source": {},
                "connectionOrigin": "REMOTE",
                "destination": {},
                "application": {},
                "action": "ALLOW",
                "tracking": {
                  "alert": {
                    "enabled": false,
                    "frequency": "DAILY"
                  },
                  "event": {
                    "enabled": true
                  }
                }
              }
            }
          ],
          "sections": [
            {
              "section_index": 1,
              "section_name": "My WF Section 11"
            },
            {
              "section_index": 2,
              "section_name": "My WF Section 22"
            }
          ],
          "rules_in_sections": [
            {
              "index_in_section": 1,
              "section_name": "My WF Section 11",
              "rule_name": "My WF Rule 11"
            },
            {
              "index_in_section": 2,
              "section_name": "My WF Section 22",
              "rule_name": "My WF Rule 22"
            },
            {
              "index_in_section": 1,
              "section_name": "My WF Section 22",
              "rule_name": "My WF Rule 33"
            }
          ]
        }
      }
    }
  }
}
```
</details>

## Working with Existing Rules (Brownfield Deployments)

For brownfield deployments where you have existing WAN Firewall rules in your Cato Management Application, you can use the Cato CLI to export and import these rules into Terraform state.

### Installing and Configuring Cato CLI

1. **Install the Cato CLI:**
   ```bash
   pip3 install catocli
   ```

2. **Configure the CLI with your Cato credentials:**
   ```bash
   catocli configure set
   ```
   This will prompt you for your Cato Management Application credentials and account information.

### Exporting Existing Rules

To export your existing WAN Firewall rules and sections into the JSON format required by this module:

```bash
catocli export wf_rules
```

This command will generate a JSON file containing all your existing WF rules and sections in the correct format for this Terraform module.

### Importing Rules into Terraform State

Once you have the JSON configuration file, you can import the existing rules and sections into Terraform state. This is useful for:

- **Brownfield deployments**: Managing existing rules with Terraform
- **Backup and restore**: Restoring rules to a known good state after unintended changes
- **State management**: Bringing existing infrastructure under Terraform control

To import the rules into Terraform state:

```bash
catocli import wf_rules_to_tf config_data/all_wf_rules_and_sections_simple_working.json --module-name=module.wf_rules
```

**Parameters:**
- `config_data/all_wf_rules_and_sections_simple_working.json`: Path to your exported JSON file
- `--module-name=module.wf_rules`: The name of your Terraform module instance

### Typical Brownfield Workflow

1. **Export existing rules:**
   ```bash
   catocli export wf_rules
   ```

2. **Create your Terraform configuration:**
   ```hcl
   module "wf_rules" {
     source = "./terraform-cato-bulk-wf-rules"
     
     wf_rules_json_file_path = "./config_data/all_wf_rules_and_sections_simple_working.json"
   }
   ```

3. **Import existing state:**
   ```bash
   catocli import wf_rules_to_tf config_data/all_wf_rules_and_sections_simple_working.json --module-name=module.wf_rules
   ```

4. **Run Terraform plan to verify:**
   ```bash
   terraform plan
   ```
   This should show no changes if the import was successful.

### Backup and Restore Workflow

If unintended changes are made directly to rules and sections in the Cato Management Application, you can restore to the last known good state:

1. **Apply your last known good configuration:**
    ```bash
    terraform apply
    ```
    This will restore rules and sections to match your Terraform configuration.

2. **Alternatively, re-export and compare:**

    ```bash
    catocli export wf_rules
    ```

## Compare with your existing JSON file to identify changes
   

## Using Module Outputs

The module provides comprehensive outputs that can be used for monitoring, auditing, integration with other systems, and operational insights. Below are practical examples of how to use these outputs in your Terraform configuration.

<details>
<summary>Click to expand example client-side outputs</summary>

```hcl
# Basic deployment information
output "deployment_info" {
  description = "Basic information about the WAN Firewall deployment"
  value = {
    total_sections = module.wf_rules.deployment_summary.total_sections_created
    total_rules    = module.wf_rules.deployment_summary.total_rules_created
    enabled_rules  = module.wf_rules.deployment_summary.enabled_rules_count
    disabled_rules = module.wf_rules.deployment_summary.disabled_rules_count
    source_file    = module.wf_rules.parsed_configuration.source_file_path
  }
}

# Quick reference for rule and section IDs
output "quick_reference" {
  description = "Quick reference maps for rules and sections"
  value = {
    section_ids = module.wf_rules.section_ids
    rule_ids    = module.wf_rules.rule_ids
  }
}

# Security policy overview
output "security_policy_overview" {
  description = "Overview of the security policy configuration"
  value = {
    allow_rules_count = module.wf_rules.deployment_summary.allow_rules_count
    block_rules_count = module.wf_rules.deployment_summary.block_rules_count
    allow_rules       = module.wf_rules.allow_rules
    block_rules       = module.wf_rules.block_rules
    disabled_rules    = module.wf_rules.disabled_rules
  }
}

# Traffic direction analysis
output "traffic_direction_analysis" {
  description = "Analysis of rules by traffic direction (TO, FROM, BOTH)"
  value = {
    rules_by_direction = module.wf_rules.rules_by_direction
    direction_counts = {
      to_direction   = length(module.wf_rules.rules_by_direction.TO)
      from_direction = length(module.wf_rules.rules_by_direction.FROM)
      both_direction = length(module.wf_rules.rules_by_direction.BOTH)
    }
  }
}

# Detailed section structure
output "section_structure" {
  description = "Detailed view of how rules are organized in sections"
  value       = module.wf_rules.sections_to_rules_mapping
}

# Bulk move operation details
output "bulk_move_details" {
  description = "Details about the bulk move operation that organized the rules"
  value       = module.wf_rules.bulk_move_operation
}

# Configuration validation
output "configuration_validation" {
  description = "Validation information about the parsed configuration"
  value = {
    source_file           = module.wf_rules.parsed_configuration.source_file_path
    rules_in_json         = module.wf_rules.parsed_configuration.rules_data_count
    sections_in_json      = module.wf_rules.parsed_configuration.sections_data_count
    rule_mappings_in_json = module.wf_rules.parsed_configuration.rules_mapping_count
    section_order         = module.wf_rules.parsed_configuration.section_names_ordered
    rules_created         = module.wf_rules.deployment_summary.total_rules_created
    sections_created      = module.wf_rules.deployment_summary.total_sections_created
  }
}

# Example: Filtered outputs for specific use cases
output "critical_rules" {
  description = "Example of filtering rules for critical security rules (BLOCK actions)"
  value = {
    block_rule_names = module.wf_rules.block_rules
    block_rule_count = length(module.wf_rules.block_rules)
    block_rule_ids   = [for rule_name in module.wf_rules.block_rules : module.wf_rules.rule_ids[rule_name]]
  }
}

# Example: Rules that might need attention
output "rules_needing_attention" {
  description = "Example of identifying rules that might need attention"
  value = {
    disabled_rules       = module.wf_rules.disabled_rules
    disabled_rules_count = length(module.wf_rules.disabled_rules)
    disabled_rule_ids    = [for rule_name in module.wf_rules.disabled_rules : module.wf_rules.rule_ids[rule_name]]
  }
}

# Example: Direction-specific analysis
output "bidirectional_rules_analysis" {
  description = "Analysis of bidirectional rules that might impact performance"
  value = {
    both_direction_rules = module.wf_rules.rules_by_direction.BOTH
    both_direction_count = length(module.wf_rules.rules_by_direction.BOTH)
    both_direction_rule_ids = {
      for rule_name in module.wf_rules.rules_by_direction.BOTH :
      rule_name => module.wf_rules.rule_ids[rule_name]
    }
  }
}

# Example: Section-specific information
output "section_details" {
  description = "Example of extracting detailed information about sections"
  value = {
    section_names = module.wf_rules.section_names
    sections_with_rule_counts = {
      for section_name, section_data in module.wf_rules.sections_to_rules_mapping :
      section_name => {
        section_id = section_data.section_id
        rule_count = length(section_data.rules)
        rule_names = [for rule in section_data.rules : rule.rule_name]
        rule_directions = {
          for rule in section_data.rules :
          rule.rule_name => try(module.wf_rules.rules[rule.rule_name].rule.direction, "UNKNOWN")
        }
      }
    }
  }
}

# Example: For integration with monitoring systems
output "monitoring_metrics" {
  description = "Example metrics that could be sent to monitoring systems"
  value = {
    deployment_timestamp     = timestamp()
    total_firewall_rules     = module.wf_rules.deployment_summary.total_rules_created
    total_firewall_sections  = module.wf_rules.deployment_summary.total_sections_created
    active_security_rules    = module.wf_rules.deployment_summary.enabled_rules_count
    inactive_security_rules  = module.wf_rules.deployment_summary.disabled_rules_count
    permissive_rules_count   = module.wf_rules.deployment_summary.allow_rules_count
    restrictive_rules_count  = module.wf_rules.deployment_summary.block_rules_count
    bidirectional_rules_count = length(module.wf_rules.rules_by_direction.BOTH)
    inbound_rules_count      = length(module.wf_rules.rules_by_direction.FROM)
    outbound_rules_count     = length(module.wf_rules.rules_by_direction.TO)
    configuration_source     = basename(module.wf_rules.parsed_configuration.source_file_path)
    bulk_move_operation_data = module.wf_rules.bulk_move_operation
  }
}

# Example: For audit and compliance reporting
output "audit_report" {
  description = "Example audit report using module outputs"
  value = {
    deployment_summary = {
      date                = timestamp()
      source_config_file  = module.wf_rules.parsed_configuration.source_file_path
      sections_deployed   = module.wf_rules.deployment_summary.total_sections_created
      rules_deployed      = module.wf_rules.deployment_summary.total_rules_created
      rules_by_status = {
        enabled  = module.wf_rules.deployment_summary.enabled_rules_count
        disabled = module.wf_rules.deployment_summary.disabled_rules_count
      }
      rules_by_action = {
        allow = module.wf_rules.deployment_summary.allow_rules_count
        block = module.wf_rules.deployment_summary.block_rules_count
      }
      rules_by_direction = {
        to_wan   = length(module.wf_rules.rules_by_direction.TO)
        from_wan = length(module.wf_rules.rules_by_direction.FROM)
        both_way = length(module.wf_rules.rules_by_direction.BOTH)
      }
    }
    rule_organization = module.wf_rules.sections_to_rules_mapping
    disabled_rules_list = module.wf_rules.disabled_rules
    block_rules_list    = module.wf_rules.block_rules
    traffic_direction_breakdown = module.wf_rules.rules_by_direction
  }
}

# Example: WAN-specific security analysis
output "wan_security_analysis" {
  description = "WAN-specific security analysis for compliance and monitoring"
  value = {
    outbound_security = {
      total_outbound_rules = length(module.wf_rules.rules_by_direction.TO)
      outbound_allow_rules = [
        for rule_name in module.wf_rules.rules_by_direction.TO :
        rule_name if contains(module.wf_rules.allow_rules, rule_name)
      ]
      outbound_block_rules = [
        for rule_name in module.wf_rules.rules_by_direction.TO :
        rule_name if contains(module.wf_rules.block_rules, rule_name)
      ]
    }
    inbound_security = {
      total_inbound_rules = length(module.wf_rules.rules_by_direction.FROM)
      inbound_allow_rules = [
        for rule_name in module.wf_rules.rules_by_direction.FROM :
        rule_name if contains(module.wf_rules.allow_rules, rule_name)
      ]
      inbound_block_rules = [
        for rule_name in module.wf_rules.rules_by_direction.FROM :
        rule_name if contains(module.wf_rules.block_rules, rule_name)
      ]
    }
    bidirectional_security = {
      total_bidirectional_rules = length(module.wf_rules.rules_by_direction.BOTH)
      bidirectional_allow_rules = [
        for rule_name in module.wf_rules.rules_by_direction.BOTH :
        rule_name if contains(module.wf_rules.allow_rules, rule_name)
      ]
      bidirectional_block_rules = [
        for rule_name in module.wf_rules.rules_by_direction.BOTH :
        rule_name if contains(module.wf_rules.block_rules, rule_name)
      ]
    }
  }
}
```
</details>

### Output Use Cases

These example outputs demonstrate various practical applications:

- **`deployment_info`**: Quick deployment overview for dashboards
- **`quick_reference`**: ID mappings for referencing resources in other modules
- **`security_policy_overview`**: Security-focused analysis of rule actions
- **`traffic_direction_analysis`**: Understanding traffic flow patterns and directions
- **`section_structure`**: Understanding rule organization and hierarchy
- **`bulk_move_details`**: Operational details about the deployment process
- **`configuration_validation`**: Comparing JSON input with actual deployment
- **`critical_rules`**: Filtering for security-critical rules (BLOCK actions)
- **`rules_needing_attention`**: Identifying disabled rules for review
- **`bidirectional_rules_analysis`**: Analyzing rules that affect both inbound and outbound traffic
- **`section_details`**: Detailed section analysis with rule counts and directions
- **`monitoring_metrics`**: Metrics formatted for monitoring systems with WAN-specific counters
- **`audit_report`**: Comprehensive audit trail for compliance with traffic direction breakdown
- **`wan_security_analysis`**: WAN-specific security posture analysis by traffic direction

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_cato"></a> [cato](#requirement\_cato) | 0.0.30 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cato"></a> [cato](#provider\_cato) | 0.0.30 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cato_bulk_wf_move_rule.all_wf_rules](https://registry.terraform.io/providers/terraform-providers/cato/0.0.30/docs/resources/bulk_wf_move_rule) | resource |
| [cato_wf_rule.rules](https://registry.terraform.io/providers/terraform-providers/cato/0.0.30/docs/resources/wf_rule) | resource |
| [cato_wf_section.sections](https://registry.terraform.io/providers/terraform-providers/cato/0.0.30/docs/resources/wf_section) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_section_to_start_after_id"></a> [section\_to\_start\_after\_id](#input\_section\_to\_start\_after\_id) | The ID of the section after which to start adding rules. | `string` | `null` | no |
| <a name="input_wf_rules_json_file_path"></a> [wf\_rules\_json\_file\_path](#input\_wf\_rules\_json\_file\_path) | Path to the json file containing the ifw rule data. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_allow_rules"></a> [allow\_rules](#output\_allow\_rules) | List of rules with ALLOW action |
| <a name="output_block_rules"></a> [block\_rules](#output\_block\_rules) | List of rules with BLOCK action |
| <a name="output_bulk_move_operation"></a> [bulk\_move\_operation](#output\_bulk\_move\_operation) | Details of the bulk move operation |
| <a name="output_deployment_summary"></a> [deployment\_summary](#output\_deployment\_summary) | Summary statistics of the deployment |
| <a name="output_disabled_rules"></a> [disabled\_rules](#output\_disabled\_rules) | List of disabled rule names |
| <a name="output_enabled_rules"></a> [enabled\_rules](#output\_enabled\_rules) | List of enabled rule names |
| <a name="output_parsed_configuration"></a> [parsed\_configuration](#output\_parsed\_configuration) | Parsed configuration data from the JSON file |
| <a name="output_rule_ids"></a> [rule\_ids](#output\_rule\_ids) | Map of rule names to their IDs |
| <a name="output_rule_names"></a> [rule\_names](#output\_rule\_names) | List of all created rule names |
| <a name="output_rules"></a> [rules](#output\_rules) | Map of all created WAN Firewall rules with their details |
| <a name="output_rules_by_direction"></a> [rules\_by\_direction](#output\_rules\_by\_direction) | Rules organized by direction |
| <a name="output_rules_to_sections_mapping"></a> [rules\_to\_sections\_mapping](#output\_rules\_to\_sections\_mapping) | Mapping of rules to their assigned sections with ordering |
| <a name="output_section_ids"></a> [section\_ids](#output\_section\_ids) | Map of section names to their IDs |
| <a name="output_section_names"></a> [section\_names](#output\_section\_names) | List of all created section names |
| <a name="output_sections"></a> [sections](#output\_sections) | Map of all created WAN Firewall sections with their details |
| <a name="output_sections_to_rules_mapping"></a> [sections\_to\_rules\_mapping](#output\_sections\_to\_rules\_mapping) | Mapping of sections to their assigned rules with ordering |
<!-- END_TF_DOCS -->