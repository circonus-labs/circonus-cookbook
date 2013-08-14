actions :create
attribute :metric_name, :name_attribute
attribute :check_bundle
attribute :type, :kind_of => Symbol, :equal_to => [:text, :numeric, :histogram]

attr_accessor :check_bundle_resource
attr_accessor :exists
attr_accessor :current_resource_ref


def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
  @exists = false
end


def to_payload_hash 
  {
    'name' => (self.metric_name() || self.name()),
    'type' => self.type(),    
    # TODO - other fields?
  }
end
