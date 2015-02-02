$:.push("#{File.dirname(__FILE__)}/../../metadata/VmConfig")
$:.push("#{File.dirname(__FILE__)}/../../metadata/MIQExtract")
# $:.push("#{File.dirname(__FILE__)}/../../util")
# $:.push("#{File.dirname(__FILE__)}/../../VMwareWebService")

# require 'runcmd'
require 'MIQExtract'
require 'VmConfig'
# require 'platform'
# require 'SharedOps'
# require 'MiqVimInventory'
# require 'miq-password'

class FleeceOps
  def SyncMetadata(ost)
    return if !checkArg(ost)
    begin
      raise "No synchronize category specified" if ost.category.nil?
      categories = ost.category.split(",")
      ost.scanTime = Time.now.utc
      ost.compress = true       # Request that data returned from the blackbox is compressed
      ost.xml_class = REXML::Document

      vmName, bb, vmId = nil
      driver = get_ws_driver(ost)
      xml_summary = ost.xml_class.createDoc("<summary/>")
      xmlNode = xml_summary.root.add_element("syncmetadata")
      xml_summary.root.add_attributes({"scan_time"=>ost.scanTime, "taskid"=>ost.taskid})
      ost.skipConfig = true
      vmName = getVmFile(ost)
      bb = Manageiq::BlackBox.new(vmName, ost)

      UpdateAgentState(ost, "Synchronize", "Synchronization in progress")
      categories.each do |c|
        c.gsub!("\"","")
        c.strip!

        # Grab data out of the bb.  (results may be limited by parms in ost like "from_time")
        ret = bb.loadXmlData(c, ost)

        # This logic will convert either libxml or Rexml to a Rexml Element
        xmlNode << ost.xml_class.load(ret.xml.root.shallow_copy.to_xml.to_s).root
        items_total, items_selected = ret.xml.root.attributes["items_total"].to_i, ret.xml.root.attributes["items_selected"].to_i
        data = ret.xml.miqEncode

        # Verify that we have data to send
        unless items_selected.zero?
          $log.info "Starting:  Sending vm data for [#{c}] to server.  Size:[#{data.length}]  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
          driver.SaveVmmetadata(bb.vmId, data, "b64,zlib,xml", ost.taskid)
          $log.info "Completed: Sending vm data for [#{c}] to server.  Size:[#{data.length}]  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
        else
          # Do not send empty XMLs.  Warn if there is not data at all, or just not items selected.
          if items_total.zero?
            $log.warn "Synchronize: No data found for [#{c}].  Items:Total[#{items_total}] Selected[#{items_selected}]  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
          else
            $log.warn "Synchronize: No data selected for [#{c}].  Items:Total[#{items_total}] Selected[#{items_selected}]  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
          end
        end
      end
    rescue => syncErr
    ensure
      if bb
        bb.postSync()
        bb.close
      end

      $log.info "Starting:  Sending vm summary to server.  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
      driver.SaveVmmetadata(vmId, xml_summary.miqEncode, "b64,zlib,xml", ost.taskid)
      $log.info "Completed: Sending vm summary to server.  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"

      UpdateAgentState(ost, "Synchronize", "Synchronization complete")

      raise syncErr if syncErr
    end
    ost.value = "OK\n"
  end

  def ScanMetadata(ost)
    return if !checkArg(ost)

    begin
      # Get the YAML from args
      if ost.args[1]
        dataHash = ost.args[1]
        dataHash = dataHash[1..-2] if dataHash[0,1] == '"' and dataHash[-1,1] == '"'
        dataHash = YAML.load(dataHash)
        ost.scanData = dataHash.is_a?(Hash) ? dataHash : {}
      end

      # Initialize stat collection variables
      ost.scanTime = Time.now.utc unless ost.scanTime
      status = "OK"; statusCode = 0; scanMessage = "OK"
      categoriesProcessed = 0
      ost.xml_class = XmlHash::Document

      UpdateAgentState(ost, "Scanning", "Initializing scan")
      vmName, bb, vmId, lastErr, vmCfg = nil
      xml_summary = ost.xml_class.createDoc(:summary)
      xmlNode = xmlNodeScan = xml_summary.root.add_element("scanmetadata")
      xmlNodeScan.add_attributes("start_time"=>ost.scanTime.iso8601)
      xml_summary.root.add_attributes("taskid"=>ost.taskid)

      vmName = getVmFile(ost)
      vmCfg = MIQExtract.new(vmName, ost)
      ost.miqVm = vmCfg
      bb = Manageiq::BlackBox.new(vmName, ost)

      vmId = bb.vmId

      # Check if we have a valid filesystem handle to work with.  Otherwise, throw an error.
      raise vmCfg.systemFsMsg unless vmCfg.systemFs

      # Collect data for each of the specified categories
      categories = vmCfg.categories
      categoryCount = categories.length
      categories.each do |c|
        # Update job state
        UpdateAgentState(ost, "Scanning", "Scanning #{c}")
        $log.info "Scanning [#{c}] information.  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"

        # Get the proper xml file
        st = Time.now
        begin
          xml = vmCfg.extract(c) {|scan_data| UpdateAgentState(ost, "Scanning", scan_data[:msg])}
          categoriesProcessed += 1
        rescue NoMethodError => lastErr
          ost.error = "#{lastErr} for VM:[#{vmName}]"
          $log.error "Scanmetadata extract error - [#{lastErr}]"
          $log.error "Scanmetadata extract error - [#{lastErr.backtrace.join("\n")}]"
        rescue => lastErr
          ost.error = "#{lastErr} for VM:[#{vmName}]"
        end
        $log.info "Scanning [#{c}] information ran for [#{Time.now-st}] seconds.  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
        if xml
          xml.root.add_attributes({"created_on" => ost.scanTime.to_i, "display_time" => ost.scanTime.iso8601})
          $log.debug "Writing scanned data to XML for [#{c}] to blackbox."
          bb.saveXmlData(xml, c)
          $log.debug "writing xml complete."
          # This logic will convert either libxml or Rexml to a Rexml Element
          categoryNode = xml_summary.class.load(xml.root.shallow_copy.to_xml.to_s).root
          categoryNode.add_attributes("start_time"=>st.utc.iso8601, "end_time"=>Time.now.utc.iso8601)
          xmlNode << categoryNode
        else
          # Handle categories that we do not expect to return data.
          # Otherwise, log an error if we do not get data back.
          unless c == "vmevents"
            $log.error "Error: No XML returned for category [#{c}]  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
          end
        end
      end
    rescue NoMethodError => scanErr
      lastErr = scanErr
      $log.error "Scanmetadata Error - [#{scanErr}]"
      $log.error "Scanmetadata Error - [#{scanErr.backtrace.join("\n")}]"
    rescue Timeout::Error, StandardError => scanErr
      lastErr = scanErr
    ensure
      vmCfg.close unless vmCfg.nil?
      bb.close if bb

      UpdateAgentState(ost, "Scanning", "Scanning completed.")

      # If we are sent a TaskId transfer a end of job summary xml.
      $log.info "Starting:  Sending scan summary to server.  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"
      if lastErr
        status = "Error"
        statusCode = 8
        statusCode = 16 if categoriesProcessed.zero?
        scanMessage = lastErr.to_s
        $log.error "ScanMetadata error status:[#{statusCode}]:  message:[#{lastErr}]"
        lastErr.backtrace.each {|m| $log.debug m} if $log.debug?
      end
      xmlNodeScan.add_attributes("end_time"=>Time.now.utc.iso8601, "status"=>status, "status_code"=>statusCode.to_s, "message"=>scanMessage)
      driver = get_ws_driver(ost)
      driver.SaveVmmetadata(vmId, xml_summary.to_xml.miqEncode, "b64,zlib,xml", ost.taskid)
      $log.info "Completed: Sending scan summary to server.  TaskId:[#{ost.taskid}]  VM:[#{vmName}]"

        ost.error = "#{lastErr} for VM:[#{vmName}]" if lastErr
      end
    ost.value = "OK\n"
  end

  def UpdateAgentState(ost, state, message)
    ost.agent_state = state
    ost.agent_message = message
    AgentJobState(ost)
  end

  def AgentJobState(ost)
    begin
      driver = get_ws_driver(ost)
      driver.AgentJobState(ost.taskid, ost.agent_state, ost.agent_message) if ost.taskid && ost.taskid.empty? == false
    rescue
    end
  end

  def checkArg(ost)
    if (!ost.args || (ost.args.length == 0))
      ost.error = "Command requires an argument\n"
      ost.show_help = true
      return(false)
    end
    return(true)
  end

  def get_ws_driver(ost)
    @vmdbDriver ||= MiqservicesClient.get_driver(ost.config)
  end
end
