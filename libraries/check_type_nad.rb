require 'open-uri'
require 'json'
require File.expand_path(File.dirname(__FILE__) + '/check_type')

class Circonus
  class CheckType
    class Nad < Circonus::CheckType
      Circonus::MetricScanner.register_type(:'json:nad', self)
      
      NAD_TYPE_TO_CIRCONUS_TYPE = {
        "i" => :numeric,
        "I" => :numeric,
        "l" => :numeric,
        "L" => :numeric,
        "n" => :numeric,
        "s" => :text,
      }.freeze

      def all
        # Discovery via HTTP
        
        # TODO read SSl, path, etc from config
        url = "http://" + target + ":" + node[:nad][:port].to_s + '/'
        content = open(url).read
        data = ::JSON.parse(content)

        # Data is a HoHoH
        # Top level keys are nad plugin (script) names
        # Next level is individual checks in each plugin
        # Final is type/value hash
        
        # Condense to hash, mapping full name to type
        
        flattened = Hash.new
        data.each do |plugin_name, checks|
          checks.each do |check_name, check_details|
            full_name = "#{plugin_name}`#{check_name}"
            flattened[full_name.to_sym] = {
              :label => full_name,  # No way of knowing a prettier name
              :type  => NAD_TYPE_TO_CIRCONUS_TYPE[check_details['_type']],
              :value  => check_details['_value']
            }
          end
        end
        
        return flattened

      end
    end
  end
end
