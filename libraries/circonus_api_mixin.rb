module CirconusApiMixin
  @@circ_client = nil
  def api
    if @@circ_client.nil?
      # Support deprecated 'app_token'
      unless node['circonus']['app_token'].nil? then
        Chef::Log.warn("Attribute node[:circonus][:app_token] is deprecated - use node[:circonus][:api_token]")        
      end
      token = node['circonus']['api_token'].nil? ? node['circonus']['app_token'] : node['circonus']['api_token']
      @@circ_client = Circonus.new(token, node['circonus']['api_url'])
    end
    @@circ_client
  end
end
