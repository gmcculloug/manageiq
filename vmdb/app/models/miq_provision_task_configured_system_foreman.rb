class MiqProvisionTaskConfiguredSystemForeman < MiqProvisionTask
  # include MiqProvisionMixin
  include_concern 'StateMachine'

  def self.request_class
    MiqProvisionConfiguredSystemRequest
  end

  # def self.base_model
  #   MiqProvision
  # end

  def deliver_to_automate
    super("configured_system_provision", my_zone)
  end

  # def execute_queue
  #   super(:zone        => my_zone,
  #         :msg_timeout => CLONE_SYNCHRONOUS ? CLONE_TIME_LIMIT : MiqQueue::TIMEOUT)
  # end

  # def after_request_task_create
  #   vm_name                      = get_next_vm_name
  #   options[:vm_target_name]     = vm_name
  #   options[:vm_target_hostname] = get_hostname(vm_name)
  #   self.description             = self.class.get_description(self, vm_name)
  #   save
  # end

  # def after_ae_delivery(ae_result)
  #   log_header = "MIQ(#{self.class.name}.after_ae_delivery)"

  #   $log.info("#{log_header} ae_result=#{ae_result.inspect}")

  #   return if ae_result == 'retry'
  #   return if miq_request.state == 'finished'

  #   if ae_result == 'ok'
  #     update_and_notify_parent(:state => "finished", :status => "Ok", :message => "#{request_class::TASK_DESCRIPTION} completed")
  #   else
  #     update_and_notify_parent(:state => "finished", :status => "Error")
  #   end
  # end

  # def self.get_description(prov_obj, vm_name)
  #   request_type = prov_obj.options[:request_type]
  #   title = case request_type
  #           when :clone_to_vm       then "Clone"
  #           when :clone_to_template then "Publish"
  #           else "Provision"
  #           end

  #   "#{title} from [#{prov_obj.vm_template.name}] to [#{vm_name}]"
  # end
end
