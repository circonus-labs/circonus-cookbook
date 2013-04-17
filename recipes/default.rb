# circonus::default

# Register Circonus checks, metrics, and rules based on the contents of 
# node attributes


# This recipe is kinda stupid - just slavishly translates attribute structures into the equivalent resource structures.

if node['circonus'] && node['circonus']['app_token'] && node['circonus']['check_bundles'] then
  node['circonus']['check_bundles'].each do |check_bundle_name, check_bundle_options|

    # We need to figure out the broker list because we need to loop over 
    # it for rulesets
    brokers = check_bundle_options[:brokers] || node['circonus']['default_brokers']


    #-----------------
    # Check Bundles
    #-----------------
    circonus_check_bundle check_bundle_name do
      type    check_bundle_options[:type].to_sym()
      config  check_bundle_options[:config]
      target  check_bundle_options[:target]
      brokers check_bundle_options[:brokers]
      period  check_bundle_options[:period]
      timeout check_bundle_options[:timeout]
    end


    #-----------------
    # Metrics
    #-----------------
    check_bundle_options[:metrics].each do | metric_name, metric_options | 

      # We need to ensure the chef resource name is unique
      metric_name_for_chef = metric_name + ' on ' + check_bundle_name

      circonus_metric metric_name_for_chef do
        metric_name metric_name
        check_bundle check_bundle_name
        type metric_options[:type].to_sym()        
      end

      #-----------------
      # Rule Sets
      #-----------------    

      if metric_options[:rule_set] then
        
        # Bit of magic here.  Allow metric_options[:rule_set] to be either an array of hashes (you're defining different rulesets for different brokers) OR allow it to be a single hash (one ruleset that applies and should be copied to all brokers).

        rule_sets = []
        if metric_options[:rule_set].kind_of?(Array) then 
          metric_options[:rule_set].each_with_index do |rso, idx|
            unless rso[:broker] then
              raise Chef::Exceptions::ConfigurationError, "Must provide an explicit broker if you are listing rulesets in an array, mr fancy-pants"
            end
            rule_sets << rso
          end
        else
          if metric_options[:rule_set][:broker] then
            raise Chef::Exceptions::ConfigurationError, "Must NOT provide an explicit broker if you are listing rulesets without an array, mr fancy-pants"
          end
          brokers.each do | broker_name |
            # deep clone hack
            rso = Marshal.load(Marshal.dump(metric_options[:rule_set]))
            rso[:broker] = broker_name
            rule_sets << rso
          end
        end

        # ALRIGHTY THEN
        rule_sets.each do |rule_set_options|
          rule_set_name = rule_set_options[:broker] + '/' + metric_name_for_chef
          
          circonus_rule_set rule_set_name do 
            metric metric_name_for_chef
            broker         rule_set_options[:broker]
            contact_groups rule_set_options[:contact_groups]
            link           rule_set_options[:link]
            notes          rule_set_options[:notes]
            derive         rule_set_options[:derive]
          end

          #-----------------
          # Rules
          #-----------------              
          rule_set_options[:rules].each_with_index do |rule, idx|

            # This is an arbitrary name, but should be unique
            rule_name = rule_set_name + '/' + idx.to_s()

            circonus_rule rule_name do 
              rule_set rule_set_name
              severity rule[:severity]
              criteria rule[:criteria]
              value    rule[:value]
              wait     rule[:wait]                
            end
          end
        end
      end
    end
  end
end
