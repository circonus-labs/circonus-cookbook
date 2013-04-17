include CirconusApiMixin

def load_current_resource
  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end

  @current_resource = Chef::Resource::CirconusRuleSet.new(new_resource.name)
  @new_resource.current_resource_ref(@current_resource) # Needed for datapoints to link to 

  # If ID was provided, copy it into the existing resource
  @current_resource.id(@new_resource.id)

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  if @current_resource.id then
    # We claim the graph already exists
    begin
      payload = api.get_graph(@current_resource.id)
    rescue RestClient::ResourceNotFound
      raise Chef::Exceptions::ConfigurationError, "Circonus graph ID #{@current_resource.id} does not appear to exist.  Don't specify the ID if you are trying to create it."
    end

    @current_resource.payload(payload)
    @current_resource.exists(true)
  else
    # Don't know if the graph exists or not - look for it by title
    ids = api.find_graph_ids(@new_resource.title)

    unless (ids.empty?) then 
      unless (ids.length == 1) then 
        # uh-oh
        raise Chef::Exceptions::ConfigurationError, "More than one circonus graph exists with title '#{new_resource.title}' - saw #{ids.join(', ')} .  You need to specify which ID you are referring to."
      end
      # Found it - set the ID on the graph resource
      @current_resource.id(ids[0])
      @current_resource.payload(api.get_graph(@current_resource.id()))
      @current_resource.exists(true)
    end
  end

  # If the graph currently exists, then copy in to the new resource.
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
    'access_keys' => [],
    'composites' => [],
    'datapoints' => [],
    'guides' => [],
    'style' => 'line',
  }
  @new_resource.payload(payload)
end

def copy_resource_attributes_into_payload

  p = @new_resource.payload

  [
   'max_left_y',
   'max_right_y',
   'min_left_y',
   'min_right_y',
   'style',
   'title',
  ].each do |field|
    value = @new_resource.method(field).call
    unless value.nil? then
      @new_resource.payload[field] = value.to_s
    end
  end

  # Datapoints gets populated by circonus_graph_datapoint resources
  # access keys - not touched
  # guides - not touched
  # composites - not touched

  
end

def any_payload_changes?
  changed = false

  # We don't look at graph_datapoints, because when a datapoint changes, it sends
  # an upload action notification to us anyway

  # We don't manage guides, composites, or access keys

  # These can all legitamitely change

  [
   'max_left_y',
   'max_right_y',
   'min_left_y',
   'min_right_y',
   'style',
   'title',
  ].each do |field|
    old = @current_resource.payload[field].to_s
    new = @new_resource.payload[field].to_s
    this_changed = old != new
    if this_changed then
      Chef::Log.info("Circonus graph '#{@new_resource.name} shows field #{field} changed from '#{old}' to '#{new}'")
    end
    changed ||= this_changed
  end

  return changed

end

def ensure_all_datapoints_have_check_id_present

  @new_resource.payload['datapoints'].each do |datapoint_payload|
    if datapoint_payload['check_id'].nil? then

      if (datapoint_payload['check_bundle_id'].nil?) then
        # Well, hopefully the metric resource has been uploaded by now, 
        # and so we can get the check bundle ID from it.
        datapoint_payload['check_bundle_id'] = datapoint_payload['metric_resource'].check_bundle_resource.id
      end

      # Ok, convert the check_bundle_id and broker_name into a check_id
      datapoint_payload['check_id'] = api.find_check_id(datapoint_payload['check_bundle_id'], datapoint_payload['broker_name'])

      # Remove our notes from the payload - circonus doesn't like extra params
      datapoint_payload.delete('metric_resource')
      datapoint_payload.delete('check_bundle_id')
      datapoint_payload.delete('broker_name')      
    end
  end
end



def action_create
  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_graph[#{@current_resource.name}] because node[:circonus][:enabled] is false")
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

  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_graph[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  # At this point we assume @new_resource.payload is correct
  Chef::Log.debug("About to upload graph, have payload:\n" + JSON.pretty_generate(@new_resource.payload))

  ensure_all_datapoints_have_check_id_present

  if @new_resource.exists then
    Chef::Log.info("Circonus graph upload: EDIT mode, id " + @new_resource.id)
    api.edit_graph(@new_resource.id, @new_resource.payload)
  else
    Chef::Log.info("Circonus graph upload: CREATE mode")
    api.create_graph(@new_resource.payload)
  end
  @new_resource.updated_by_last_action(true)
end

