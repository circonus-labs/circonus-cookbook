class Circonus

  class MetricScanner
    @@klass_by_type = {}

    def self.get(check_bundle_resource)
      klass = @@klass_by_type[check_bundle_resource.type.to_sym]
      unless klass then
        raise "Sorry, no support in Circonus::MediaScanner for check type '#{check_bundle_resource.type.to_sym}' yet"
      end
      klass.new(check_bundle_resource)
    end

    def self.register_type (type, klass)
      @@klass_by_type[type] = klass
    end                            
  end
  
  class CheckType
    attr_reader :target
    attr_reader :config
    attr_reader :node
    
    include Enumerable


    def initialize (check_bundle_resource)
      @node = check_bundle_resource.node
      @target = check_bundle_resource.target || @node[:circonus][:target] || @node[:fqdn]
      @config = check_bundle_resource.config
    end
    
    def fixed?
      return false
    end    

    def each (&b)
      all.each { |*v| yield *v }
    end

  end
end
