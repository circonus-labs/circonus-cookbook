require File.expand_path(File.dirname(__FILE__) + '/check_type')
class Circonus
  class CheckType
    class Ping < Circonus::CheckType
      Circonus::MetricScanner.register_type(:ping_icmp, self)
   
      def fixed?
        return true
      end

      def all
        return {
          'Available (percent)'     => :numeric,
          'Avg roundtrip (seconds)' => :numeric,
          'Max roundtrip (seconds)' => :numeric,
          'Min roundtrip (seconds)' => :numeric,
          'Packets sent'            => :numeric,      
        }
      end
    end
  end
end
