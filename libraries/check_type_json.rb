require 'open-uri'
require 'json'
require File.expand_path(File.dirname(__FILE__) + '/check_type')

class Circonus
  class CheckType
    class JSON < Circonus::CheckType
      Circonus::MetricScanner.register_type(:'json', self)
      
      def all
        # Discovery via HTTP
        url = config[:url]
        content = open(url).read
        data = ::JSON.parse(content)

        # From JSON Docs link on any Circonus Web UI check page
        # { 
        #   "number": 1.23,
        #   "bignum_as_string": "281474976710656",
        #   "test": "a text string",
        #   "container": { "key1": 1234 },
        #   "array": [  1234, 
        #               "string",
        #               { "crazy": "like a fox" }
        #            ]
        #  }
        # There is no particular data structure required by Circonus; format your data
        # however you wish and Circonus will parse it accordingly. Circonus would parse 
        # the above example into the following metrics ("services" tells how many 
        # metrics resulted from parsing):
        #
        # array`0   1234
        # array`1   string
        # array`2`crazy    like a fox
        # bignum_as_string "281474976710656"
        # container`key   11234
        # number          1.23000000
        # services        7 
        # test            a text string
        
        data = window_dressing(terrifying_flatten(data))

        scan = {}

        data.each do |metric_name, value|
          scan[metric_name] = {
            :label => metric_name, # No way of knowing a prettier name
            :type => value =~ /^\d+(\.\d+)?$/ ? :numeric : :text,
          }
        end

        return scan
      end

      def terrifying_flatten(inbound, prefix = nil)
        outbound = {}
        if inbound.kind_of? (Hash) then
          inbound.each do |key, val|
            if val.kind_of?(Hash) || val.kind_of?(Array)    
              outbound.merge!(terrifying_flatten(val, (prefix ? prefix + '`' : '') + key.to_s))      
            else
              outbound[(prefix ? prefix + '`' : '') + key.to_s] = val
            end
          end
        else
          inbound.each_with_index do |val, key|
            if val.kind_of?(Hash) || val.kind_of?(Array)    
              outbound.merge!(terrifying_flatten(val, (prefix ? prefix + '`' : '') + key.to_s))      
            else
              outbound[(prefix ? prefix + '`' : '') + key.to_s] = val
            end
          end    
        end
        outbound
      end

      # Sort by key (sigh) and inject services count
      def window_dressing(inbound)
        inbound['services'] = inbound.keys.length
        outbound = {}
        inbound.keys.sort.each { |k| outbound[k] = inbound[k] }
        outbound
      end



    end
  end
end
