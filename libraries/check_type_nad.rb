require 'open-uri'
require 'json'

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
        "s" => :string,
      }.freeze

      def all
        # Discovery via HTTP
        
        # TODO read SSl, path, etc from config
        url = "http://" + target + ":" + node[:nad][:port].to_s + '/'
        content = open(url).read
        data = JSON.parse(content)

        # Data is a HoHoH
        # Top level keys are nad plugin (script) names
        # Next level is individual checks in each plugin
        # Final is type/value hash
        
        # Condense to hash, mapping full name to type
        
        flattened = Hash.new
        data.each do |plugin_name, checks|
          checks.each do |check_name, check_details|
            flattened["#{plugin_name}`#{check_name}"] = NAD_TYPE_TO_CIRCONUS_TYPE[check_details['_type']]
          end
        end
        
        return flattened

      end
    end
  end
end
