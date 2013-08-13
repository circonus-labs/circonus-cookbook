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
          'available' => { :label => 'Available (percent)',     :type => :numeric, },
          'average'   => { :label => 'Avg roundtrip (seconds)', :type => :numeric, },
          'maximum'   => { :label => 'Max roundtrip (seconds)', :type => :numeric, },
          'minimum'   => { :label => 'Min roundtrip (seconds)', :type => :numeric, },
          'count'     => { :label => 'Packets sent',            :type => :numeric, },
        }
      end
    end
  end
end
