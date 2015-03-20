module MiqAeMethodService
  class MiqAeServiceMiqProvisionTask < MiqAeServiceMiqRequestTask

    def statemachine_task_status
      ar_method do
        if ['finished', 'provisioned'].include?(@object.state)
          if @object.status.to_s.downcase == 'error'
            'error'
          else
            'ok'
          end
        else
          'retry'
        end
      end
    end

  end
end
