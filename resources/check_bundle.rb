actions :create, :upload # :delete # TODO
attribute :display_name, :name_attribute
attribute :target
attribute :timeout, :kind_of => Integer, :default => 10
attribute :period, :kind_of => Integer, :default => 60
attribute :type, { :required => true, :kind_of => [Symbol, String] }
attribute :brokers
attribute :id, :kind_of => String, :regex => /^\d+$/
attribute :config, :kind_of => Hash, :default => {}

# TODO - these should be private or readonly
attribute :exists, :kind_of => [TrueClass, FalseClass], :default => false
attribute :payload, :kind_of => Hash

# Gross hack so metric resources can find both the new_resouce and current_resource
attribute :current_resource_ref


def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
end
