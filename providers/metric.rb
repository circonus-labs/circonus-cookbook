include CirconusApiMixin

def load_current_resource

  if @new_resource.current_resource_ref then
    return @new_resource.current_resource_ref
  end
  
  @current_resource = Chef::Resource::CirconusMetric.new(new_resource.name)
  @new_resource.current_resource_ref = @current_resource 

  # Verify that the referenced check_bundle resource exists
  new_check_bundle_resource = run_context.resource_collection.find(:circonus_check_bundle => @new_resource.check_bundle)

  unless new_check_bundle_resource then
    raise Chef::Exceptions::ConfigurationError, "Circonus metric #{@new_resource.name} references check bundle #{@new_resource.check_bundle}, which must exist as a resource (it doesn't)."
  end

  # OK, set check_bundle backlinks
  @new_resource.check_bundle_resource = new_check_bundle_resource 
  current_check_bundle_resource = new_check_bundle_resource.current_resource_ref
  @current_resource.check_bundle_resource = current_check_bundle_resource

  # Copy in name and type - those are the same between existing and desired
  @current_resource.name(@new_resource.name()) # chef resource name
  @current_resource.metric_name(@new_resource.metric_name() || @new_resource.name())  # metric name in circonus
  @current_resource.type(@new_resource.type())

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    return @current_resource
  end

  # Ok, now we do what load_current_resource is really supposed to do - determine the existing state
  
  # Chef::Log.info("In metric.LCR, current check bundle exists is " + @current_resource.check_bundle_resource.exists.inspect)

  # Check to see if the metric exists in the payload of the current (prior state) check_bundle
  if @current_resource.check_bundle_resource.exists then
    # OK, we know we have a payload.  Are we in there as a metric?
    circonus_metric_name = @new_resource.metric_name() || @new_resource.name()

    found = false
    @current_resource.check_bundle_resource.payload['metrics'].each do |cb_payload_metric|
      Chef::Log.debug("CCD Metric - For metric #{@current_resource.name}, comparing my name '#{circonus_metric_name}' to payload name '#{cb_payload_metric['name']}'")      
      Chef::Log.debug("CCD Metric - For metric #{@current_resource.name}, comparing my type '#{@new_resource.type().to_s()}' to payload type '#{cb_payload_metric['type']}'")
      if circonus_metric_name == cb_payload_metric['name'] && @new_resource.type().to_s() == cb_payload_metric['type'] then
        found = true
        break
      end
    end

    Chef::Log.debug("CCD Metric - For metric #{@current_resource.name}, have payload match #{found}")
    
    @current_resource.exists = found 

  else
    @current_resource.exists = false 
  end

  @current_resource

end


def action_create

  # If we are in fact disabled, return now
  unless (node['circonus']['enabled']) then
    Chef::Log.info("Doing nothing for circonus_metric[#{@current_resource.name}] because node[:circonus][:enabled] is false")
    return
  end

  unless @current_resource.exists then
    # Inject myself into my check_bundle's metrics payload
    @new_resource.check_bundle_resource.payload['metrics'] << @new_resource.to_payload_hash()

    # Yes, I changed myself
    @new_resource.updated_by_last_action(true)

    # Inform the check_bundle that yes we will need to do an upload
    @new_resource.notifies(:upload, @new_resource.check_bundle_resource, :delayed)
  end
end
