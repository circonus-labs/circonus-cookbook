actions :create, :upload, :delete
attribute :display_name, :name_attribute
attribute :target
attribute :timeout, :kind_of => Integer, :default => 10
attribute :period, :kind_of => Integer, :default => 60
attribute :type, { :required => true, :kind_of => [Symbol, String] }
attribute :brokers
attribute :id, :kind_of => String, :regex => /^\d+$/
attribute :config, :kind_of => Hash, :default => {}
attribute :tags, :kind_of => Array, :default => []

attr_accessor :exists
attr_accessor :payload
attr_accessor :delete_requested

# Gross hack so metric resources can find both the new_resouce and current_resource
attr_accessor :current_resource_ref


def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
  @exists = false
  @delete_requested = false
end
