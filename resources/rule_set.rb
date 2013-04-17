actions :create, :upload #, :delete # TODO
attribute :metric   # name of a circonus_metric 
attribute :broker   # name of the broker (used to determine check id)
attribute :contact_groups, :kind_of => Hash
attribute :link, :kind_of => String
attribute :notes, :kind_of => String
attribute :derive, :kind_of => Symbol, :equal_to => [:derive, :counter]
# attribute :parent 

attribute :metric_resource
attribute :check_id
attribute :id
attribute :exists, :kind_of => [TrueClass, FalseClass], :default => false
attribute :payload
attribute :current_resource_ref

def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
end
