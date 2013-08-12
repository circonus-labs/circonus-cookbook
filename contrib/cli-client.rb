#!/opt/omni/bin/ruby

# This is the env under which chef-solo executes
require 'rubygems'
Gem.use_paths(Gem.dir, ["/opt/omni/lib/ruby/gems/1.9"])
Gem.refresh

require 'pp'
require 'json'
require 'rest_client'
require '../libraries/circonus_api'

# This makes the REST client library dump debugging into to STDERR
# ENV['RESTCLIENT_LOG'] = 'stderr'

app_token = ENV['CIRCONUS_APP_TOKEN']


# Main circonus API client object.  Use this to run API calls.
options = {
  :api_url => 'https://api.circonus.com/v2/', 
  :cache_path => '/tmp/my-cc',
}
circ = Circonus.new(app_token, options)

# The REST client contained inside the API client.  Use it to diagnose HTTP issues.
rest = circ.rest

#================================================================#
#                 Examples of Using the API
#================================================================#
# The API returns/accepts ruby data structures to match the JSON 
# that the Circonus API expects.

# pp means pretty-print

#pp circ.list_brokers
#pp circ.find_broker_id('agent-il-1')

# pp circ.list_contact_groups()
# pp circ.find_contact_group_id('sysadmins')

# expensive call on a big account!
# pp circ.list_check_bundles

# try this instead - filters on target, and optionally check bundle type
# pp circ.find_check_bundle_ids('185.2.138.140', 'ping_icmp')
# pp circ.find_check_bundle_ids('dev.workingequity.com')

# Once you have an ID, use it
# pp circ.get_check_bundle(5567)

# You can also get a check bundle ID by going to the Web UI, visiting a check URL, and inspecting the source.  (note that a check ID and a check BUNDLE id are different, and we can't really use a check ID easily).


# This looks up a check ID given a check bundle ID and a broker name
# pp circ.find_check_id(4302, 'Ashburn, VA, US')

# You need a check ID to access a rule set
# pp circ.get_rule_set('5833_duration')

# pp circ.list_graphs

# a big, complicated graph
# pp circ.get_graph('fd63af77-84e7-4361-96cc-b418c35baf07')

# The test graph created for derm-dev-1
# pp circ.get_graph('00cbcb61-d46c-4b0f-a51a-1676ddc3a001')

# pp circ.get_rule_set('53160_Core::SmfMaintenance`services`services')


#================================================================#
#                 HAPPY MOTORING
#================================================================#

# pp circ.get_check_bundle(16579);
