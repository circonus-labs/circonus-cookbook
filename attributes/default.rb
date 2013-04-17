
default['circonus']['enabled'] = true
default['circonus']['app_token'] = nil
default['circonus']['target'] = ''  # Dynamic default to guess_main_ip() from NetInfo
default['circonus']['default_brokers'] = []

# Used by the circonus::default recipe to generate resources from attributes
default['circonus']['check_bundles'] = {}
default['circonus']['graphs'] = {}
default['circonus']['worksheets'] = {}

# By default, use the Circonus SaaS API (override this attribute if using Circonus Inside or Private SaaS)
default['circonus']['api_url'] = 'https://api.circonus.com/v2/'
