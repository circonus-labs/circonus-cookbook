
# Circonus v2 API Client Library for chef-solo
#
# Extremely loosely based on code by Adam Jacob 
#   https://github.com/adamhjk/ruby-circonus/blob/master/lib/circonus.rb
#
# Author: Clinton Wolfe:: Clinton Wolfe (<clinton@omniti.com>)
# Copyright:: Copyright (c) 2012 OmniTI, Inc.
# License:: Apache License, Version 2.0
# 
# Original Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2010 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require 'json'
require 'rest_client'
require 'uri'
require 'fileutils'

if RUBY_VERSION =~ /^1\.8/
  class Dir
    class << self
      def exists? (path)
        File.directory?(path)
      end
      alias_method :exist?, :exists?
    end
  end
end

module RestClient
  class Resource
    unless self.method_defined?(:brackets_orig) then
      alias :brackets_orig :"[]"    
      def [](resource_name)
        brackets_orig(URI.escape(resource_name))      
      end
    end
  end
end

class Circonus
  VERSION = "0.2.0"
  APP_NAME = 'omniti_chef_cookbook'
  DEFAULT_CACHE_PATH = '/var/tmp/chef-circonus'
  DEFAULT_TIMEOUT = 30

  attr_writer :api_token
  attr_reader :rest
  attr_writer :last_request_params
  attr_reader :options

  def initialize(api_token, opts_in={})
    @api_token = api_token
    @options = opts_in
    options[:cache_path] ||= DEFAULT_CACHE_PATH
    options[:timeout]    ||= DEFAULT_TIMEOUT
    options[:halt_on_error] = true if options[:halt_on_error].nil?

    unless Dir.exists?(options[:cache_path]) then
      Dir.mkdir(options[:cache_path])
    end

    headers = {
      :x_circonus_auth_token => @api_token,
      :x_circonus_app_name => APP_NAME,
      :accept => 'application/json',
    }

    @rest = RestClient::Resource.new(options[:api_url], {:headers => headers, :timeout => options[:timeout], :open_timeout => options[:timeout]})

    me_myself = self
    RestClient.add_before_execution_proc { |req, params| me_myself.last_request_params = params }

  end


  def all_string_values(old_hash) 
    new_hash = Hash.new
    old_hash.each { |k,v| new_hash[k.to_s] = old_hash[k].to_s() }
    new_hash
  end


  #==================================================================================#
  #                               LOW-LEVEL  METHDOS
  #==================================================================================#

  rw_resources = [
                  'check_bundle',
                  'rule_set',
                  'graph',
                  'worksheet',
                  'template',
                  'contact_group',
                 ]
  ro_resources = [
                  'broker',
                  'account',
                  'user',
                 ]
  
  def raise_or_warn(ex, blurb)
    
    message = blurb + make_exception_message(ex)

    if options[:halt_on_error] then
      raise message
    else
      if Object.const_defined?('Chef')
        chef_module = Object.const_get('Chef')
        chef_module.const_get('Log').send(:warn, message)
      else
        $stderr.puts "WARN: #{message}"
      end
    end
  end
    
  def bomb_shelter()
    attempts = 0

    begin
      result = yield
     
    rescue RestClient::Unauthorized => ex
      raise_or_warn ex, "Circonus API error - HTTP 401 (API key missing or unauthorized)\nPro tip: you may not have added an API key under the node[:circonus][:api_token] attribute.  Try visiting the Circonus web UI, clicking on your account, then API Tokens, obtaining a token, and adding it to the attributes for this node.\n If you've already obtained a key, make sure it is authorized within Circonus."

    rescue RestClient::Forbidden => ex
      raise_or_warn ex,  "Circonus API error - HTTP 403 (not authorized)\nPro tip: You are accessing a resource you (or rather, your api token) aren't allowed to.  Naughty!\n"

    rescue RestClient::ResourceNotFound => ex
      # Circonus nodes are eventually consistent.  When creating a check and a rule, often the check won't exist yet, according to circonus.  So we get a 404.  Wait and retry.
      attempts = attempts + 1
      if attempts < 3 then
        sleep 1
        retry
      else
        raise_or_warn ex,  "Circonus API error - HTTP 404 (no such resource)\nPro tip: We tried 3 times already, in case Circonus was syncing.  Check the URL.\n"
      end

    rescue RestClient::BadRequest => ex
      # Check for out of metrics
      explanation = JSON.parse(ex.http_body)
      if explanation['message'] == 'Usage limit' then
        raise_or_warn ex,  "Circonus API error - HTTP 400 (Usage Limit)\nPro tip: You are out of metrics!\n"
      else
        raise_or_warn ex,  "Circonus API error - HTTP 400 (we made a bad request)\nPro tip: Circonus didn't like something about the request contents.  It usually gives a detailed error message in the response body.\n"
      end

    rescue RestClient::InternalServerError => ex
      raise_or_warn ex,  "Circonus API error - HTTP 500 (server's brain exploded)\n"

    rescue RestClient::RequestTimeout => ex
      raise_or_warn ex,  "Circonus API error - HTTP Timeout.  Current timeout is #{options[:timeout]}.  You can adjust this setting using the node[:circonus][:timeout] setting.\n"


    end




    result

  end

  def make_exception_message(ex)
    message = ""
    message += "  API token: " + (@last_request_params[:headers] ? @last_request_params[:headers][:x_circonus_auth_token].to_s : 'nil') + "\n"
    message += "        URI: " + @last_request_params[:url].to_s + "\n"
    message += "HTTP Method: " + @last_request_params[:method].to_s.upcase + "\n"
    reqbod = @last_request_params[:payload].nil? ? '' : JSON.pretty_generate(JSON.parse(@last_request_params[:payload]))
    message += (reqbod.empty? ? '' : "Request body:\n" + reqbod + "\n\n")
    message += ((ex.http_body.nil? || ex.http_body.empty?) ? '' : "Response body:\n" + ex.http_body + "\n\n")

    # D-BUG
    # message += @last_request_params.inspect()

    message
    
  end

  #---------------
  # List Methods - list_foos() - GET /v2/<resource>
  #---------------
  [rw_resources, ro_resources].flatten.each do |resource_name| 
    method_name = 'list_' + resource_name + 's'
    send :define_method, method_name do # TODO - one day maybe be able to take filtering args?
      bomb_shelter {
        JSON.parse(@rest[resource_name].get)
      }
    end
  end

  #---------------
  # Get Methods  - get_foo(id) - GET /v2/<resource>/id
  #  Will escalate a 404 if not found
  #---------------
  [rw_resources, ro_resources].flatten.each do |resource_name| 
    method_name = 'get_' + resource_name
    send :define_method, method_name do |resource_id|
      bomb_shelter {
        JSON.parse(@rest[resource_name + '/' + resource_id.to_s].get)
      }
    end
  end

  #---------------
  # Find Methods  - find_foo(id) - GET /v2/<resource>/id
  #  Will return nil if not found
  #---------------
  [rw_resources, ro_resources].flatten.each do |resource_name| 
    method_name = 'find_' + resource_name
    send :define_method, method_name do |resource_id|
      info = nil
      begin
        info = JSON.parse(@rest[resource_name + '/' + resource_id.to_s].get)
      rescue RestClient::ResourceNotFound => ex
        # Do nothing
      rescue Exception => ex
        # Kinda gross, but just hit it again to get error processing
        bomb_shelter {
          info = JSON.parse(@rest[resource_name + '/' + resource_id.to_s].get)
        }
      end
      return info
    end
  end


  #---------------
  # Edit Methods  - edit_foo(id,content_as_ruby_hash) - PUT /v2/<resource>/id
  #---------------
  [rw_resources].flatten.each do |resource_name| 
    method_name = 'edit_' + resource_name
    send :define_method, method_name do |resource_id, content|
      json_content = JSON.generate(content)
      bomb_shelter {
        JSON.parse(@rest[resource_name + '/' + resource_id.to_s].put(json_content))
      }
    end
  end

  #---------------
  # Create Methods  - create_foo(content_as_ruby_hash) - POST /v2/<resource>
  #---------------
  [rw_resources].flatten.each do |resource_name| 
    method_name = 'create_' + resource_name
    send :define_method, method_name do |content|
      json_content = JSON.generate(content)
      bomb_shelter {
        JSON.parse(@rest[resource_name].post(json_content))
      }
    end
  end

  #---------------
  # Delete Methods  - delete_foo(id) - DELETE /v2/<resource>/id
  #---------------
  [rw_resources].flatten.each do |resource_name| 
    method_name = 'delete_' + resource_name
    send :define_method, method_name do |resource_id|
      bomb_shelter {
        rv = @rest[resource_name + '/' + resource_id.to_s].delete
        if rv == '' then 
          return {}
        else          
          JSON.parse(rv)
        end
      }
    end
  end

  #---------------
  # Cache Methods
  #---------------

  def load_cache_file (which)
    if File.exists?(options[:cache_path] + '/' + which) then
      return JSON.parse(IO.read(options[:cache_path] + '/' + which))
    else
      return {}
    end
  end

  def write_cache_file (which, data)
    File.open(options[:cache_path] + '/' + which, 'w') do |file|
      file.print(JSON.pretty_generate(data))
    end
  end

  def clear_cache
    if File.exists?(options[:cache_path]) then
      FileUtils.rm_rf(options[:cache_path])
    end
    Dir.mkdir(options[:cache_path])
  end


  #==================================================================================#
  #                          MID-LEVEL METHODS
  #==================================================================================#
  

  def find_check_bundle_ids(target, type=nil, display_name=nil)
    unless type.nil? then
      type = type.to_s()
    end
    cache = load_cache_file('check_bundle_ids')
    hits = []
    if cache.key?(target) then 
      if type.nil? then
        hits = cache[target].values.flatten
      else
        hits = cache[target][type] || []
      end
    end

    # If we have some hits, and a name was provided, check to see if any of them match the requested name
    if !display_name.nil? then
      hits = hits.select do  |check_bundle_id|
        cb = get_check_bundle(check_bundle_id)
        cb['display_name'] == display_name
      end
    end

    if !hits.empty? then
      return hits
    end

    # Pessimism: if we ended up with 0 hits, go ahead and fetch the whole list

    # list_check_bundles is horrifyingly expensive
    # cache all IDS on that target and type, regardless of name
    matched_bundles = list_check_bundles.find_all do |bundle| 
      match = bundle['target'] == target

      if match then
        cache[target] ||= {}
        cache[target][bundle['type']] ||= []
        cache[target][bundle['type']] << bundle['_cid'].gsub('/check_bundle/', '')
        cache[target][bundle['type']].uniq!
      end

      if match && !type.nil? then
        match = bundle['type'] == type
      end

      match
    end

    write_cache_file('check_bundle_ids', cache)

    if !display_name.nil? then
      matched_bundles = matched_bundles.select do  |cb|
        cb['display_name'] == display_name
      end
    end

    matched_ids = matched_bundles.map { |bundle| bundle['_cid'].gsub('/check_bundle/', '') }
   
  end

  def find_broker_id(name)
    cache = load_cache_file('brokers')
    if cache.key?(name) then 
      return cache[name]
    end

    # If no name in cache file, assume a miss
    
    matched_brokers = list_brokers.find_all do |broker| 
      cache[broker['_name']] = broker['_cid'].gsub('/broker/', '')
      match = broker['_name'] == name

      match
    end

    write_cache_file('brokers', cache)

    if matched_brokers.empty? then
      return nil
    else
      return matched_brokers[0]['_cid'].gsub('/broker/', '')
    end

  end

  def find_check_id(check_bundle_id, broker_name)
    broker_id = find_broker_id(broker_name)

    cache = load_cache_file('check_ids')
    if cache[check_bundle_id] && cache[check_bundle_id][broker_id]  then
      return cache[check_bundle_id][broker_id]
    end

    check_bundle = get_check_bundle(check_bundle_id)

    # TODO - BAD ASSUMPTION
    # Assume that the check indexes match the broker indexes
    found_idx = nil
    check_bundle['brokers'].each_with_index do | broker_path, idx|
      if broker_path == '/broker/' + broker_id then 
        found_idx = idx
      end
    end

    if found_idx.nil? then
      raise "Could not find broker #{broker_name} (id #{broker_id}) on check bundle ID #{check_bundle_id}"
    end

    check_id = check_bundle['_checks'][found_idx].gsub('/check/', '')

    cache[check_bundle_id] ||= {}
    cache[check_bundle_id][broker_id] = check_id
    write_cache_file('check_ids', cache)

    check_id

  end

  def find_contact_group_id(name)
    cache = load_cache_file('contact_groups')
    if cache.key?(name) then 
      return cache[name]
    end

    # If no name in cache file, assume a miss
    
    matched_contact_groups = list_contact_groups.find_all do |contact_group| 
      cache[contact_group['name']] = contact_group['_cid'].gsub('/contact_group/', '')
      match = contact_group['name'] == name

      match
    end

    write_cache_file('contact_groups', cache)

    if matched_contact_groups.empty? then
      return nil
    else
      return matched_contact_groups[0]['_cid'].gsub('/contact_group/', '')
    end

  end


  def find_graph_ids(title)
    cache = load_cache_file('graphs')
    if cache.key?(title) then 
      return cache[title]
    end

    # If no title in cache file, assume a miss
    matched_graphs = list_graphs.find_all do |graph| 
      match = graph['title'] == title

      # Only cache on a match?
      if match then
        cache[graph['title']] ||= []
        id = graph['_cid'].gsub('/graph/', '')
        unless cache[graph['title']].member?(id) then
          cache[graph['title']] << id
        end
      end

      match
    end

    write_cache_file('graphs', cache)
    matched_graph_ids = matched_graphs.map { |bundle| bundle['_cid'].gsub('/graph/', '') }

  end


 
end
