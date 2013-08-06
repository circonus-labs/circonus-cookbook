actions :create, :upload #, :delete # TODO

attribute :access_keys, :kind_of => Array, :default => []
# datapoints, guide, and composites are represented by circonus_graph_datapoint resource
attribute :max_left_y, :kind_of => Integer
attribute :max_right_y, :kind_of => Integer
attribute :min_left_y, :kind_of => Integer
attribute :min_right_y, :kind_of => Integer
attribute :style, :kind_of => Symbol 
attribute :title, :kind_of => String, :name_attribute => true
attribute :id
attribute :tags, :kind_of => Array, :default => []

# These are undocumented, but appear in the get_graph API call response
# notes
# description


attribute :exists, :kind_of => [TrueClass, FalseClass], :default => false
attribute :payload
attribute :current_resource_ref


def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
end
