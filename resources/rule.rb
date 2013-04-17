actions :create #, :delete # TODO
attribute :rule_set
attribute :criteria, :kind_of => String, :equal_to => [
                                                       # numeric
                                                       'min value',
                                                       'max value',
                                                       # text
                                                       'match',
                                                       'does not match',
                                                       'contains',
                                                       'does not contain',
                                                       'on change', 
                                                       # either
                                                       'on absence'
                                                      ]
attribute :severity, :kind_of => [String,Integer], :equal_to => [ 1,2,3,4,5,'1', '2', '3', '4', '5']
attribute :value
attribute :wait, :kind_of => [String,Integer], :regex => /^\d+$/, :default => 0



attribute :rule_set_resource
attribute :exists, :kind_of => [TrueClass, FalseClass], :default => false
attribute :current_resource_ref


def initialize(*args)
  super
  @action = :create  # default_action pre 0.10.10
end


def to_payload_hash 
  p =  {
    'criteria' => self.criteria(),
    'severity' => self.severity().to_s(),
    'value'    => self.value().to_s(),
    'wait'     => self.wait().to_s(),
  }

  # Workaround
  if self.criteria == 'on absence' && p['value'].empty? then
    p['value'] = "300"
  end

  p
end
