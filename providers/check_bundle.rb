require 'set'
include CirconusApiMixin

# In our case, we must do some slight discovery on BOTH states
#  because we apply defaults to the @new_resource

def load_current_resource
  # Apply defaults to the desired state
  # TODO - should this be in the resource initialize() ?
  unless @new_resource.target then 
    if self.respond_to?(:guess_main_ip) then
      tgt = node['circonus']['target'].empty? ? guess_main_ip() : node['circonus']['target']
    else
      tgt = node['circonus']['target']
    end
    @new_resource.target(tgt)
  end
  if @new_resource.brokers.nil? then
    @new_resource.brokers(node['circonus']['default_brokers'])
  end

  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end

  @current_resource = Chef::Resource::CirconusCheckBundle.new(new_resource.name)
  @new_resource.current_resource_ref = @current_resource # Needed for metrics, etc to link to 

  # Copy in target and type - those are the same between existing and desired
  @current_resource.target(@new_resource.target())
  @current_resource.type(@new_resource.type())

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  # Ok, now we do what load_current_resource is really supposed to do - determine the existing state

  if @new_resource.id then
    begin
      payload = api.get_check_bundle(@new_resource.id)
    rescue RestClient::ResourceNotFound
      raise Chef::Exceptions::ConfigurationError, "Circonus check bundle ID #{@new_resource.id} does not appear to exists for target #{@current_resource.target}, type #{@current_resource.type}.  Don't specify the ID if you are trying to create it."
    end

    # check type
    unless payload['type'] == @new_resource.type.to_s() then
      raise Chef::Exceptions::ConfigurationError, "Circonus check bundle ID #{@new_resource.id} exists, and is of type #{payload['type']}.  You've requested #{@current_resource.type}, though, and I don't know how to convert check bundle types."
    end

    # TODO check target
    # In theory we could update the check bundle....

    @current_resource.payload = payload
    @current_resource.exists = true
  else

    # No ID provided - do an exhaustive search (though we cache on the target and type)
    ids = api.find_check_bundle_ids(@current_resource.target, @current_resource.type, @new_resource.display_name || @new_resource.name)    
    Chef::Log.debug("<<<<<<< In bundle.LCR, search result for #{new_resource.name} on tgt #{@current_resource.target} type #{@current_resource.type} is " + ids.inspect)

    unless (ids.empty?) then 
      unless (ids.length == 1) then
        raise Chef::Exceptions::ConfigurationError, "More than one #{@current_resource.type}-type check on target #{@current_resource.target} exists with name #{new_resource.name}, which blew my fragile eggshell mind. Bundle IDs: #{ids.join(',')}"
      end

      # Fetch it
      candidate_payload = api.get_check_bundle(ids[0])
      @current_resource.id(ids[0])
      @current_resource.payload = candidate_payload
      @current_resource.exists = true
    end
  end

  # Chef::Log.debug("In bundle.LCR, current check bundle exists is " + @current_resource.exists.inspect)
  if @current_resource.exists then

    # Chef::Log.info(">>>>>>>>In bundle.LCR, current check bundle exists and payload is #{@current_resource.payload.inspect}")
    # WORKAROUND - if a check_bundle has been deleted, it will be returned with a single metric, that is an empty hash.  If so, remove that.
    if ['deleted', 'disabled'].include?(@current_resource.payload['status']) then
      if @current_resource.payload['metrics'].length == 1 && @current_resource.payload['metrics'][0].empty? then
        @current_resource.payload['metrics'] = []
      end
    end

    # Deep clone
    @new_resource.payload = Marshal.load(Marshal.dump(@current_resource.payload))
    @new_resource.id(@current_resource.id)
    @new_resource.exists = true
  else 
    init_empty_payload
  end

  copy_resource_attributes_into_payload

  @current_resource
end

def init_empty_payload
  payload = {
    'metrics' => [],
    'config'  => {},
    'tags'    => [],
  }
  @new_resource.payload = payload
  
end

def copy_resource_attributes_into_payload 
  # target
  @new_resource.payload['target'] = @new_resource.target

  # brokers
  if @new_resource.brokers.empty? then
    raise Chef::Exceptions::ConfigurationError, "Hrm, empty broker list for check bundle #{@new_resource.name}.  Either explicitly set 'brokers' resource attribute, or set node[:circonus][:default_brokers] to an array of broker names."    
  end

  @new_resource.payload['brokers'] = @new_resource.brokers.map { |broker_name|
    broker_id = api.find_broker_id(broker_name)
    if broker_id.nil? then 
      raise Chef::Exceptions::ConfigurationError, "Could not locate a broker ID for a broker with the name '#{broker_name}' - are you sure it's spelled correctly?  Visit https://<your-circonus-server>/brokers to verify the active broker list."
    end
    '/broker/' + broker_id
  }.sort


  @new_resource.payload['type'] = @new_resource.type
  @new_resource.payload['display_name'] = @new_resource.display_name || @new_resource.name
  @new_resource.payload['config'] = @new_resource.config()
  @new_resource.payload['period'] = @new_resource.period()
  @new_resource.payload['timeout'] = @new_resource.timeout()
  @new_resource.payload['tags'] = @new_resource.tags()

end

