include CirconusApiMixin

# Chef child of both graph and metric

def load_current_resource

  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end
  
  @current_resource = Chef::Resource::CirconusGraphDatapoint.new(new_resource.name)
  @new_resource.current_resource_ref(@current_resource)

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  # Verify that the referenced graph resource exists
  new_graph_resource = run_context.resource_collection.find(:circonus_graph => @new_resource.graph)

  unless new_graph_resource then
    raise Chef::Exceptions::ConfigurationError, "Circonus graph_datapoint #{@new_resource.name} references graph #{@new_resource.graph}, which must exist as a resource (it doesn't)."
  end

  # OK, set graph backlinks
  @new_resource.graph_resource(new_graph_resource)
  current_graph_resource = new_graph_resource.current_resource_ref
  @current_resource.graph_resource(current_graph_resource)

  # Verify that the referenced metric exists
  new_metric_resource = run_context.resource_collection.find(:circonus_metric => @new_resource.metric)

  unless new_metric_resource then
    raise Chef::Exceptions::ConfigurationError, "Circonus graph datapoint #{@new_resource.name} references metric #{@new_resource.metric}, which must exist as a resource (it doesn't)."
  end

  # OK, set metric backlinks
  @new_resource.metric_resource(new_metric_resource)
  current_metric_resource = new_metric_resource.current_resource_ref
  @current_resource.metric_resource(current_metric_resource)

  # Copy non volatile fields in 
  @current_resource.broker(@new_resource.broker)
  @current_resource.metric(@new_resource.metric)


  # Check to see if the datapoint exists in the payload of the current (prior state) graph
  if @current_resource.graph_resource.exists && @current_resource.metric_resource.exists then

    # Resolve the metric name and broker to find the check_id
    @current_resource.check_id(api.find_check_id(@current_resource.metric_resource.check_bundle_resource.id, @current_resource.broker))

    # OK, we know we have a payload.  Are we in there as a graph_datapoint?
    match_index = @current_resource.graph_resource.payload['datapoints'].find_index do |datapoint|

      # Careful here.  We want to find any existing datapoint that matches on our identity fields.
      # Which would be the check_id and metric name.  Note that unlike rules and metrics, we do NOT compare on all fields - here, we only compare on our identity fields
      matched = true
      matched &&= datapoint['check_id'].to_s == @current_resource.check_id.to_s
      matched &&= datapoint['metric_name'] == @current_resource.metric
      Chef::Log.debug("Examining existing datapoint: " + datapoint.inspect())
      Chef::Log.debug("Examining current check id: " + @current_resource.check_id.inspect())
      Chef::Log.debug("Matched? " + matched.inspect())
      matched
    end

    Chef::Log.debug("In graph_datapoint.LCR, have match idx " + match_index.inspect())
    unless match_index.nil? then
      @current_resource.exists(true)
      @current_resource.index_in_graph_payload(match_index)      
    end  
  else
    @current_resource.exists(false)
  end

  # If the datapoint currently exists, tell the desired state about it
  if @current_resource.exists then
    @new_resource.exists(true)
    @new_resource.index_in_graph_payload(@current_resource.index_in_graph_payload)
    @new_resource.check_id(@current_resource.check_id)
  end

  @current_resource

end

def any_payload_changes?
  # We can assume we exist, and have a payload index on the graph
  old_payload = @current_resource.graph_resource.payload['datapoints'][@current_resource.index_in_graph_payload]
  new_payload = @new_resource.to_payload_hash
  
  # Assume check_id, metric_name, and metric_type match

  # Treat color special by allowing the server to set a default.
  new_payload['color'] ||= old_payload['color']

  # Treat alpha special by allowing the server to set a default.
  new_payload['alpha'] ||= old_payload['alpha']
  # However, server has a bug; may set alpha to invalid value null.  Check and fix.
  new_payload['alpha'] = new_payload['alpha'].nil? ? 'ff' : new_payload['alpha']
  
  fields = [
            'alpha',
            'axis',
            'data_formula',
            'color',
            'derive',
            'hidden',
            'legend_formula',
            'name',
            'stack',
           ]
  changed = false
  fields.each do | field |
    old = old_payload[field].to_s
    new = new_payload[field].to_s
    this_changed = old != new
    if this_changed then
      Chef::Log.info("Circonus graph datapoint '#{@new_resource.name} shows field #{field} changed from '#{old}' to '#{new}'")
    end
    changed ||= this_changed
  end

  return changed
end

def action_create
  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_graph[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  if @current_resource.exists && any_payload_changes? then

    # REPLACE myself in my graph's datapoints payload
    @new_resource.graph_resource.payload['datapoints'][@new_resource.index_in_graph_payload] = @new_resource.to_payload_hash()
    @new_resource.updated_by_last_action(true)

  elsif !@current_resource.exists then
    # NOTE - we may not have a check_id yet!  Rely on the the graph's :upload action to populate that if needed (since by that point, the metric (and thus the check ID) should exist)
    # Grotesquely, do so using a hack in the check_id field of the payload

    # APPEND myself into my graph's datapoints payload
    @new_resource.graph_resource.payload['datapoints'] << @new_resource.to_payload_hash()
    @new_resource.updated_by_last_action(true)
  end

  if (@new_resource.updated_by_last_action?) then
    # Inform the graph that yes we will need to do an upload
    @new_resource.notifies(:upload, @new_resource.graph_resource, :delayed)    
  end

end
