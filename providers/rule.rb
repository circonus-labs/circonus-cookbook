include CirconusApiMixin

def load_current_resource

  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end
  
  @current_resource = Chef::Resource::CirconusRule.new(new_resource.name)
  @new_resource.current_resource_ref(@current_resource)

  # Verify that the referenced rule_set resource exists
  new_rule_set_resource = run_context.resource_collection.find(:circonus_rule_set => @new_resource.rule_set)

  unless new_rule_set_resource then
    raise Chef::Exceptions::ConfigurationError, "Circonus rule #{@new_resource.name} references rule set #{@new_resource.rule_set}, which must exist as a resource (it doesn't)."
  end

  # OK, set rule_set backlinks
  @new_resource.rule_set_resource(new_rule_set_resource)
  current_rule_set_resource = new_rule_set_resource.current_resource_ref
  @current_resource.rule_set_resource(current_rule_set_resource)

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  # Check to see if the rule exists in the payload of the current (prior state) rule_set
  if @current_resource.rule_set_resource.exists && !@current_resource.rule_set_resource.payload.nil? then
    # OK, we know we have a payload.  Are we in there as a rule?
    match = @current_resource.rule_set_resource.payload['rules'].find do |rule|
      old = api.all_string_values(rule)
      new = @new_resource.to_payload_hash()
      Chef::Log.debug("CCD: Rule - Examining existing rule: " + old.inspect())
      Chef::Log.debug("CCD: Rule - Examining new rule: " + new.inspect())
      Chef::Log.debug("CCD: Rule - Equals? " + (new == old).inspect())
      new == old
    end

    Chef::Log.debug("CCD: Rule - In rule.LCR for #{new_resource.name}, have match " + match.inspect())
    
    @current_resource.exists(!match.nil?)

  else
    @current_resource.exists(false)
  end

  @current_resource

end

def action_create

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_rule[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end


  unless @current_resource.exists then
    # Inject myself into my rule_set's rules payload
    @new_resource.rule_set_resource.payload['rules'] << @new_resource.to_payload_hash()

    # Yes, I changed myself
    @new_resource.updated_by_last_action(true)

    # Inform the rule_set that yes we will need to do an upload
    @new_resource.notifies(:upload, @new_resource.rule_set_resource, :delayed)
  end
end
