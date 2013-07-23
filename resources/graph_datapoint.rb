actions :create #, :delete # TODO

attribute :type, :kind_of => Symbol, :equal_to => [:data, :guide, :composite], :default => :data

attribute :graph
attribute :broker # We identify checks by broker
attribute :metric # name of the chef circonus_metric resource
attribute :alpha, :kind_of => Numeric, :default => 0.3,
    :callbacks => {"should be a number between 0 and 1" => lambda {|i| self.validate_alpha(i) } }
attribute :axis, :kind_of => Symbol, :equal_to => [:r, :l], :default => :l
attribute :color, :kind_of => String, :regex => /^\#[0-9a-fA-F]{6}$/
attribute :data_formula 
# This is a true WTF for validation
attribute :derive, :kind_of => Symbol, :equal_to => [:counter, :derive, :gauge], :default => :gauge

attribute :hidden, :kind_of => [TrueClass, FalseClass], :default => false
attribute :legend_formula
attribute :stack # Dunno validation

attribute :exists, :kind_of => [TrueClass, FalseClass], :default => false
attribute :check_id
attribute :current_resource_ref
attribute :graph_resource
attribute :metric_resource
attribute :index_in_graph_payload

def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
end

   # {"axis"=>"r",
   #  "check_id"=>52785,
   #  "color"=>"#caac00",
   #  "data_formula"=>nil,
   #  "derive"=>"counter",
   #  "hidden"=>false,
   #  "legend_formula"=>"auto,2,round",
   #  "metric_name"=>"out_errors",
   #  "metric_type"=>"numeric",
   #  "name"=>"Out Errors",
   #  "stack"=>nil},

def to_payload_hash
  payload = Hash.new()

  payload_fields.each do |field|
    payload[field] = self.method(field).call
  end

  if self.datapoint?
    # BARFY HACK - see provider/graph.rb ensure_all_datapoints_have_check_id_present()
    if payload['check_id'].nil?
      payload['broker_name'] = self.broker()
      # May not have this yet (may not have uploaded the check bundle yet)....
      payload['check_bundle_id'] = self.metric_resource.check_bundle_resource.id
      # .... so store the metric resource the graph resource can try accessing it later
      payload['metric_resource'] = self.metric_resource
    end

    # Copy in metric name and type
    payload['metric_name'] = (self.metric_resource.metric_name || self.metric_resource.name)
    payload['metric_type'] = self.metric_resource.type.to_s
  end

  # TODO - set default color by cycling?

  return payload

end

def datapoint?
  self.type == :data
end

def composite?
  self.type == :composite
end

def guide?
  self.type == :guide
end

def graph_payload
  mapping = {:data => 'datapoints', :composite => 'composites', :guide => 'guides'}
  graph_resource.payload[mapping[self.type]]
end

def payload_fields
  fields = [
    'color',
    'data_formula',
    'hidden',
    'legend_formula',
    'name'
  ]

  if datapoint?
    fields << 'alpha'
    fields << 'check_id'
    fields << 'derive'
  end

  unless guide?
    fields << 'axis'
    fields << 'stack'
  end

  fields
end

private

def self.validate_alpha(i)
  i >= 0 && i <= 1
end