def any_payload_changes?

  unless @current_resource.exists then
    return true
  end

  changed = false

  # Broker list
  this_changed = Set.new(@current_resource.payload['brokers']) != Set.new(@new_resource.payload['brokers'])
  if (this_changed) then 
    Chef::Log.debug("CCD: Check bundle -Saw change on field broker list")
  end
  changed ||= this_changed

  # Config - compare on string values, but allow server to provide defaults
  old = api.all_string_values(@current_resource.payload['config'])
  new = api.all_string_values(@new_resource.payload['config'])
  Chef::Log.debug("CCD: Check bundle - Examining existing config: " + old.inspect())
  Chef::Log.debug("CCD: Check bundle - Examining new config: " + new.inspect())
  this_changed = false
  (old.keys + new.keys).uniq.each do |key|
    if old.has_key?(key) && new.has_key?(key) && new[key] != old[key] then
      this_changed = true
      Chef::Log.debug("CCD: Check bundle - Saw change on field config/#{key}, changing from #{old[key]} to #{new[key]}")
    elsif (!old.has_key?(key)) && new.has_key?(key) then
      this_changed = true
      Chef::Log.debug("CCD: Check bundle - Saw change on field config/#{key}, creating new value #{new[key]}")
      # If old has a key and new doesn't, no change - that's the server setting a default
    end
    changed ||= this_changed
  end
  
  # Type and display_name are identities

  # Period and timeout are simple strings
  ['period', 'timeout' ].each do |field| 
    this_changed = @current_resource.payload[field].to_s != @new_resource.payload[field].to_s
    if this_changed then
      Chef::Log.debug("CCD: Check bundle - Current #{field}:" + @current_resource.payload[field].inspect())
      Chef::Log.debug("CCD: Check bundle - New #{field}:" + @new_resource.payload[field].inspect())
      Chef::Log.debug("CCD: Check bundle - Saw change on field #{field}")
    end
    changed ||= this_changed
  end

  # Tags is an array of strings - sort and stringify first!
  @current_resource.payload['tags'] ||= []
  @current_resource.payload['tags'] = @current_resource.payload['tags'].map { |t| t.to_s }.sort
  @new_resource.payload['tags'] = @new_resource.payload['tags'].map { |t| t.to_s }.sort
  if @current_resource.payload['tags'] != @new_resource.payload['tags'] then
    changed = true
    Chef::Log.debug("CCD: Check bundle - Saw change on field 'tags' old value #{@current_resource.payload['tags'].join(',')} new value #{@new_resource.payload['tags'].join(',')}")
  end

  changed

end


def action_create

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_check_bundle[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  # We don't actually do anything here
  # Other than decide whether to add a late upload notification  
  
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


def action_delete
  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_check_bundle[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  # We don't actually do anything here
  # Other than decide whether to add a late upload notification  
  unless @current_resource.exists then
    # Chef::Log.info(">>>>>>>CB.action_delete - current resource does not exist - never created?")
    # Never created?
    return
  end

  # Old API bug had two different values for the status
  unless @current_resource.payload['status'] == 'deleted' || @current_resource.payload['status'] == 'disabled' then
    # Chef::Log.info(">>>>>>>CB.action_delete - injecting upload action")
    @new_resource.updated_by_last_action(true)
    @new_resource.delete_requested = true
    @new_resource.notifies(:upload, @new_resource, :delayed)        
  end

end

def action_upload

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_check_bundle[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  # OK, three cases: 
  #  create new check bundle
  #  edit existing check bundle
  #  delete check bundle


  

  if @new_resource.exists && ! @new_resource.delete_requested then
    Chef::Log.info("Upload: EDIT mode, id " + @new_resource.id)

    # Fixup the payload: force the status to be active, if it is currently deleted
    # elsewise circonus throws a 400 error
    if @new_resource.payload['status'] == 'disabled' or @new_resource.payload['status'] == 'deleted' then
      @new_resource.payload['status'] = 'active'
    end

    Chef::Log.debug("About to upload check_bundle, have payload:\n" + JSON.pretty_generate(@new_resource.payload))

    # At this point we assume @new_resource.payload is correct
    # (was set by metrics, probably)
    api.edit_check_bundle(@new_resource.id, @new_resource.payload)

  elsif @new_resource.exists && @new_resource.delete_requested then
    Chef::Log.info("Upload: DELETE mode, id " + @new_resource.id)
    Chef::Log.debug("About to upload check_bundle, have payload:\n" + JSON.pretty_generate(@new_resource.payload))
    api.delete_check_bundle(@new_resource.id)    

  else
    Chef::Log.info("Upload: CREATE mode")
    Chef::Log.debug("About to upload check_bundle, have payload:\n" + JSON.pretty_generate(@new_resource.payload))

    # At this point we assume @new_resource.payload is correct
    # (was set by metrics, probably)
    new_bundle = api.create_check_bundle(@new_resource.payload)

    # parse out and store the ID - we need this in case we are creating dependents (like rulesets) in this run
    @new_resource.id(new_bundle['_cid'].gsub('/check_bundle/', ''))
    @new_resource.current_resource_ref.id(@new_resource.id)
    Chef::Log.debug("New check_bundle id is: #{@new_resource.id}")
  end
  @new_resource.updated_by_last_action(true)
end
