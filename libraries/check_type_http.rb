require File.expand_path(File.dirname(__FILE__) + '/check_type')
class Circonus
  class CheckType
    class Http < Circonus::CheckType
      Circonus::MetricScanner.register_type(:http, self)
   
      COMMON_METRICS = {
        'bytes'      => { :label => 'Bytes received', :type => :numeric },
        'code'    => { :label => 'Response Code', :type => :text }, 
        'duration'    => { :label => 'Duration, total (ms)', :type => :numeric }, 
        'truncated'    => { :label => 'Truncated Payload Indicates (via 1 or 0)', :type => :numeric }, 
        'tt_connect'    => { :label => 'Duration, initial connect (ms)', :type => :numeric },  
        'tt_firstbyte'    => { :label => 'Duration, first byte (ms)', :type => :numeric }, 
      }

      SSL_METRICS = {
        'cert_end'   => { :label => 'SSL Expire on (epoch)', :type => :numeric }, 
        'cert_end_in'   => { :label => 'Certificate time until expire (seconds)', :type => :numeric }, 
        'cert_error'    => { :label => 'SSL Error', :type => :text }, 
        'cert_issuer'    => { :label => 'SSL Issuer', :type => :text }, 
        'cert_start'    => { :label => 'SSL Issued on (epoch)', :type => :numeric }, 
        'cert_subject'    => { :label => 'SSL Subject', :type => :text }, 
      }

      REGEX_METRICS = {
        'body_match' => { :label => 'Body match string', :type => :text },
      }

      def fixed?
        return true # well, sort of
      end

      def all
        metrics = COMMON_METRICS.dup()
        if config[:url] =~ /^https/ then
          metrics.merge!(SSL_METRICS.dup())
        end
        if config[:body] then
          # No support for :extract :(
          metrics.merge!(REGEX_METRICS.dup())
        end

        metrics
      end
    end
  end
end
