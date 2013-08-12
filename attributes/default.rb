
default['circonus']['enabled'] = true
default['circonus']['app_token'] = nil
default['circonus']['target'] = ''  # Dynamic default to guess_main_ip() from NetInfo
default['circonus']['default_brokers'] = []
# By default, use the Circonus SaaS API (override this attribute if using Circonus Inside or Private SaaS)
default['circonus']['api_url'] = 'https://api.circonus.com/v2/'
default['circonus']['cache_path'] = '/var/tmp/chef-circonus'
default['circonus']['clear_cache_on_start'] = false
default['circonus']['timeout'] = 15
default['circonus']['halt_on_error'] = true


# Used by the circonus::default recipe to generate resources from attributes
default['circonus']['check_bundles'] = {}
default['circonus']['graphs'] = {}
default['circonus']['worksheets'] = {}

