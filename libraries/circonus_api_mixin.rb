module CirconusApiMixin
  @@circ_client = nil
  def api
    if @@circ_client.nil?
      # Support deprecated 'app_token'
      unless node['circonus']['app_token'].nil? then
        Chef::Log.warn("Attribute node[:circonus][:app_token] is deprecated - use node[:circonus][:api_token]")        
      end
      token = node['circonus']['api_token'].nil? ? node['circonus']['app_token'] : node['circonus']['api_token']
      
      options = { 
        :api_url => node['circonus']['api_url'], 
        :cache_path => node['circonus']['cache_path'],
        :timeout => node['circonus']['timeout'],
        :halt_on_error => node['circonus']['halt_on_error'],
      }

      @@circ_client = Circonus.new(token, options)

      if node['circonus']['clear_cache_on_start'] then
        @@circ_client.clear_cache
      end

    end
    @@circ_client
  end
end
