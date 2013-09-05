require File.expand_path(File.dirname(__FILE__) + '/check_type')
class Circonus
  class CheckType
    class Ntp < Circonus::CheckType
      Circonus::MetricScanner.register_type(:ntp, self)

      def fixed?
        return true
      end

      def all
        return {
          'clock_name' => { :label => 'Clock name', :type => :text, },
          'delay'      => { :label => 'Delay', :type => :numeric, },
          'dispersion' => { :label => 'Dispersion', :type => :numeric, },
          'jitter'     => { :label => 'Jitter', :type => :numeric, },
          'offset'     => { :label => 'Offset', :type => :numeric, },
          'offset_ms'  => { :label => 'Offset ms', :type => :numeric, },
          'peers'      => { :label => 'Peers', :type => :numeric, },
          'poll'       => { :label => 'Poll', :type => :numeric, },
          'stratum'    => { :label => 'Stratum', :type => :numeric, },
          'when'       => { :label => 'When', :type => :numeric, },
          'xleave'     => { :label => 'Xleave', :type => :numeric, },
        }
      end
    end
  end
end
