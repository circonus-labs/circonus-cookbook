# Circonus Cookbook

## Features:
    * A library class, Circonus, which acts as a Circonus API v2 client
    * Integration with resmon cookbook (TODO)
    * Chef Resources for:
      * circonus_check_bundle
      * circonus_metric
      * circonus_rule_set
      * circonus_rule
      * circonus_graph
      * circonus_graph_datapoint
    * A default recipe that uses the node attributes to create the above resources
    * Ability to ignore configure API timeout and optionally continue despite API errors

## TODO List

    * Most of the resources do not offer :delete actions yet (check_bundle does)
    * Support for graphs in default recipe (attribute walker)
    * Ability to control order of rules
    * LWRP for worksheets

## Recipes

### `circonus` (`circonus::default`)

Optional.  Lets you define circonus check bundles, metrics, and rules via the node's attributes.  See the 'Cookbook Attributes' section for details on the expected attribute structure.

## LWRPs

### circonus_check_bundle

Manages a check bundle on circonus.  Note that you MUST have at least one circonus_metric that refers to the circonus_check_bundle (a limitation of the API).

Actions:
    * :create - Create/Manage the check bundle
    * :delete - Delete the check bundle and all its metrics (WARNING: DATA LOSS).

Resource Attributes:

    * display_name - Display name of bundle, will appear in email subjects.  Uses resource name if not provided.
    * target - Hostname or IP to query.  Defaults to node[:circonus][:target], which defaults to the node's guess_main_ip() according to NetInfo.
    * type - Type of check, like :resmon or :http    
    * brokers - Array of broker names.  Defaults to node[:circonus][:default_brokers]
    * tags - Array of freeform strings to be used as tags in the web UI.  Default [ ] 
    * config - Hash of options specific to the check bundle type.  See https://circonus.com/resources/api/calls#check_bundles 

Example:

    circonus_check_bundle "foo-host Resmon" do
      type :resmon
      # Note that resmon URL MUST end in slash
      config { 'url' => 'http://foo-host.int.omniti.net:81/', 'port' => 81}
    end

### circonus_metric

Manages a metric on circonus.  Each metric must refer to a previously defined circonus_check_bundle resource.

Actions:
    * :create - Create/Manage the metric

Resource Attributes:

    * name - Name of metric.  Consult your check type docs for information on what can go here.  Defaults to resource name.
    * type - Type of value returned - one of :text, :numeric,  or :histogram
    * check_bundle - Name of the check bundle resource that should contain this metric.  Required.

See also: the Circonus::MetricScanner utility library, which helps enumerate available metrics.

Example:

    circonus_metric "Core::Resmon`resmon`configstatus" do
      check_bundle "derm-dev-1 Resmon"
      type :text
    end

### circonus_rule_set

Manages a ruleset on circonus, which allows you to trigger alerts/emails/pages.  Each metric can have 0 or 1 rulesets per broker, and each ruleset may have 0-n rules.  The ruleset gathers together the contact and response information, while the rules define the specific criteria under which the alert(s) will fire.

The name of this resource is arbitrary, but it is suggested that you use 'broker-name/metric-name' since that will be unique.

Actions:
    * :create - Create/manage the metric

Resource Attributes:

    * metric - Name of the circonus_metric resource this ruleset will be bound to.  Must be defined prior to the circonus_rule_set .
    * broker - Name of the circonus broker that is collecting stats for the metric.  You may repeat circonus_rule_sets on the same metric if you specify different brokers.
    * contact_groups - Ruby hash-of-arrays.  Keys are the strings '1','2', .. '5', representing the severity levels.    Values are arrays of string names of contact groups; when a rule fires at that severity level, all of the contact groups specified will be notified.  You may omit entries for which you have no contact groups.
    * derive - Flag indicating whether the metric should be treated as a derivative (ie, watch for changes over time, rather than specific values).  Values are :derive , :counter, or null.
    * link - An arbitrary URL that will be emailed to contact groups, presumably to assist in incident response.
    * notes - Arbitrary text that will be shown in the Circonus Web UI, presumably to assist in incident response.

TODO - add parent attribute

Example:

    circonus_rule_set "agent-il-1/Core::Cpu`local`idle" do
       metric "Core::Cpu`local`idle"
       broker "agent-il-1"
       contact_groups '1' => [ "Chef Admins" ], '2' => [ ]
       link 'http://foo.com'
       notes 'The very model of a modern major general'
    end

### circonus_rule

Manages a single circonus rule.  Relies on the circonus_rule_set resource already being defined.  

BUG: There is no way to manage order of rules via this resource.  Since the first rule to match wins, order matters.

The name of the resource is arbitrary.

Actions:

    * :create - Create/manage a circonus rule.

Resource Attributes:

    * rule_set - Name of a circonus_rule_set chef resource, which must be defined prior to the rule resource.
    * criteria - Operator to use to detect a match of the rule.  Valid values:
        * 'min value' - for numeric metrics
        * 'max value' - for numeric metrics
        * 'match' - exact match for text metrics
        * 'does not match' - exact match for text metrics
        * 'contains' - regex, for text metrics.  If the regex matches, the alert fires.
        * 'does not contain' - regex, for text metrics.  If the regex does not match, the alert fires.
        * 'on change' - for text metrics, compares to last detected value
        * 'on absence' - for all metrics, detects metric loss of signal
    * severity - Integer severity level, 1-5.  If this rule matches, the contact group(s) assigned in the rule_set to this severity level will be notified.
    * value - Operand for those criteria that require one.  String.
    * wait - Integer, delay in minutes to wait before alerting.  Use this to suppress false positives due to transients.

