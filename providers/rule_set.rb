include CirconusApiMixin

def load_current_resource
  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end

  @current_resource = Chef::Resource::CirconusRuleSet.new(new_resource.name)
  @new_resource.current_resource_ref(@current_resource) # Needed for rules to link to 

  # Try to find metric among existing resources
  new_metric_resource = run_context.resource_collection.find(:circonus_metric => @new_resource.metric)

  unless new_metric_resource then
    raise Chef::Exceptions::ConfigurationError, "Circonus rule set #{@new_resource.name} references metric #{@new_resource.metric}, which must exist as a resource (it doesn't)."
  end

  # OK, set metric backlinks
  @new_resource.metric_resource(new_metric_resource)
  current_metric_resource = new_metric_resource.current_resource_ref
  @current_resource.metric_resource(current_metric_resource)

  # Copy non volatile fields in 
  @current_resource.broker(@new_resource.broker)
  @current_resource.metric(@new_resource.metric)
  
  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  # Try to figure out if ruleset exists, and if so, get my ID
  if @current_resource.metric_resource.exists then
    # The ID for a ruleset is the check_id + '_' + metric name
    @current_resource.check_id(api.find_check_id(@current_resource.metric_resource.check_bundle_resource.id, @current_resource.broker))
    ruleset_id = @current_resource.check_id + '_' + (@current_resource.metric_resource.metric_name || @current_resource.metric_resource.name)

    @current_resource.id(ruleset_id)

    # It's legit for the metric to exist, but not have a ruleset.  So, call find, not get.
    existing_rule_set = api.find_rule_set(ruleset_id)
    if existing_rule_set then
      @current_resource.payload(existing_rule_set)
      @current_resource.exists(true)
    else
      @current_resource.exists(false)
    end
  end

  # If the ruleset currently exists, then copy in to the new resource.
  if @current_resource.exists then
    # Deep clone
    @new_resource.payload(Marshal.load(Marshal.dump(@current_resource.payload)))
    @new_resource.id(@current_resource.id)
    @new_resource.exists(true)
  else 
    init_empty_payload
  end

  copy_resource_attributes_into_payload

  @current_resource
end

def init_empty_payload
  payload = {
    'contact_groups' => {
      '1' => [], '2' => [], '3' => [], '4' => [],  '5' => [], 
    },
    'rules' => [],
    'link' => '',
    'notes' => '',
    'derive' => nil,
  }
  @new_resource.payload(payload)
end

def copy_resource_attributes_into_payload

  # Wha...?
  init_empty_payload if @new_resource.payload.nil?

  p = @new_resource.payload

  # derive
  p['derive'] = @new_resource.derive

  # notes
  p['notes'] = @new_resource.notes

  # link
  p['link'] = @new_resource.link

  # Contact groups
  1.upto(5) do |sev|
    unless @new_resource.contact_groups[sev.to_s].nil? then
      p['contact_groups'][sev.to_s] = @new_resource.contact_groups[sev.to_s].map do |cg_name|
        cg_id = api.find_contact_group_id(cg_name)
        if cg_id.nil? then 
          raise Chef::Exceptions::ConfigurationError, "Circonus metric #{@new_resource.name} references contact group '#{cg_name}', but I can't find a contact group with that name"
        end
        '/contact_group/' + cg_id
      end
    end
  end
  
  # metric name
  p['metric_name'] = (@new_resource.metric_resource.metric_name || @new_resource.metric_resource.name) # Circonus metric name, NOT chef resource name

  # metric type
  p['metric_type'] = @new_resource.metric_resource.type.to_s

  # check
  if @new_resource.check_id then
    check_id_int = @new_resource.check_id.to_s.gsub('/check/', '')
    p['check'] = '/check/' + check_id_int
  end

  # I have no idea what goes in parent - TODO

  # Rules gets populated by circonus_rule resources
  
end

def any_payload_changes?

  return true if @current_resource.payload.nil?

  changed = false

  # check, metric name, and metric type are identities - must not change

  # We don't look at rules, because when a rule changes, it sends
  # an upload action notification to us anyway

  # These can all legitamitely change

  [ 'link', 'notes', 'derive'].each do |field|   
    old = @current_resource.payload[field].to_s
    new = @new_resource.payload[field].to_s
    this_changed = old != new
    if this_changed then
      Chef::Log.debug("Circonus ruleset shows field #{field} changed from '#{old.to_s}' to '#{new.to_s}'")
    end
    changed ||= this_changed
  end

  1.upto(5) do |sev|
    this_changed = @new_resource.payload['contact_groups'][sev.to_s].sort != @current_resource.payload['contact_groups'][sev.to_s].sort
    if this_changed then
      Chef::Log.debug("Circonus ruleset shows contact group sev #{sev.to_s} changed")
    end
    changed ||= this_changed
  end

  return changed

end

def ensure_check_id_present

  check_id_int = nil

  if @new_resource.payload['check'] then
    check_id_int = @new_resource.payload['check'].gsub('/check/', '')
  elsif @new_resource.check_id then 
    # Maybe we know it, but just didn't pack it?
    check_id_int = @new_resource.check_id.to_s.gsub('/check/', '')
  else
    # Well, we assume that the check_bundle was being created in this chef run
    # and that it has already happened at this point.  We just need to ask circonus 
    # what our check ID is.
    check_id_int = api.find_check_id(@new_resource.metric_resource.check_bundle_resource.id, @new_resource.broker)
  end

  @new_resource.check_id(check_id_int)
  @new_resource.payload['check'] = '/check/' + check_id_int
  @new_resource.id(check_id_int + '_' + (@new_resource.metric_resource.metric_name || @new_resource.metric_resource.name))
    
end

def provide_dummy_values_for_zero_arg_criteria
  # For any rules with criteria 'on absence' or 'on change', no value attribute 
  # should be required, but the API requires one.  
  # Send an empty string as a dummy.
  
  @new_resource.payload['rules'].each do |rule|
    next unless ['on absence', 'on change'].include?(rule['criteria'])
    next if rule.has_key?('value')
    rule['value'] = ''
  end

end


def action_create
  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_rule_set[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  unless @current_resource.exists then
    @new_resource.updated_by_last_action(true)
    @new_resource.notifies(:upload, @new_resource, :delayed)
    return
  end

  if any_payload_changes? then
    @new_resource.updated_by_last_action(true)
    @new_resource.notifies(:upload, @new_resource, :delayed)
    return    
  end

end

def action_upload

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_rule_set[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  # May or may not have a check_id at this point, but we should be able to determine it
  ensure_check_id_present
  provide_dummy_values_for_zero_arg_criteria

  # At this point we assume @new_resource.payload is correct
  Chef::Log.debug("About to upload rule_set, have payload:\n" + JSON.pretty_generate(@new_resource.payload))

  if @new_resource.exists then
    Chef::Log.info("Circonus rule_set upload: EDIT mode, id " + @new_resource.id)
    api.edit_rule_set(@new_resource.id, @new_resource.payload)
  else
    Chef::Log.info("Circonus rule_set upload: CREATE mode")
    api.create_rule_set(@new_resource.payload)
  end
  @new_resource.updated_by_last_action(true)
end