Example:

    circonus_rule "agent-il-1/Core::Cpu`local`idle/25-idle" do
      rule_set "agent-il-1/Core::Cpu`local`idle"
      criteria 'min value'
      value 25
      severity 3
      wait 5
    end

### circonus_graph

Manages a circonus graph.  You can greate a graph independently of any check bundles or metrics.  A graph may have 0 or more graph datapoints, which do rely on metrics.

Name of the resource is used as the graph title.

Actions:

    * :create - Create/Manage the graph

Resource Attributes:

    * id - optional, GUID of the graph.  If provided, you can change the name of the graph; if omitted, changing the name of the graph will create a new graph.
    * style - :line or :area
    * tags - Array of freeform strings to be used as tags in the web UI.  Default [ ] 
    * max_left_y, max_right_y, min_left_y, min_right_y - Y Axis limits

### circonus_graph_datapoint

Manages a data series on a graph.  Relies on a circonus_metric resource definition, as well as agrpah definition.  You must also provide the broker name, so we can resolve the check ID.

The name is used as the display name.  The identity of the data point is derived from the metric and the broker.

Actions:
   
    * :create - Create/Manage a graph data series

Resource Attributes:

    * type - :data, :guide, :composite - :data by default
    * graph - name of the circonus_graph chef resource on which to draw the data
    * metric - name of the circonus_metric chef resource that provides the data
    * broker - name of the broker, used to identify the check
    * axis - :r or :l, which axis the the data should be measured against
    * color - #FF00FF style; if omitted, circonus server will provide a default
    * alpha - float or integer; 0 - 1; defaults to 0.3
    * data_formula - see web UI help; may be left null
    * legend_formula - see web UI help; may be left null
    * hidden - true/false, false default
    * derive - :counter, :derive, :gauge - :gauge is default
    
In order to create a guide, the following attributes can/should be used:

    * type - :guide
    * name
    * color
    * hidden
    * data_formula - ie "90000"
    * legend_formula

For composites, the following attributes can/should be used:

    * type - :composite
    * name
    * color
    * axis
    * hidden
    * data_formula - ie "= 100 * A / (A + B)"
    * legend_formula

## Utility Library

The cookbook includes a utility class, Circonus::MetricScanner, which provides a way to list the metrics available on a proposed check bundle before it is actually created in circonus.  This is needed for check types that can be configured, like nad and resmon.

Example:

    example_check_bundle_name = "nad demo - MetricScanner"
    circonus_check_bundle example_check_bundle_name do 
       type "json:nad"
       config :url => '/'
    end

    # The metrics list is an Enumerable, so you can filter it.
    nad_metrics = Circonus::MetricScanner.get(resources("circonus_check_bundle[#{example_check_bundle_name}]"))
    nad_metrics.select { |name, type|
       name =~ /^cpu`idle/
    }.each do |metric_name, metric_type|
        circonus_metric metric_name + ' on ' + example_check_bundle_name do 
            metric_name metric_name
            check_bundle example_check_bundle_name
            type metric_type
        end
    end

Currently very few check types are supported by MetricScanner - only ping and nad.

## Cookbook Attributes

    :circonus => {

        # Set this to false if you want to disable circonus actions
        :enabled => true,

        # These attributes control behavior of the circonus cookbook at a low-level
        :api_token => 'some-string-here',  # Required - see  https://circonus.com/resources/api#authentication
        # Note: app_token is a deprecated alias for api_token

        :target => 'your-ip',           # By default, uses value of node[:fqdn]
        :default_brokers => [ ],           # List of names of brokers, like 'agent-il-1', to use when creating check bundles        

        # Path to a directory in which we will cache circonus config data
        :cache_path => '/var/tmp/chef-circonus',

        # Set to true to clear the cache at the beginning of each run.  This can help some
        # API errors when nodes are rapidly provisioned/deprovisioned.
        :clear_cache_on_start => false, 

        # Timeout in seconds for API HTTP requests
        :timeout => 10,

        # Set this to false to treat API errors as warnings, continuing the chef run.
        # Not all errors can be ignored.
        :halt_on_error => true,

        # The remaining attrs are a convenience, for creating checks/metrics/rules from node attributes.
        # this tree gets interpreted by the circonus::default recipe
        :check_bundles => {
           'check bundle name' => {
              # These are required
              :type => 'resmon',
              :config => { :foo => 'bar' }, # See Circonus/Noit docs

              # These have defaults
              :target => 'defaults to guess_main_ip',
              :period => 60,
              :timeout => 10,
              :brokers => ['agent-foo-1', 'agent-foo-2'],

              # Deeper....
              :metrics => {
                 # Names of metrics are usually determined by the type of the check bundle
                 'Some::metric' => {
                     :type => :numeric, # or :text or :histogram
                     
                     # You can stop at this point if you don't need alerts or graphs


                     # Rules
                     :rule_set => {
                        # Required
                        :contact_groups => { 
                           '1' => ['You', 'Your Mom'],   # These are names of the contact groups in Circonus; you can't just make them up
                           '3' => ['Bob']
                        },
                        
                        # Optional
                        :link => 'http://helpful.info',
                        :derive => :counter, # null, the default, is most typical
                        :notes => 'If this alarm goes off, you are already doomed.',
                       
                       # The rules themselves
                       :rules => [
                         {
                         :severity => 2,
                         :criteria => 'max value',
                         :value => '40',  
                         :wait => 13 ,
                         },
                         { ... }
                       ]                          
                     }
                 },
                 'Another::metric'  => { ... }
              }

           },
           'check bundle name 2' => { ... }
        }       

    }

# Contributing

The main repo is at https://github.com/omniti-labs/circonus-cookbook - please fork, make a topic branch, and send a pull request when you want to submit.  

# Authors

## Maintainers

  Clinton Wolfe

## Contributors

  Eric Saxby





